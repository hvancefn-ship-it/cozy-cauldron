extends Node

## AudioManager — autoload singleton
## Manages SFX playback via a pool of AudioStreamPlayer nodes.
## Also persists sfx_volume and haptics_enabled to user://settings.json.

const SETTINGS_PATH := "user://settings.json"
const POOL_SIZE := 8

var sfx_volume: float = 1.0
var haptics_enabled: bool = true

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0


func _ready() -> void:
	_build_pool()
	_load_settings()
	_apply_volume()


# ---------------------------------------------------------------------------
# Pool
# ---------------------------------------------------------------------------

func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)


# ---------------------------------------------------------------------------
# SFX playback
# ---------------------------------------------------------------------------

func play_sfx(name: String) -> void:
	var path := "res://audio/sfx/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	var stream := ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE)
	if stream == null:
		return
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	player.stream = stream
	player.play()


# ---------------------------------------------------------------------------
# Volume
# ---------------------------------------------------------------------------

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save_settings()


func _apply_volume() -> void:
	var db := linear_to_db(sfx_volume)
	for player in _pool:
		player.volume_db = db


# ---------------------------------------------------------------------------
# Haptics
# ---------------------------------------------------------------------------

func set_haptics(enabled: bool) -> void:
	haptics_enabled = enabled
	_save_settings()


func is_haptics_enabled() -> bool:
	return haptics_enabled


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return
	var data: Dictionary = parsed as Dictionary
	if data.has("sfx_volume"):
		sfx_volume = clampf(float(data["sfx_volume"]), 0.0, 1.0)
	if data.has("haptics_enabled"):
		haptics_enabled = bool(data["haptics_enabled"])


func _save_settings() -> void:
	var data := {
		"sfx_volume": sfx_volume,
		"haptics_enabled": haptics_enabled,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()
