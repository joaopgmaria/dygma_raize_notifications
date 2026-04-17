require "json"

LAYOUT_FILE = File.expand_path("~/.keyboard/layout.json")
SCHEME_FILE  = File.expand_path("~/.keyboard/scheme")

module Keyboard
  @mutex           = Mutex.new
  @reconnect_mutex = Mutex.new
  @port            = nil
  @theme           = []
  @idle_theme      = []   # snapshot of the clean/saved state; never overwritten by animations
  @total           = 0
  @layout          = {}
  @reconnecting    = false

  def self.connect
    port_path = Dir.glob("/dev/cu.usbmodem*").first
    raise "No Dygma Raise keyboard found at /dev/cu.usbmodem*" unless port_path
    _open_port(port_path)
    fetch_theme
    @idle_theme = @theme.map(&:dup)  # clean baseline at startup
  end

  # Returns the idle (pre-animation) theme. Used by /clear to restore cleanly.
  def self.idle_theme
    @idle_theme.map(&:dup)
  end

  # Update the idle theme. Pass a snapshot array, or nil to capture @theme.
  # Called by explicit save/restore commands — never by animations.
  def self.save_idle(theme = nil)
    @idle_theme = (theme || @theme).map(&:dup)
  end

  def self.load_layout
    @layout = JSON.parse(File.read(LAYOUT_FILE))
  end

  # Sends a serial command and returns the response lines.
  # If the keyboard is disconnected, raises immediately and starts a background
  # reconnect thread — the mutex is NOT held during the reconnect wait, so
  # HTTP requests remain responsive while the keyboard is unplugged.
  def self.send_cmd(cmd)
    @mutex.synchronize do
      raise IOError, "Keyboard not connected" unless @port
      _raw_send(cmd)
    end
  rescue Errno::ENXIO, Errno::EIO, IOError => e
    warn "[keyboard] Disconnected (#{e.class}) — starting background reconnect..."
    _handle_disconnect
    raise
  end

  def self.fetch_theme
    @mutex.synchronize do
      raise IOError, "Keyboard not connected" unless @port
      raw    = _raw_send("led.theme").join(" ").split.map(&:to_i)
      @theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
      @total = @theme.size
    end
  rescue Errno::ENXIO, Errno::EIO, IOError => e
    warn "[keyboard] Disconnected (#{e.class}) — starting background reconnect..."
    _handle_disconnect
    raise
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
    @mutex.synchronize do
      raise IOError, "Keyboard not connected" unless @port
      _raw_send("led.setAll #{r} #{g} #{b}")
      @theme.map! { [r, g, b] }
    end
  rescue Errno::ENXIO, Errno::EIO, IOError => e
    warn "[keyboard] Disconnected (#{e.class}) — starting background reconnect..."
    _handle_disconnect
    raise
  end

  def self.restore_full(snapshot)
    @mutex.synchronize do
      raise IOError, "Keyboard not connected" unless @port
      _raw_send("led.theme #{snapshot.flatten.join(" ")}")
      @theme = snapshot.map(&:dup)
    end
  rescue Errno::ENXIO, Errno::EIO, IOError => e
    warn "[keyboard] Disconnected (#{e.class}) — starting background reconnect..."
    _handle_disconnect
    raise
  end

  # Apply per-index color overrides and send a full led.theme in one serial call.
  # Indices not in color_map keep their current @theme value (background preserved).
  # The entire read-modify-send-write cycle is atomic under @mutex.
  def self.paint_frame(color_map)
    @mutex.synchronize do
      raise IOError, "Keyboard not connected" unless @port
      new_theme = @theme.map(&:dup)
      color_map.each { |i, rgb| new_theme[i] = rgb }
      _raw_send("led.theme #{new_theme.flatten.join(" ")}")
      @theme = new_theme
    end
  rescue Errno::ENXIO, Errno::EIO, IOError => e
    warn "[keyboard] Disconnected (#{e.class}) — starting background reconnect..."
    _handle_disconnect
    raise
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
    # O_NOCTTY: prevent the serial tty from becoming our controlling terminal.
    # Without this, setsid() leaves us with no controlling terminal, so the
    # first tty we open becomes one — and macOS sends SIGHUP to the process
    # when the USB device is removed, which kills Puma.
    @port = File.open(path, File::RDWR | File::NOCTTY)
    @port.binmode
    @port.sync = true
  end

  # Close the port and start a background reconnect thread.
  # @reconnect_mutex ensures only one reconnect runs at a time.
  def self._handle_disconnect
    @mutex.synchronize do
      @port&.close rescue nil
      @port = nil
    end

    @reconnect_mutex.synchronize do
      return if @reconnecting
      @reconnecting = true
    end

    Thread.new do
      begin
        _do_reconnect
      ensure
        @reconnect_mutex.synchronize { @reconnecting = false }
      end
    end
  end

  # Polls every second for up to 30 s. Runs outside @mutex so the service
  # remains responsive to HTTP requests (which fail fast via the nil @port check).
  def self._do_reconnect
    port_path = nil
    30.times do
      port_path = Dir.glob("/dev/cu.usbmodem*").first
      break if port_path
      warn "[keyboard] Keyboard not found — waiting to reconnect..."
      sleep 1
    end

    unless port_path
      warn "[keyboard] Keyboard not found after 30 s — reconnect failed"
      return
    end

    @mutex.synchronize do
      _open_port(port_path)
      sleep 0.3  # let the keyboard enumerate before the first command
      raw    = _raw_send("led.theme").join(" ").split.map(&:to_i)
      @theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
      @total = @theme.size
      warn "[keyboard] Reconnected to #{port_path}"
    end
  end

  def self._raw_send(cmd)
    @port.write("#{cmd}\n")
    lines = []
    loop do
      # 3-second timeout per line: if the keyboard is disconnected mid-response
      # the read won't block forever, keeping @mutex free for other callers.
      raise IOError, "Serial read timeout" unless IO.select([@port], nil, nil, 3)
      line = @port.readline.strip
      break if line == "."
      lines << line unless line.empty?
    end
    lines
  end
end
