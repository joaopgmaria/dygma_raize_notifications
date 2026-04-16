#!/usr/bin/env ruby
# map_layout.rb — map ALL keys to LED indices, a few at a time
#
# Lights keys in groups of 4, each a distinct full-brightness color.
# You name what you see for each color → exact LED index.
#
# NOTE: requires direct serial access — stop the service first:
#   bundle exec rackup config.ru  →  Ctrl+C to stop

require "net/http"
begin
  uri = URI("http://localhost:9292/status")
  Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) { |h| h.get(uri.path) }
  abort "Service is running — stop it before running map_layout.rb (it needs direct serial access)"
rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout
  # good — service is not running (or not responding)
end
# Re-running keeps existing values — press Enter to skip a key.
# Output: ~/.keyboard/layout.json

require "json"

LAYOUT_FILE = File.expand_path("~/.keyboard/layout.json")
SCHEME_FILE  = File.expand_path("~/.keyboard/scheme")

GROUP_SIZE = 4

GROUP_COLORS = [
  { name: "Red",    rgb: [255,   0,   0] },
  { name: "Green",  rgb: [  0, 255,   0] },
  { name: "Blue",   rgb: [  0,   0, 255] },
  { name: "Yellow", rgb: [255, 255,   0] },
].freeze

LAYOUT_REFERENCE = <<~REF
  Suggested key names:
  ┌──────────────────────────────────────────┐  ┌───────────────────────────────────────────────┐
  │ Left half                                │  │ Right half                                    │
  │ Esc   1     2     3     4     5     6    │  │ 7     8     9     0     -     +     Bksp      │
  │ Tab   Q     W     E     R     T          │  │ Y     U     I     O     P     {     }     \   │
  │ Caps  A     S     D     F     G          │  │ H     J     K     L     ;     '     Enter     │
  │ Shift Z     X     C     V     B          │  │ N     M     ,     .     /     Shift           │
  │ Ctrl  Dygma1 Alt  Space1 Space2          │  │ Space3 Space4 Alt  Dygma2 Fn   Ctrl           │
  │ Thumb1 Thumb2                            │  │ Thumb3 Thumb4                                 │
  └──────────────────────────────────────────┘  └───────────────────────────────────────────────┘
REF

# ── Serial ────────────────────────────────────────────────────────────────────

port_path = Dir.glob("/dev/cu.usbmodem*").first
abort "Keyboard not found (no /dev/cu.usbmodem* device)" unless port_path

system("stty -f #{port_path} 9600 raw -echo cs8 cread clocal 2>/dev/null")
port = File.open(port_path, "r+b")
port.sync = true

def send_cmd(port, cmd)
  port.write("#{cmd}\n")
  lines = []
  while (line = port.readline.strip) != "."
    lines << line unless line.empty?
  end
  lines
end

def prompt_count(label, default)
  print "#{label} [#{default}]: "
  input = $stdin.gets.strip
  input.empty? ? default : input.to_i
end

# ── Discover LED count and confirm half sizes ─────────────────────────────────

raw        = send_cmd(port, "led.theme").join(" ")
total_leds = raw.split.count / 3
puts "Detected #{total_leds} total LEDs (keys + underglow)\n\n"

left_count  = prompt_count("Left half key count",  32)
right_count = prompt_count("Right half key count", 36)
left_start  = 0
right_start = left_count
puts

# ── Load existing layout ──────────────────────────────────────────────────────

existing = File.exist?(LAYOUT_FILE) ? JSON.parse(File.read(LAYOUT_FILE)) : {}
# invert for led_index → key_name lookup
existing_by_index = existing.invert.transform_keys(&:to_i)

# ── Half mapper ───────────────────────────────────────────────────────────────

def map_half(port, half_name, start_idx, count, total_leds, existing, existing_by_index, already_mapped = {})
  puts "═" * 58
  puts " #{half_name} HALF  (LED indices #{start_idx}–#{start_idx + count - 1})"
  puts "═" * 58
  puts "Enter key name, '--' to skip (fetches a replacement), or Enter to keep existing.\n\n"

  found    = {}
  named    = 0
  next_idx = start_idx + count  # next index to fetch when a skip happens
  queue    = (start_idx...(start_idx + count)).to_a
  group_n  = 0

  until named >= count || queue.empty?
    group = queue.shift(GROUP_SIZE)
    group_n += 1

    send_cmd(port, "led.setAll 0 0 0")
    group.each_with_index do |led_idx, pos|
      r, g, b = GROUP_COLORS[pos][:rgb]
      send_cmd(port, "led.at #{led_idx} #{r} #{g} #{b}")
    end

    puts "Group #{group_n}  (LEDs #{group.first}–#{group.last})"
    group.each_with_index do |led_idx, pos|
      break if named >= count

      # Already claimed by the other half — auto-skip with replacement
      if already_mapped.key?(led_idx)
        puts "  #{GROUP_COLORS[pos][:name].ljust(7)} #{led_idx.to_s.rjust(3)}  → '#{already_mapped[led_idx]}' (other half), skipping"
        queue.push(next_idx) && next_idx += 1 if next_idx < total_leds
        next
      end

      existing_name = existing_by_index[led_idx]
      hint = existing_name ? " [#{existing_name}]" : ""

      loop do
        print "  #{GROUP_COLORS[pos][:name].ljust(7)} #{led_idx.to_s.rjust(3)}#{hint} > "
        input = $stdin.gets.strip

        if input == "--"
          # Skip — doesn't count toward quota; fetch a replacement index
          if next_idx < total_leds
            queue.push(next_idx)
            next_idx += 1
          end
          break
        elsif input.empty?
          if existing_name
            found[existing_name] = led_idx
            named += 1
          else
            # No existing value and no input — treat as skip with replacement
            if next_idx < total_leds
              queue.push(next_idx)
              next_idx += 1
            end
          end
          break
        elsif found.key?(input)
          puts "    '#{input}' already assigned to LED #{found[input]} — use a different name or '--'."
        else
          found[input] = led_idx
          named += 1
          break
        end
      end
    end
    puts
  end

  found
end

# ── Run both halves ───────────────────────────────────────────────────────────

puts LAYOUT_REFERENCE
puts "Mapping all keys — left half first, then right.\n\n"

left_map  = map_half(port, "LEFT",  left_start,  left_count,  total_leds, existing, existing_by_index)
right_map = map_half(port, "RIGHT", right_start, right_count, total_leds, existing, existing_by_index,
                     left_map.invert)  # pass led_index => key_name so right half can skip them

# ── Restore & save ────────────────────────────────────────────────────────────

if File.exist?(SCHEME_FILE)
  scheme = File.read(SCHEME_FILE).strip
  send_cmd(port, "led.theme #{scheme}") unless scheme.empty?
else
  send_cmd(port, "led.setAll 0 0 0")
end
port.close

merged = existing.merge(left_map).merge(right_map)
File.write(LAYOUT_FILE, JSON.pretty_generate(merged.sort.to_h))

puts "═" * 58
puts " Saved #{merged.length} keys to #{LAYOUT_FILE}"
puts "═" * 58
puts
merged.sort_by { |_, v| v }.each_slice(7) do |slice|
  puts slice.map { |k, v| "#{k}=#{v}".ljust(12) }.join
end
