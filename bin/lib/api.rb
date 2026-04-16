require "net/http"
require "uri"
require "json"

SERVICE_URL = "http://localhost:9292"

def api(method, path, params = {})
  uri = URI("#{SERVICE_URL}#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?
  req = case method
        when :get    then Net::HTTP::Get.new(uri)
        when :post   then Net::HTTP::Post.new(uri)
        when :delete then Net::HTTP::Delete.new(uri)
        end
  Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
rescue Errno::ECONNREFUSED
  abort "Keyboard service not running — start it with: dygma start"
end

def api_json(method, path, params = {})
  res = api(method, path, params)
  body = JSON.parse(res.body)
  if res.code.to_i >= 400
    abort "Error #{res.code}: #{body["error"]}"
  end
  body
end
