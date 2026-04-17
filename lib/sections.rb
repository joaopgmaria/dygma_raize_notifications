require_relative "keyboard"

TOP_ROW_KEYS   = %w[esc 1 2 3 4 5 6 7 8 9 0 ' + backspace].freeze
SPACE_BAR_KEYS = %w[space1 space2 space3 space4 thumb1 thumb2 thumb3 thumb4].freeze

# Physical columns left→right. Each entry is the set of keys in that vertical strip.
# Keys absent from the layout are silently skipped via filter_map.
CHASE_COLUMNS = [
  # Left half
  %w[esc 1 tab caps l_shift l_ctrl l_dygma],
  %w[2 q a z],
  %w[3 w s x l_alt],
  %w[4 e d c space1],
  %w[5 r f v space2 thumb1],
  %w[6 t g b thumb2],
  # Right half
  %w[7 y h n space3 thumb3],
  %w[8 u j m space4 thumb4],
  ["9", "i", "k", ","],
  ["0", "o", "l", ".", "r_alt"],
  ["'", "p", "ç", "?", "r_dygma"],
  ["+", "{", "~"],
  ["backspace", "}", "\\", "enter", "r_shift", "fn", "r_ctrl"],
].freeze

UNDERGLOW_LEFT_START  = 69
UNDERGLOW_LEFT_END    = 98
UNDERGLOW_RIGHT_START = 99
UNDERGLOW_RIGHT_END   = 130
NEURON_INDEX          = 131

module Sections
  KNOWN = %w[all top_row space_bar underglow underglow_left underglow_right neuron
             left right left_keys right_keys keys].freeze

  def self.indices_for(name)
    case name
    when "all"
      nil
    when "top_row"
      TOP_ROW_KEYS.map { |k| Keyboard.layout[k] }.compact
    when "space_bar"
      SPACE_BAR_KEYS.map { |k| Keyboard.layout[k] }.compact
    when "underglow"
      (UNDERGLOW_LEFT_START..UNDERGLOW_RIGHT_END).to_a
    when "underglow_left"
      (UNDERGLOW_LEFT_START..UNDERGLOW_LEFT_END).to_a
    when "underglow_right"
      (UNDERGLOW_RIGHT_START..UNDERGLOW_RIGHT_END).to_a
    when "neuron"
      [NEURON_INDEX]
    when "left_keys"
      Keyboard.layout.values.select { |i| i <= 32 }.sort.uniq
    when "right_keys"
      Keyboard.layout.values.select { |i| i >= 33 }.sort.uniq
    when "keys"
      indices_for("left_keys") + indices_for("right_keys")
    when "left"
      indices_for("left_keys") + indices_for("underglow_left")
    when "right"
      indices_for("right_keys") + indices_for("underglow_right")
    else
      raise ArgumentError, "Unknown section '#{name}'. Known: #{KNOWN.join(", ")}"
    end
  end

  # Returns an ordered Array<Array<Integer>> of index groups for the scan animation.
  # "all"       → physical vertical key columns (multiple keys per group).
  # "space_bar" → paired columns: [space1,thumb1], [space2,thumb2], [space3,thumb3], [space4,thumb4].
  # Other       → each key is its own single-element group (key-by-key scan).
  SPACE_BAR_COLUMNS = [
    %w[space1 thumb1],
    %w[space2 thumb2],
    %w[space3 thumb3],
    %w[space4 thumb4],
  ].freeze

  def self.chase_columns(section)
    case section
    when "all", "keys"
      CHASE_COLUMNS
        .map { |col| col.filter_map { |k| Keyboard.layout[k] } }
        .reject(&:empty?)
    when "space_bar"
      SPACE_BAR_COLUMNS
        .map { |col| col.filter_map { |k| Keyboard.layout[k] } }
        .reject(&:empty?)
    else
      (indices_for(section) || []).map { |i| [i] }
    end
  end
end
