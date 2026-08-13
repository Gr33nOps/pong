extends Node

# Colors
const COLOR_P1 = Color(0, 1, 1, 1)   # Cyan/Blue
const COLOR_P2 = Color(1, 0, 0, 1)   # Red
const COLOR_P1_ALT = Color(1, 1, 0, 1)  # Yellow (colorblind)
const COLOR_P2_ALT = Color(0, 1, 0, 1)  # Green (colorblind)

# Game settings
const WINNER_SCORE = 5
const MODE_AI = 1
const MODE_2P = 2

# Ball physics — arcade Pong (front-face hits only)
const BALL_RADIUS = 21.0
const START_SPEED = 480.0
const MAX_SPEED = 1200.0
const SPEED_INCREMENT = 1.08
const MAX_BOUNCE_ANGLE_DEG = 72.0
const SERVE_ANGLE_DEG = 28.0
const MIN_HORIZONTAL = 0.38
const ENGLISH = 0.55
const RALLY_SPEED_STEP = 0.012

# Paddle
const PADDLE_HEIGHT = 214.0
const HALF_HEIGHT = PADDLE_HEIGHT / 2.0
const PADDLE_WIDTH = 21.0
const PADDLE_MARGIN = 16.0
const PADDLE_SPEED = 580.0
const PADDLE_SHRINK_START = 6
const PADDLE_MIN_SCALE = 0.55

# Trail
const MAX_TRAIL_POINTS = 16
const TRAIL_WIDTH = 16.0

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
const GAME_OVER_FADE_IN = 0.4
const MENU_FADE_IN = 0.3

# Settings keys
const SETTINGS_FILE = "user://settings.cfg"
const KEY_MASTER_VOLUME = "master_volume"
const KEY_SFX_VOLUME = "sfx_volume"
const KEY_COLORBLIND_MODE = "colorblind_mode"
const KEY_AI_DIFFICULTY = "ai_difficulty"
const KEY_HIGH_SCORE = "high_score"

const DIFFICULTY_EASY := 0.5
const DIFFICULTY_NORMAL := 1.0
const DIFFICULTY_HARD := 1.5


func read_config() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	return config


func write_config(config: ConfigFile) -> void:
	config.save(SETTINGS_FILE)