require "json"

LAYOUT_FILE = File.expand_path("~/.keyboard/layout.json")
SCHEME_FILE  = File.expand_path("~/.keyboard/scheme")

module Keyboard
  @mutex  = Mutex.new
  @port   = nil
  @theme  = []
  @total  = 0
  @layout = {}

  def self.connect
    port_path = Dir.glob("/dev/cu.usbmodem*").first
    raise "No Dygma Raise keyboard found at /dev/cu.usbmodem*" unless port_path

    _open_port(port_path)
    fetch_theme
  end

  def self.load_layout
    @layout = JSON.parse(File.read(LAYOUT_FILE))
  end

  def self.send_cmd(cmd)
    @mutex.synchronize do
      attempt = 0
      begin
        _raw_send(cmd)
      rescue Errno::ENXIO, Errno::EIO, IOError => e
        raise e if (attempt += 1) > 1
        warn "[keyboard] Disconnected (#{e.class}) — reconnecting..."
        _reconnect!
        retry
      end
    end
  end

  def self.fetch_theme
    raw    = send_cmd("led.theme").join(" ").split.map(&:to_i)
    @theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
    @total = @theme.size
  end

  def self.theme
    @theme.map(&:dup)
  end

  def self.total_leds
    @total
  end

  def self.layout
    @layout
  end

  def self.set_leds(indices, r, g, b)
    color_map = indices.each_with_object({}) { |i, h| h[i] = [r, g, b] }
    paint_frame(color_map)
  end

  def self.set_all(r, g, b)
    send_cmd("led.setAll #{r} #{g} #{b}")
    @theme.map! { [r, g, b] }
  end

  def self.restore_full(snapshot)
    flat = snapshot.flatten.join(" ")
    send_cmd("led.theme #{flat}")
    @theme = snapshot.map(&:dup)   # keep in-memory state in sync
  end

  # Apply per-index color overrides and send a full led.theme in one serial call.
  # Indices not in color_map keep their current @theme value (background preserved).
  def self.paint_frame(color_map)
    new_theme = @theme.map(&:dup)
    color_map.each { |i, rgb| new_theme[i] = rgb }
    flat = new_theme.flatten.join(" ")
    send_cmd("led.theme #{flat}")
    @theme = new_theme
  end

  def self.restore_indices(snapshot)
    color_map = snapshot.transform_values(&:dup)
    paint_frame(color_map)
  end

  def self.snapshot_indices(indices)
    indices.each_with_object({}) { |i, h| h[i] = @theme[i].dup }
  end

  private

  def self._open_port(path)
    @port&.close rescue nil
    system("stty -f #{path} 9600 raw -echo cs8 cread clocal 2>/dev/null")
    @port = File.open(path, "r+b")
    @port.sync = true
  end

  # Runs inside @mutex — must not call send_cmd (would deadlock).
  def self._reconnect!
    @port&.close rescue nil
    @port = nil
    sleep 0.5
    port_path = Dir.glob("/dev/cu.usbmodem*").first
    raise "Keyboard not found after disconnect — ensure it is reconnected" unless port_path
    _open_port(port_path)
    # Re-fetch theme inline (can't call send_cmd — already holding @mutex).
    raw    = _raw_send("led.theme").join(" ").split.map(&:to_i)
    @theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
    @total = @theme.size
    warn "[keyboard] Reconnected to #{port_path}"
  end

  def self._raw_send(cmd)
    @port.write("#{cmd}\n")
    lines = []
    while (line = @port.readline.strip) != "."
      lines << line unless line.empty?
    end
    lines
  end
end
