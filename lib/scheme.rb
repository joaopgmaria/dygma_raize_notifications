require_relative "behaviors"
require_relative "colors"

# A persistent background animation that runs independently of notifications.
# Notifications suspend the scheme while active; when the last notification
# finishes the scheme restarts instead of restoring a static snapshot.
module Scheme
  @mutex      = Mutex.new
  @current    = nil   # { style:, color:, r:, g:, b: } or nil
  @thread     = nil
  @pre_scheme = nil   # keyboard LED state captured before the first scheme started

  # Start (or replace) the background scheme animation.
  # On the very first call (no scheme running), captures the current keyboard
  # state so clear() can return to it later.
  def self.set(style, color)
    raise ArgumentError, "Unknown color '#{color}'. Available: #{COLORS.keys.join(", ")}" unless COLORS.key?(color)
    r, g, b = COLORS[color]
    @mutex.synchronize do
      _stop_thread
      # Capture idle theme the first time a scheme starts (in-memory, no serial I/O).
      @pre_scheme ||= Keyboard.idle_theme
      @current = { style: style, color: color, r: r, g: g, b: b }
      _start_thread
    end
  end

  # Stop the scheme, restore the pre-animation keyboard state, and clear config.
  # Returns true if it performed a restore, false if there was nothing to restore.
  def self.clear
    pre = nil
    @mutex.synchronize do
      _stop_thread
      @current    = nil
      pre         = @pre_scheme
      @pre_scheme = nil
    end
    Keyboard.restore_full(pre) if pre
    !pre.nil?
  end

  # Is a scheme configured (even if currently suspended)?
  def self.active?
    @mutex.synchronize { !@current.nil? }
  end

  # Returns { style:, color: } or nil.
  def self.current
    @mutex.synchronize { @current&.slice(:style, :color) }
  end

  # Kill the animation thread but keep @current so it can be restarted.
  def self.suspend
    @mutex.synchronize { _stop_thread }
  end

  # Restart the animation. If the optional guard block returns false the
  # restart is skipped — used to abort if a new notification just started.
  def self.restart(&guard)
    @mutex.synchronize do
      return unless @current
      return if guard && !guard.call
      _stop_thread
      _start_thread
    end
  end

  private_class_method def self._stop_thread
    @thread&.kill
    @thread = nil
  end

  private_class_method def self._start_thread
    c = @current
    return unless c
    @thread = Thread.new do
      behavior = Behaviors.for(c[:style])
      behavior.call("all", nil, c[:r], c[:g], c[:b], nil)
    rescue => e
      warn "[scheme] #{e.message}"
    end
  end
end
