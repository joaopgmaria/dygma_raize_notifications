require "securerandom"
require_relative "keyboard"
require_relative "sections"
require_relative "notification"
require_relative "behaviors"
require_relative "colors"
require_relative "scheme"

module Notifications
  class ConflictError < StandardError; end
  class NotFoundError < StandardError; end

  @mutex    = Mutex.new
  @active   = {}  # section => Notification
  @registry = {}  # id => Notification
  @baseline = {}  # section => snapshot captured before first notification; cleared when section goes idle

  def self.start(section, color, style: "flash", count: nil, force: false, keep_if_same: false)
    raise ArgumentError, "Unknown color '#{color}'. Available: #{COLORS.keys.join(", ")}" unless COLORS.key?(color)

    indices  = Sections.indices_for(section)
    r, g, b  = COLORS[color]
    to_kill  = nil
    id       = nil
    suspend_scheme = false

    @mutex.synchronize do
      was_idle = @active.empty?

      if (existing = @active[section])
        same = existing.color == color && existing.style == style
        return existing.id if keep_if_same && same
        raise ConflictError, "Section '#{section}' already has an active notification" unless force || keep_if_same
        existing.cancel!
        @active.delete(section)
        to_kill = existing
      end

      unless @baseline[section]
        @baseline[section] = section == "all" ? Keyboard.theme : Keyboard.snapshot_indices(indices)
      end

      id           = SecureRandom.hex(4)
      behavior     = Behaviors.for(style)
      notification = Notification.new(
        id: id, section: section, indices: indices,
        r: r, g: g, b: b, color: color, style: style,
        count: count, baseline: @baseline[section]
      )

      @active[section] = notification
      @registry[id]    = notification
      notification.run(behavior, on_finish: method(:_finalize))

      # Suspend scheme after adding to @active so that any concurrent Scheme.restart
      # guard check (Notifications.idle?) sees a non-empty @active and aborts.
      suspend_scheme = was_idle && Scheme.active?
    end

    to_kill&.kill
    Scheme.suspend if suspend_scheme
    id
  end

  # True when no notifications are active. Used as a guard in Scheme.restart.
  def self.idle?
    @mutex.synchronize { @active.empty? }
  end

  def self.cancel(id)
    to_kill = nil

    @mutex.synchronize do
      n = @registry[id]
      raise NotFoundError, "Notification '#{id}' not found" unless n
      return { id: id, status: n.status } unless n.running?

      n.cancel!
      if @active[n.section]&.id == id
        @active.delete(n.section)
        to_kill = n
      end
    end

    # Kill outside the mutex — thread's on_finish handles LED restore after it dies.
    to_kill&.kill
    { id: id, status: "cancelled" }
  end

  def self.cancel_section(section)
    id = @mutex.synchronize { @active[section]&.id }
    raise NotFoundError, "No active notification for section '#{section}'" unless id
    cancel(id)
  end

  def self.get(id)
    @registry[id]&.to_h
  end

  def self.active
    @mutex.synchronize { @active.transform_values(&:id) }
  end

  def self.cancel_all
    to_kill = []
    @mutex.synchronize do
      @active.each_value do |notification|
        notification.cancel!
        notification.skip_restore!
        to_kill << notification
      end
      @active.clear
      @baseline.clear
    end
    to_kill.each(&:kill)
  end

  private

  def self._finalize(notification)
    restart_scheme = false

    @mutex.synchronize do
      notification.complete!
      section = notification.section

      # A newer notification has claimed this section — leave it alone.
      already_superseded = @active[section] && @active[section].id != notification.id

      # Remove from @active now (no-op if cancel() already did it).
      @active.delete(section) if @active[section]&.id == notification.id

      unless already_superseded
        # If all notifications are gone and a scheme is configured, let the scheme
        # restart instead of restoring a static snapshot.
        if @active.empty? && Scheme.active?
          notification.skip_restore!
          restart_scheme = true
        else
          notification.restore
        end
        @baseline.delete(section)
      end
    end

    # Restart outside the mutex. The guard aborts if a new notification sneaked in.
    Thread.new { Scheme.restart { Notifications.idle? } } if restart_scheme
  end
end
