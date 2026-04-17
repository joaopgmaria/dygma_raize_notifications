require_relative "keyboard"
require_relative "sections"

module Behaviors
  BREATHE_STEPS     = 20    # steps per half-cycle
  BREATHE_STEP_TIME = 0.08  # seconds per step → 20 * 2 * 0.08 = 3.2s per breath
  BREATHE_MIN       = 0.08  # stay at 8% brightness at the trough

  CHASE_TRAIL     = 4     # keys fading behind the head
  CHASE_STEP_TIME = 0.05  # seconds per step

  MATRIX_TRAIL = 4     # keys fading behind each raindrop head
  MATRIX_TICK  = 0.08  # seconds per frame

  RAINBOW_STEP_TIME = 0.05  # seconds per frame
  RAINBOW_HUE_SHIFT = 15     # degrees to advance the wave each frame

  def self.for(style)
    case style
    when "flash"     then method(:flash)
    when "breathe"   then method(:breathe)
    when "solid"     then method(:solid)
    when "alternate" then method(:alternate)
    when "scan"      then method(:scan)
    when "matrix"    then method(:matrix)
    when "rainbow"   then method(:rainbow)
    else raise ArgumentError, "Unknown style '#{style}'. Available: flash, breathe, solid, alternate, scan, matrix, rainbow"
    end
  end

  def self.flash(section, indices, r, g, b, count)
    i = 0
    loop do
      break if count && i >= count
      _set(section, indices, r, g, b)
      sleep 0.4
      _set(section, indices, 0, 0, 0)
      sleep 0.2
      i += 1
    end
  end

  def self.breathe(section, indices, r, g, b, seconds)
    deadline = seconds ? Time.now + seconds : nil
    loop do
      break if deadline && Time.now >= deadline
      BREATHE_STEPS.times do |s|
        t = Time.now
        f = BREATHE_MIN + (1.0 - BREATHE_MIN) * (s + 1).to_f / BREATHE_STEPS
        _set(section, indices, (r * f).round, (g * f).round, (b * f).round)
        _sleep_remaining(BREATHE_STEP_TIME, t)
      end
      BREATHE_STEPS.times do |s|
        t = Time.now
        f = 1.0 - (1.0 - BREATHE_MIN) * (s + 1).to_f / BREATHE_STEPS
        _set(section, indices, (r * f).round, (g * f).round, (b * f).round)
        _sleep_remaining(BREATHE_STEP_TIME, t)
      end
    end
  end

  def self.solid(section, indices, r, g, b, duration)
    _set(section, indices, r, g, b)
    duration ? sleep(duration) : sleep
  end

  # Alternates color between left and right halves (keys + underglow) regardless of section/indices.
  def self.alternate(_section, _indices, r, g, b, count)
    left  = Sections.indices_for("left")
    right = Sections.indices_for("right")
    i = 0
    loop do
      break if count && i >= count
      Keyboard.set_leds(left,  r, g, b)
      Keyboard.set_leds(right, 0, 0, 0)
      sleep 0.4
      Keyboard.set_leds(right, r, g, b)
      Keyboard.set_leds(left,  0, 0, 0)
      sleep 0.4
      i += 1
    end
  end

  # KITT-style scanner: a column of keys sweeps back and forth with a fading trail.
  # For "all", each column is the physical vertical strip of keys.
  # For other sections, each key is its own column (key-by-key scan).
  # count = number of complete sweeps (forward + back = 1); nil = infinite.
  def self.scan(section, _indices, r, g, b, count)
    columns = Sections.chase_columns(section)
    if section == "all"
      columns = columns.each_with_index.map { |col, ci| col + (UNDERGLOW_COLUMNS[ci] || []) }
    end
    n       = columns.length
    return if n < 2

    all_indices = columns.flatten
    forward     = (0...n).to_a
    backward    = (1...(n - 1)).to_a.reverse
    sweep       = forward + backward

    sweeps = 0
    loop do
      break if count && sweeps >= count

      sweep.each_with_index do |pos, step|
        t0  = Time.now
        dir = step < n ? 1 : -1  # +1 moving right, -1 moving left

        # Build a color map for every key; default off
        color_map = {}
        all_indices.each { |idx| color_map[idx] = [0, 0, 0] }

        # Trail (fades behind the head)
        (1..CHASE_TRAIL).each do |offset|
          trail_pos = pos - dir * offset
          next unless trail_pos.between?(0, n - 1)
          factor = (CHASE_TRAIL - offset + 1).to_f / (CHASE_TRAIL + 1)
          columns[trail_pos].each { |idx| color_map[idx] = [(r * factor).round, (g * factor).round, (b * factor).round] }
        end

        # Head at full brightness
        columns[pos].each { |idx| color_map[idx] = [r, g, b] }

        # One led.theme call updates all key LEDs in a single serial round-trip
        Keyboard.paint_frame(color_map)

        _sleep_remaining(CHASE_STEP_TIME, t0)
      end

      sweeps += 1
    end
  end

  # Matrix digital rain: independent raindrops fall down each column with a fading trail.
  # count = seconds to run; nil = infinite.
  def self.matrix(section, _indices, r, g, b, count)
    columns     = Sections.chase_columns(section)
    return if columns.empty?

    all_indices = columns.flatten
    deadline    = count ? Time.now + count : nil

    Keyboard.set_leds(Sections.indices_for("underglow"), r, g, b)

    # One drop per column, randomly staggered so they don't all start together.
    drops = columns.map do |col|
      { pos: -(rand(col.length + 3) + 1), speed: rand(2) + 1, tick: 0 }
    end

    loop do
      break if deadline && Time.now >= deadline

      t0        = Time.now
      color_map = {}
      all_indices.each { |idx| color_map[idx] = [0, 0, 0] }

      drops.each_with_index do |drop, ci|
        col = columns[ci]
        cn  = col.length
        pos = drop[:pos]

        # Trail above the head fades out linearly
        (1..MATRIX_TRAIL).each do |offset|
          tp = pos - offset
          next unless tp.between?(0, cn - 1)
          factor = (MATRIX_TRAIL - offset + 1).to_f / (MATRIX_TRAIL + 1)
          color_map[col[tp]] = [(r * factor).round, (g * factor).round, (b * factor).round]
        end

        # Head at full brightness
        color_map[col[pos]] = [r, g, b] if pos.between?(0, cn - 1)

        # Advance on the column's own speed tick
        drop[:tick] += 1
        if drop[:tick] >= drop[:speed]
          drop[:tick] = 0
          drop[:pos] += 1
          # Reset when fully off-screen; re-randomise speed and delay
          if drop[:pos] > cn + MATRIX_TRAIL
            drop[:pos]   = -(rand(cn + 3) + 1)
            drop[:speed] = rand(2) + 1
          end
        end
      end

      # One led.theme call updates all key LEDs in a single serial round-trip
      Keyboard.paint_frame(color_map)

      _sleep_remaining(MATRIX_TICK, t0)
    end
  end

  # Underglow LEDs grouped by key column (matches CHASE_COLUMNS ordering, col 0 = leftmost).
  #
  # Left half (69–98, 30 LEDs): starts halfway up the left edge going up then clockwise.
  #   Left edge upper → col 0:  69–71
  #   Top edge L→R   → cols 1–5: 72–76
  #   Right edge      → col 5:  77–86
  #   Bottom edge R→L → cols 5–1: 87–91
  #   Left edge lower → col 0:  92–98
  #
  # Right half (99–130, 32 LEDs): mirror — starts halfway up the right edge going up then counter-clockwise.
  #   Right edge upper → col 12: 99–101
  #   Top edge R→L    → cols 11–6: 102–107
  #   Left edge        → col 6:  108–117
  #   Bottom edge L→R → cols 6–11: 118–123
  #   Right edge lower → col 12: 124–130
  UNDERGLOW_COLUMNS = [
    [69, 70, 71, 92, 93, 94, 95, 96, 97, 98],              # col 0  — left outer edge
    [72, 91],                                                # col 1
    [73, 90],                                                # col 2
    [74, 89],                                                # col 3
    [75, 88],                                                # col 4
    [76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87],      # col 5  — right edge of left half
    [107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118], # col 6  — left edge of right half
    [106, 119],                                              # col 7
    [105, 120],                                              # col 8
    [104, 121],                                              # col 9
    [103, 122],                                              # col 10
    [102, 123],                                              # col 11
    [99, 100, 101, 124, 125, 126, 127, 128, 129, 130],      # col 12 — right outer edge
  ].freeze

  # Rainbow wave scrolling left to right continuously.
  # Hues are spread evenly across all columns; the whole spectrum shifts
  # RAINBOW_HUE_SHIFT degrees per frame, wrapping seamlessly.
  # color/r/g/b params are unused — rainbow generates its own colors.
  # count = seconds to run; nil = infinite.
  def self.rainbow(section, _indices, _r, _g, _b, count)
    columns = Sections.chase_columns(section)
    return if columns.empty?

    n        = columns.length
    deadline = count ? Time.now + count : nil
    offset   = 0  # current hue shift in degrees (0–359)

    loop do
      break if deadline && Time.now >= deadline

      t0        = Time.now
      color_map = {}

      columns.each_with_index do |col, ci|
        hue = (ci.to_f / n - offset.to_f / 360.0) % 1.0
        r, g, b = _hsv_to_rgb(hue, 1.0, 1.0)
        (col + (UNDERGLOW_COLUMNS[ci] || [])).each { |idx| color_map[idx] = [r, g, b] }
      end

      Keyboard.paint_frame(color_map)
      offset = (offset + RAINBOW_HUE_SHIFT) % 360

      _sleep_remaining(RAINBOW_STEP_TIME, t0)
    end
  end

  private_class_method def self._set(section, indices, r, g, b)
    section == "all" ? Keyboard.set_all(r, g, b) : Keyboard.set_leds(indices, r, g, b)
  end

  # Sleep only for however long remains in the target step, after serial I/O.
  # If serial I/O already consumed the whole step, skip sleep entirely.
  private_class_method def self._sleep_remaining(target, step_start)
    remaining = target - (Time.now - step_start)
    sleep remaining if remaining > 0
  end

  # Convert HSV (h: 0.0–1.0, s: 0.0–1.0, v: 0.0–1.0) to [r, g, b] 0–255.
  private_class_method def self._hsv_to_rgb(h, s, v)
    h6 = h * 6.0
    i  = h6.floor % 6
    f  = h6 - h6.floor
    p  = v * (1.0 - s)
    q  = v * (1.0 - f * s)
    t  = v * (1.0 - (1.0 - f) * s)
    r, g, b = case i
              when 0 then [v, t, p]
              when 1 then [q, v, p]
              when 2 then [p, v, t]
              when 3 then [p, q, v]
              when 4 then [t, p, v]
              when 5 then [v, p, q]
              end
    [(r * 255).round, (g * 255).round, (b * 255).round]
  end
end
