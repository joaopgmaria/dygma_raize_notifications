require_relative "keyboard"

class Notification
  attr_reader :id, :section, :color, :style, :status, :started_at

  def initialize(id:, section:, indices:, r:, g:, b:, color:, style:, count:, baseline:)
    @id         = id
    @section    = section
    @indices    = indices
    @r          = r
    @g          = g
    @b          = b
    @color      = color
    @style      = style
    @count      = count
    @baseline   = baseline
    @status     = "running"
    @started_at = Time.now.iso8601
    @thread     = nil
  end

  def run(behavior, on_finish:)
    @thread = Thread.new do
      behavior.call(@section, @indices, @r, @g, @b, @count)
    ensure
      on_finish.call(self)
    end
    self
  end

  def kill
    @thread&.kill
  end

  def complete!
    @status = "done" if @status == "running"
  end

  def cancel!
    @status = "cancelled"
  end

  def running?
    @status == "running"
  end

  def skip_restore!
    @skip_restore = true
  end

  def restore
    return if @skip_restore
    @section == "all" ? Keyboard.restore_full(@baseline) : Keyboard.restore_indices(@baseline)
  rescue => e
    warn "[notification] Restore failed: #{e.message}"
  end

  def to_h
    { section: @section, status: @status, color: @color, style: @style, started_at: @started_at }
  end
end
