extends Node

const ONLINE_SERVER_URL := "wss://pong-3l48.onrender.com"

# Gamepad: scaled deadzone removes stick drift without making the first part
# of the paddle travel feel sluggish.
const GAMEPAD_DEADZONE := 0.18
const GAMEPAD_RESPONSE_EXPONENT := 1.15
const GAMEPAD_NAV_ENGAGE := 0.62
const GAMEPAD_NAV_RELEASE := 0.42

# Settings keys
const SETTINGS_FILE = "user://settings.cfg"
const KEY_MASTER_VOLUME = "master_volume"
const KEY_SFX_VOLUME = "sfx_volume"
const KEY_MUTED = "muted"
const KEY_ONLINE_SERVER_URL = "online_server_url"


func read_config() -> ConfigFile:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Could not load settings (%s); using defaults." % err)
	return config


func write_config(config: ConfigFile) -> void:
	var err := config.save(SETTINGS_FILE)
	if err != OK:
		push_warning("Could not save settings (%s)." % err)


func get_online_server_url() -> String:
	var environment_url := OS.get_environment("PONG_SERVER_URL").strip_edges()
	if not environment_url.is_empty():
		return environment_url
	var web_url := clean_server_override(_read_web_server_override())
	if not web_url.is_empty():
		return web_url
	var config := read_config()
	return str(config.get_value("online", KEY_ONLINE_SERVER_URL, ONLINE_SERVER_URL)).strip_edges()


## Test builds can target another server via window.PONG_SERVER_URL in the page
## or a ?server= link parameter.
func _read_web_server_override() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval("String(window.PONG_SERVER_URL || new URLSearchParams(window.location.search).get('server') || '')", true)
	return str(value) if value != null else ""


## Only secure sockets, or plain sockets to this machine, are accepted.
func clean_server_override(url: String) -> String:
	var clean := url.strip_edges()
	var pattern := RegEx.new()
	pattern.compile("^(wss://[A-Za-z0-9.-]+(:[0-9]{1,5})?|ws://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?)/?$")
	return clean if pattern.search(clean) != null else ""
