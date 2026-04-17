extends Control
class_name Cauldron
## Active brew scene. All tunable values pulled from UpgradeManager at brew-start.

@export var base_symbols_required: int = 3
@export var base_max_misses: int = 3
@export var flash_duration: float = 0.35
@export var flash_color_success: Color = Color(0.1, 1.0, 0.2, 0.85)
@export var flash_color_fail: Color    = Color(1.0, 0.1, 0.1, 0.85)

signal potion_completed()
signal potion_exploded()
signal symbol_matched(index: int, total: int)
signal symbol_missed(miss_count: int)

@onready var _bg: TextureRect  = $CauldronRect

const CAULDRON_TEX_PATH  := "res://assets/cauldron_strip3.png"
const CAULDRON_FRAMES    := 3
const CAULDRON_FRAME_W   := 48
@onready var _flash: ColorRect = $FlashRect
@onready var _label: Label     = $Label

var _scroll: Scroll = null
var _hud: BrewHUD   = null
var _symbol_index: int = 0
var _miss_count: int   = 0
var _brewing: bool     = false
var _current_symbols: Array[String] = []

# Resolved at brew-start from upgrades
var _symbols_required: int = 3
var _max_misses: int = 3
var _autocomplete: bool = false


func _ready() -> void:
	_flash.color = Color(0, 0, 0, 0)
	_label.text = "Tap to brew!"
	if ResourceLoader.exists(CAULDRON_TEX_PATH):
		_setup_cauldron_sprite()
	else:
		_bg.self_modulate = Color(0.15, 0.1, 0.2, 1.0)


func _setup_cauldron_sprite() -> void:
	var tex: Texture2D = load(CAULDRON_TEX_PATH)
	if tex == null:
		return
	# Replace TextureRect with AnimatedSprite2D for proper frame animation
	var sprite := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	sf.clear_all()
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 4.0)
	for i in CAULDRON_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * CAULDRON_FRAME_W, 0, CAULDRON_FRAME_W, CAULDRON_FRAME_W)
		sf.add_frame("idle", atlas)
	sprite.sprite_frames = sf
	# Position centered inside the TextureRect bounds
	var rect := _bg.get_rect()
	sprite.position = Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	sprite.scale = Vector2(rect.size.x / float(CAULDRON_FRAME_W), rect.size.y / float(CAULDRON_FRAME_W))
	sprite.play("idle")
	_bg.add_child(sprite)
	_bg.texture = null  # hide the TextureRect's own image


func set_scroll(scroll: Scroll) -> void:
	_scroll = scroll
	_scroll.symbol_matched.connect(_on_symbol_matched)
	_scroll.symbol_failed.connect(_on_symbol_failed)


func set_hud(hud: BrewHUD) -> void:
	_hud = hud


func _input(event: InputEvent) -> void:
	if _brewing or not is_visible_in_tree():
		return
	var tapped := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tapped = _bg.get_global_rect().has_point(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tapped = _bg.get_global_rect().has_point(st.position)
	if tapped:
		_start_brew()


func _start_brew() -> void:
	if _scroll == null:
		push_error("Cauldron: scroll not set!")
		return

	# Ingredient gate: each attempt costs slime, success or fail.
	var host: Node = get_parent()
	if host and host.has_method("consume_slime_for_brew_attempt"):
		var ok: bool = bool(host.consume_slime_for_brew_attempt())
		if not ok:
			_label.text = "Need 5 slime to brew"
			return
	AudioManager.play_sfx("sfx_cauldron_tap")

	# --- Read upgrades ---
	# symbols_required: base minus reductions, min 1
	var sym_reduction: int = (
		int(UpgradeManager.get_value("brew_symbols_1")) +
		int(UpgradeManager.get_value("brew_symbols_2")) +
		int(UpgradeManager.get_value("brew_symbols_3")) +
		int(UpgradeManager.get_value("prestige_symbol"))
	)
	_symbols_required = max(1, base_symbols_required + sym_reduction)  # floor = 1, always

	# max misses: base plus bonus
	_max_misses = base_max_misses + int(UpgradeManager.get_value("brew_misses"))

	# autocomplete last symbol if upgrade purchased
	_autocomplete = UpgradeManager.get_level("brew_autocomplete") > 0

	# symbol leniency: adjust threshold temporarily
	var lenient_bonus: float = UpgradeManager.get_value("brew_lenient")  # positive, lowers match threshold
	if lenient_bonus != 0.0:
		for sym in SymbolLibrary.get_symbol_names():
			var current: float = SymbolLibrary.get_threshold(sym)
			SymbolLibrary.symbol_thresholds["_brew_orig_" + sym] = current
			SymbolLibrary.symbol_thresholds[sym] = max(0.1, current - lenient_bonus)  # lower threshold = more forgiving

	_brewing = true
	_symbol_index = 0
	_miss_count = 0
	_label.text = ""

	var names: Array[String] = SymbolLibrary.get_symbol_names()
	if names.is_empty():
		push_error("Cauldron: no symbols in library!")
		return

	_current_symbols.clear()
	for _i in range(_symbols_required):
		_current_symbols.append(names[randi() % names.size()])

	if _hud:
		_hud.show_hud(_symbols_required, _max_misses)
		_hud.reset_dots()

	_show_next_symbol()


func _show_next_symbol() -> void:
	# Autocomplete: if last symbol and upgrade purchased, skip drawing
	if _autocomplete and _symbol_index == _symbols_required - 1:
		await get_tree().create_timer(0.3).timeout
		_on_symbol_matched(_current_symbols[_symbol_index], 1.0)
		return
	_scroll.show_symbol(_current_symbols[_symbol_index])


func _on_symbol_matched(_sym_name: String, _score: float) -> void:
	_flash_cauldron(true)
	if _hud:
		_hud.mark_symbol_success(_symbol_index)
	symbol_matched.emit(_symbol_index, _symbols_required)
	_symbol_index += 1
	_miss_count = 0

	if _symbol_index >= _symbols_required:
		await get_tree().create_timer(flash_duration + 0.1).timeout
		_finish_brew(true)
	else:
		await get_tree().create_timer(0.4).timeout
		_scroll.dismiss()
		await get_tree().create_timer(0.2).timeout
		_show_next_symbol()


func _on_symbol_failed(_score: float) -> void:
	_flash_cauldron(false)

	# Calm Focus: chance to ignore a failed stroke (doesn't consume a miss)
	var calm_focus_chance: float = clampf(UpgradeManager.get_value("brew_time"), 0.0, 0.95)
	var consumed_miss: bool = true
	if calm_focus_chance > 0.0 and randf() < calm_focus_chance:
		consumed_miss = false

	if consumed_miss:
		_miss_count += 1
		if _hud:
			_hud.mark_miss(_miss_count - 1)
		symbol_missed.emit(_miss_count)
		if _miss_count >= _max_misses:
			await get_tree().create_timer(flash_duration + 0.1).timeout
			_finish_brew(false)
	else:
		_label.text = "Calm Focus saved that one ✨"
		symbol_missed.emit(_miss_count)


func _finish_brew(success: bool) -> void:
	_brewing = false
	_scroll.dismiss()
	_restore_thresholds()

	if _hud:
		await get_tree().create_timer(0.5).timeout
		_hud.hide_hud()

	if success:
		_label.text = "Potion complete! 🧪"
		AudioManager.play_sfx("sfx_brew_complete")
		potion_completed.emit()
	else:
		_label.text = "💥 Exploded!"
		AudioManager.play_sfx("sfx_brew_explode")
		if Main.current_tab == 1:
			HapticsManager.vibrate_heavy()
		potion_exploded.emit()

	await get_tree().create_timer(2.0).timeout
	if not _brewing:
		_label.text = "Tap to brew!"


## Called by Main when player switches away from Brew tab mid-brew.
## Safely aborts the current brew so it doesn't lock up on return.
func abort_brew() -> void:
	if not _brewing:
		return
	_brewing = false
	_scroll.dismiss()
	_restore_thresholds()
	if _hud:
		_hud.hide_hud()
	_label.text = "Tap to brew!"


## Restore per-symbol thresholds modified during brew (brew_lenient)
func _restore_thresholds() -> void:
	for sym in SymbolLibrary.get_symbol_names():
		var key := "_brew_orig_" + sym
		if SymbolLibrary.symbol_thresholds.has(key):
			SymbolLibrary.symbol_thresholds[sym] = SymbolLibrary.symbol_thresholds[key]
			SymbolLibrary.symbol_thresholds.erase(key)


func _flash_cauldron(success: bool) -> void:
	var target_color := flash_color_success if success else flash_color_fail
	_flash.color = target_color
	_pulse_cauldron(success)
	var tween := create_tween()
	tween.tween_property(_flash, "color", Color(target_color.r, target_color.g, target_color.b, 0.0), flash_duration)


func _pulse_cauldron(success: bool) -> void:
	var original_scale := _bg.scale
	var pop := Vector2(1.06, 1.06) if success else Vector2(0.94, 0.94)
	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(_bg, "scale", pop, 0.08)
	t.tween_property(_bg, "scale", original_scale, 0.12)
