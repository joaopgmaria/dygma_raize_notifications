require_relative "keyboard"
require_relative "colors"

module Text
  @mutex    = Mutex.new
  @baseline = nil

  def self.set(string, color)
    r, g, b = COLORS.fetch(color) { raise ArgumentError, "Unknown color '#{color}'. Available: #{COLORS.keys.join(", ")}" }

    @mutex.synchronize do
      indices = _indices_for(string)
      return if indices.empty?

      unless @baseline
        Keyboard.fetch_theme
        @baseline = Keyboard.snapshot_indices(indices)
      end
      Keyboard.set_leds(indices, r, g, b)
    end
  end

  def self.clear
    @mutex.synchronize do
      return unless @baseline

      begin
        Keyboard.restore_indices(@baseline)
      rescue => e
        warn "[text] Restore failed (#{e.message})"
      end

      @baseline = nil
    end
  end

  private

  def self._indices_for(string)
    string.downcase.chars.uniq.filter_map { |c| Keyboard.layout[c] }
  end
end
