extends Node
## Saved settings (your name, mute), which online server to use, and invite
## links (a link like ...?room=AB12CD takes a friend straight to your room).

const ONLINE_SERVER_URL := "wss://pong-3l48.onrender.com"
## Where the game is hosted; used for invite links outside the browser.
const GAME_URL := "https://gr33nops.github.io/pong/"
const SETTINGS_FILE := "user://settings.cfg"
const MAX_NAME_LENGTH := 12


func player_name() -> String:
	return str(load_config().get_value("player", "name", ""))


func save_player_name(player_name_text: String) -> void:
	var config := load_config()
	config.set_value("player", "name", player_name_text)
	save_config(config)


## Capital letters, digits and single spaces, at most 12 characters.
func clean_name(raw: String) -> String:
	var allowed := RegEx.new()
	allowed.compile("[^A-Z0-9 ]")
	var spaces := RegEx.new()
	spaces.compile(" +")
	var text := spaces.sub(allowed.sub(raw.to_upper(), "", true), " ", true).strip_edges()
	return text.substr(0, MAX_NAME_LENGTH).strip_edges()


## A link that opens the game and joins this room.
func invite_link(room_code: String) -> String:
	var page := GAME_URL
	if OS.has_feature("web"):
		var here = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
		if here != null and not str(here).is_empty():
			page = str(here)
	return "%s?room=%s" % [page, room_code]


## The room code from an invite link this page was opened with, or "".
func invite_code_from_page() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval("String(new URLSearchParams(window.location.search).get('room') || '')", true)
	var code := str(value).strip_edges().to_upper() if value != null else ""
	var six_characters := RegEx.new()
	six_characters.compile("^[A-Z0-9]{6}$")
	return code if six_characters.search(code) != null else ""


func load_config() -> ConfigFile:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_FILE)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load settings (%s); using defaults." % error)
	return config


func save_config(config: ConfigFile) -> void:
	var error := config.save(SETTINGS_FILE)
	if error != OK:
		push_warning("Could not save settings (%s)." % error)


## The server address, in order of priority:
## 1. the PONG_SERVER_URL environment variable (desktop and tests)
## 2. window.PONG_SERVER_URL or a ?server= link (web test builds)
## 3. the live server
func online_server_url() -> String:
	var from_environment := OS.get_environment("PONG_SERVER_URL").strip_edges()
	if not from_environment.is_empty():
		return from_environment
	var from_page := clean_server_url(_read_server_url_from_page())
	if not from_page.is_empty():
		return from_page
	return ONLINE_SERVER_URL


## Accepts only secure addresses (wss://), or plain ones to this computer.
func clean_server_url(url: String) -> String:
	var clean := url.strip_edges()
	var pattern := RegEx.new()
	pattern.compile("^(wss://[A-Za-z0-9.-]+(:[0-9]{1,5})?|ws://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?)/?$")
	return clean if pattern.search(clean) != null else ""


func _read_server_url_from_page() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval("String(window.PONG_SERVER_URL || new URLSearchParams(window.location.search).get('server') || '')", true)
	return str(value) if value != null else ""
