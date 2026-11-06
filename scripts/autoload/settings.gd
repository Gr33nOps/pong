extends Node
## Saved settings (just "muted" for now) and which online server to use.

const ONLINE_SERVER_URL := "wss://pong-3l48.onrender.com"
const SETTINGS_FILE := "user://settings.cfg"


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
