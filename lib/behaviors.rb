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

  def self.for(style)
    case style
    when "flash"     then method(:flash)
    when "breathe"   then method(:breathe)
    when "solid"     then method(:solid)
    when "alternate" then method(:alternate)
    when "chase"     then method(:chase)
    when "matrix"    then method(:matrix)
    else raise ArgumentError, "Unknown style '#{style}'. Available: flash, breathe, solid, alternate, chase, matrix"
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
    left  = Sections.indices_for("left")  + Sections.indices_for("underglow_left")
    right = Sections.indices_for("right") + Sections.indices_for("underglow_right")
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
  # For other sections, each key is its own column (key-by-key chase).
  # count = number of complete sweeps (forward + back = 1); nil = infinite.
  def self.chase(section, _indices, r, g, b, count)
    columns = Sections.chase_columns(section)
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

  private_class_method def self._set(section, indices, r, g, b)
    section == "all" ? Keyboard.set_all(r, g, b) : Keyboard.set_leds(indices, r, g, b)
  end

  # Sleep only for however long remains in the target step, after serial I/O.
  # If serial I/O already consumed the whole step, skip sleep entirely.
  private_class_method def self._sleep_remaining(target, step_start)
    remaining = target - (Time.now - step_start)
    sleep remaining if remaining > 0
  end
end
