require_relative "keyboard"
require_relative "notifications"

PROGRESS_KEYS = %w[1 2 3 4 5 6 7 8 9 0].freeze

# Fixed gradient color per key position (1-indexed, 1=leftmost).
# Positions 1-5: red → yellow (G rises 0→255, R stays 255)
# Positions 6-10: yellow → green (R falls 255→0, G stays 255)
PROGRESS_COLORS = (1..10).map do |pos|
  if pos <= 5
    g = ((pos - 1) * 255.0 / 4).round
    [255, g, 0]
  else
    r = ((10 - pos) * 255.0 / 4).round
    [r, 255, 0]
  end
end.freeze

module Progress
  @mutex    = Mutex.new
  @baseline = nil  # { index => [r,g,b] } snapshot before first set

  def self.set(pct)
    pct = pct.clamp(0, 100)

    @mutex.synchronize do
      # Notifications on top_row take priority — skip LED update but store value.
      return if Notifications.active["top_row"]

      indices = _indices
      return if indices.empty?

      unless @baseline
        Keyboard.fetch_theme
        @baseline = Keyboard.snapshot_indices(indices)
      end
      lit       = (pct * 10.0 / 100).round.clamp(0, 10)
      color_map = indices.each_with_index.each_with_object({}) do |(idx, i), h|
        h[idx] = i < lit ? PROGRESS_COLORS[i] : [0, 0, 0]
      end
      Keyboard.paint_frame(color_map)
    end
  end

  def self.clear
    @mutex.synchronize do
      return unless @baseline

      begin
        Keyboard.restore_indices(@baseline)
      rescue => e
        warn "[progress] Restore failed (#{e.message})"
      end

      @baseline = nil
    end
  end

  private

  def self._indices
    PROGRESS_KEYS.map { |k| Keyboard.layout[k] }.compact
  end
end
