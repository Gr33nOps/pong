extends Node

# Colors
const COLOR_P1 = Color(0.12, 0.12, 0.11, 1)   # Black ink
const COLOR_P2 = Color(0.12, 0.12, 0.11, 1)   # Black ink
const COLOR_P1_ALT = Color(0.12, 0.12, 0.11, 1)  # Monochrome fallback
const COLOR_P2_ALT = Color(0.12, 0.12, 0.11, 1)  # Monochrome fallback

# Game settings
const WINNER_SCORE = 5
const MODE_AI = 1
const MODE_2P = 2
const GAME_VERSION := "1.1.13"

# Ball physics — arcade Pong (front-face hits only)
const BALL_RADIUS = 21.0
const START_SPEED = 480.0
const MAX_SPEED = 1020.0
const BALL_COLLISION_STEP = 4.0
const MAX_BALL_SUBSTEPS = 64
const PADDLE_COLLISION_PAD = 2.0
const SPEED_INCREMENT = 1.042
const MAX_BOUNCE_ANGLE_DEG = 72.0
const SERVE_ANGLE_DEG = 28.0
const MIN_HORIZONTAL = 0.38
const ENGLISH = 0.4
const RALLY_SPEED_STEP = 0.006
const SCORE_HOLD = 0.4

# Paddle
const PADDLE_HEIGHT = 156.0
const HALF_HEIGHT = PADDLE_HEIGHT / 2.0
const PADDLE_WIDTH = 21.0
const PADDLE_MARGIN = 16.0
const PADDLE_SPEED = 580.0
const PADDLE_POINTER_SNAP_SPEED = PADDLE_SPEED
const PADDLE_SHRINK_START = 5
const PADDLE_MIN_SCALE = 0.7

# Gamepad — scaled deadzone removes stick drift without making the first part
# of the paddle travel feel sluggish.
const GAMEPAD_DEADZONE := 0.18
const GAMEPAD_RESPONSE_EXPONENT := 1.15
const GAMEPAD_NAV_ENGAGE := 0.62
const GAMEPAD_NAV_RELEASE := 0.42
const GAMEPAD_NAV_INITIAL_REPEAT := 0.32
const GAMEPAD_NAV_REPEAT := 0.12

# Trail
const MAX_TRAIL_POINTS = 18
const TRAIL_WIDTH = 10.0

# AI
const AI_BASE_SPEED = 480.0

# SFX
const SAMPLE_RATE = 22050

# Screen shake
const SHAKE_DURATION = 0.15
const SHAKE_MAGNITUDE = 8.0

# Particles
const PARTICLE_LIFETIME = 0.5
const PARTICLE_COUNT = 12

# Animation
const GAME_OVER_FADE_IN = 0.45
const MENU_FADE_IN = 0.28

# UI
const UI_GOLD = Color(0.12, 0.12, 0.11, 1)
const UI_MUTED = Color(0.22, 0.22, 0.22, 1)
const UI_DIM_TEXT = Color(0.40, 0.40, 0.40, 1)
const COURT_BG = Color(1.0, 1.0, 1.0, 1)
const HUD_HEIGHT = 72.0
const HUD_PAD = 28.0
const TOUCH_UI_SCALE := 1.05

# Settings keys
const SETTINGS_FILE = "user://settings.cfg"
const KEY_MASTER_VOLUME = "master_volume"
const KEY_SFX_VOLUME = "sfx_volume"
const KEY_COLORBLIND_MODE = "colorblind_mode"
const KEY_AI_DIFFICULTY = "ai_difficulty"
const KEY_AI_DIFFICULTY_NAME = "ai_difficulty_name"
const KEY_HIGH_SCORE = "high_score"
const KEY_PLAYER_IS_LEFT = "player_is_left"

const DIFFICULTY_EASY := 0.55
const DIFFICULTY_NORMAL := 0.82
const DIFFICULTY_HARD := 1.0
const KEY_MUTED = "muted"


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


func configure_touch_root(root: Control) -> void:
	var state := get_node_or_null("/root/GameState")
	var touch_ui := OS.has_feature("mobile")
	if state != null and state.has_method("is_touch_ui"):
		touch_ui = state.is_touch_ui()
	if not touch_ui:
		root.scale = Vector2.ONE
		return
	root.pivot_offset = Vector2(576.0, 324.0)
	# Compact landscape phones already use the full reference height; scaling the
	# whole overlay there would crop the top/bottom safe area. Larger touch
	# displays get a modest visual bump while hit testing remains logical.
	var window_size := get_window().size
	var scale := TOUCH_UI_SCALE if window_size.y >= 600 else 1.0
	root.scale = Vector2.ONE * scale
