require "sinatra/base"
require "fileutils"
require_relative "lib/keyboard"
require_relative "lib/sections"
require_relative "lib/notifications"
require_relative "lib/progress"
require_relative "lib/text"

Keyboard.connect
Keyboard.load_layout

SERVICE_PORT = 9292

class KeyboardService < Sinatra::Base
  set :bind, "127.0.0.1"
  set :port, SERVICE_PORT

  before { content_type "application/json" }

  # POST /notify/:section?color=green&style=flash&count=5
  post "/notify/:section" do
    color = params[:color] || "red"
    style = params[:style] || "flash"
    count = params[:count]&.to_i
    force         = params[:force] == "true"
    keep_if_same  = params[:keep_if_same] == "true"

    id = Notifications.start(params[:section], color, style: style, count: count, force: force, keep_if_same: keep_if_same)
    { id: id }.to_json
  rescue Notifications::ConflictError => e
    halt 409, { error: e.message }.to_json
  rescue ArgumentError => e
    halt 400, { error: e.message }.to_json
  end

  # DELETE /notify/:id
  delete "/notify/:id" do
    Notifications.cancel(params[:id]).to_json
  rescue Notifications::NotFoundError => e
    halt 404, { error: e.message }.to_json
  end

  # DELETE /notify/section/:section  — cancel whatever is active on a section
  delete "/notify/section/:section" do
    Notifications.cancel_section(params[:section]).to_json
  rescue Notifications::NotFoundError => e
    halt 404, { error: e.message }.to_json
  end

  # GET /notify/:id
  get "/notify/:id" do
    entry = Notifications.get(params[:id])
    halt 404, { error: "Notification '#{params[:id]}' not found" }.to_json unless entry
    entry.merge(id: params[:id]).to_json
  end

  # POST /restore
  post "/restore" do
    Keyboard.restore_full(Keyboard.theme)
    { status: "ok" }.to_json
  end

  # POST /scheme/save
  post "/scheme/save" do
    Keyboard.fetch_theme
    flat = Keyboard.theme.flatten.join(" ")
    FileUtils.mkdir_p(File.dirname(SCHEME_FILE))
    File.write(SCHEME_FILE, flat)
    { status: "ok", leds: Keyboard.total_leds }.to_json
  end

  # POST /scheme/restore
  post "/scheme/restore" do
    halt 404, { error: "No saved scheme at #{SCHEME_FILE}" }.to_json unless File.exist?(SCHEME_FILE)
    raw   = File.read(SCHEME_FILE).split.map(&:to_i)
    theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
    Keyboard.restore_full(theme)
    { status: "ok", leds: theme.size }.to_json
  end

  # PUT /progress/:value (0-100)
  put "/progress/:value" do
    pct = params[:value].to_i
    halt 400, { error: "Value must be 0-100" }.to_json unless (0..100).include?(pct)
    Progress.set(pct)
    { value: pct }.to_json
  end

  # DELETE /progress
  delete "/progress" do
    Progress.clear
    { status: "cleared" }.to_json
  end

  # PUT /text?string=CLI&color=red — light up the keys for each character
  put "/text" do
    string = params[:string] or halt 400, { error: "string param required" }.to_json
    color  = params[:color] || "white"
    Text.set(string, color)
    { string: string, color: color }.to_json
  rescue ArgumentError => e
    halt 400, { error: e.message }.to_json
  end

  # DELETE /text
  delete "/text" do
    Text.clear
    { status: "cleared" }.to_json
  end

  # POST /clear — cancel all notifications and restore saved scheme
  post "/clear" do
    Notifications.cancel_all
    Progress.clear
    Text.clear
    if File.exist?(SCHEME_FILE)
      raw   = File.read(SCHEME_FILE).split.map(&:to_i)
      theme = raw.each_slice(3).map { |r, g, b| [r, g, b] }
      Keyboard.restore_full(theme)
    else
      Keyboard.fetch_theme
    end
    { status: "ok" }.to_json
  end

  # GET /status
  get "/status" do
    {
      keyboard_connected: true,
      total_leds:         Keyboard.total_leds,
      layout_keys:        Keyboard.layout.keys.size,
      active_sections:    Notifications.active,
    }.to_json
  end
end

KeyboardService.run! if __FILE__ == $0
