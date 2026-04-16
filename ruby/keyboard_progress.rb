require "net/http"
require "uri"

class KeyboardProgressFormatter
  RSpec::Core::Formatters.register self,
    :start, :example_passed, :example_failed, :example_pending, :dump_summary

  SERVICE_URL = ENV.fetch("KEYBOARD_SERVICE_URL", "http://localhost:9292")

  def initialize(_output)
    @total     = 0
    @completed = 0
    @failed    = false
    @last_pct  = -1
  end

  def start(notification)
    @total = notification.count
    api(:post, "/notify/underglow?color=yellow&style=breathe&force=true")
    api(:put,  "/progress/0")
  end

  def example_passed(_notification)
    increment
  end

  def example_failed(_notification)
    @failed = true
    increment
  end

  def example_pending(_notification)
    increment
  end

  def dump_summary(notification)
    api(:delete, "/progress")
    failed = @failed ||
             notification.failure_count > 0 ||
             notification.errors_outside_of_examples_count > 0
    color = failed ? "red" : "green"
    api(:post, "/notify/underglow?color=#{color}&style=flash&count=5&force=true")
  end

  private

  def increment
    @completed += 1
    return if @total == 0
    # Cap at 99 during the run — progress clears (implicitly 100) on dump_summary.
    pct = [(@completed * 100.0 / @total).round, 99].min
    if pct != @last_pct
      @last_pct = pct
      async { api(:put, "/progress/#{pct}") }
    end
  end

  def api(method, path)
    uri = URI("#{SERVICE_URL}#{path}")
    req = case method
          when :post   then Net::HTTP::Post.new(uri)
          when :put    then Net::HTTP::Put.new(uri)
          when :delete then Net::HTTP::Delete.new(uri)
          end
    Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 2) { |h| h.request(req) }
  rescue StandardError
    # Service not running — silently skip.
  end

  def async(&block)
    Thread.new(&block)
  end
end

RSpec.configuration.add_formatter(KeyboardProgressFormatter)
