extends Control
class_name RatfolkSprite
## Animated Ratfolk shopkeeper with a mimic cash register.
## Built entirely from ColorRects. Blinks, twitches ears, register pops open.

const FUR       := Color(0.58, 0.48, 0.40, 1.0)
const FUR_DARK  := Color(0.42, 0.33, 0.26, 1.0)
const EYE_W     := Color(0.95, 0.95, 0.95, 1.0)
const PUPIL     := Color(0.08, 0.05, 0.05, 1.0)
const NOSE      := Color(0.85, 0.45, 0.50, 1.0)
const SHIRT     := Color(0.14, 0.28, 0.52, 1.0)  # merchant blue
const APRON     := Color(0.88, 0.80, 0.62, 1.0)
const REGISTER  := Color(0.22, 0.20, 0.18, 1.0)
const REG_KEYS  := Color(0.35, 0.32, 0.28, 1.0)
const REG_DRAW  := Color(0.55, 0.42, 0.18, 1.0)  # gold-ish drawer
const MIMIC_EYE := Color(0.95, 0.75, 0.10, 1.0)  # glowing amber
const TOOTH     := Color(0.96, 0.94, 0.88, 1.0)
const COIN      := Color(0.92, 0.78, 0.12, 1.0)

var _ear_l: ColorRect
var _ear_r: ColorRect
var _eye_l: ColorRect
var _eye_r: ColorRect
var _pupil_l: ColorRect
var _pupil_r: ColorRect
var _reg_drawer: ColorRect
var _mimic_eye: ColorRect
var _mimic_tooth_l: ColorRect
var _mimic_tooth_r: ColorRect
var _coin: ColorRect
var _tail: ColorRect

var _base_y: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(110, 130)
	_build()
	_base_y = position.y
	_start_idle()
	_start_blink()
	_start_ear_twitch()
	_start_register_cha_ching()


func _build() -> void:
	# Tail (behind body)
	_tail = _rect(FUR_DARK, Vector2(0, 85), Vector2(8, 40))
	_rect(FUR_DARK, Vector2(6, 105), Vector2(12, 8))

	# Body / shirt
	_rect(SHIRT, Vector2(22, 50), Vector2(50, 45))
	# Apron
	_rect(APRON, Vector2(32, 54), Vector2(30, 38))

	# Arms
	_rect(FUR, Vector2(10, 54), Vector2(16, 10))
	_rect(FUR, Vector2(68, 54), Vector2(16, 10))

	# Ears
	_ear_l = _rect(FUR, Vector2(22, 2), Vector2(12, 20))
	_rect(NOSE, Vector2(24, 4), Vector2(8, 14))  # inner ear
	_ear_r = _rect(FUR, Vector2(60, 2), Vector2(12, 20))
	_rect(NOSE, Vector2(62, 4), Vector2(8, 14))

	# Head
	_rect(FUR, Vector2(20, 18), Vector2(54, 36))

	# Muzzle
	_rect(FUR_DARK, Vector2(30, 38), Vector2(34, 16))

	# Nose
	_rect(NOSE, Vector2(42, 36), Vector2(10, 7))

	# Eyes
	_eye_l = _rect(EYE_W, Vector2(26, 24), Vector2(12, 10))
	_eye_r = _rect(EYE_W, Vector2(56, 24), Vector2(12, 10))
	_pupil_l = _rect(PUPIL, Vector2(29, 26), Vector2(6, 7))
	_pupil_r = _rect(PUPIL, Vector2(59, 26), Vector2(6, 7))

	# Whiskers
	_rect(FUR_DARK, Vector2(8, 42), Vector2(22, 2))
	_rect(FUR_DARK, Vector2(8, 46), Vector2(22, 2))
	_rect(FUR_DARK, Vector2(64, 42), Vector2(22, 2))
	_rect(FUR_DARK, Vector2(64, 46), Vector2(22, 2))

	# ── Mimic Cash Register ───────────────────────────────────────────────
	# Register body
	_rect(REGISTER, Vector2(78, 52), Vector2(28, 38))
	# Keys panel
	_rect(REG_KEYS, Vector2(81, 56), Vector2(22, 18))
	# Key bumps (3x2 grid)
	for row in 2:
		for col in 3:
			_rect(Color(0.5, 0.5, 0.5, 1.0), Vector2(83 + col * 7, 58 + row * 8), Vector2(5, 5))

	# Mimic mouth / drawer — animates open
	_reg_drawer = _rect(REG_DRAW, Vector2(78, 80), Vector2(28, 10))
	# Mimic teeth
	_mimic_tooth_l = _rect(TOOTH, Vector2(80, 78), Vector2(6, 4))
	_mimic_tooth_r = _rect(TOOTH, Vector2(96, 78), Vector2(6, 4))
	# Mimic eye (the one creepy register eye)
	_mimic_eye = _rect(MIMIC_EYE, Vector2(88, 60), Vector2(8, 8))
	_rect(PUPIL, Vector2(90, 62), Vector2(4, 4))

	# Coin (pops out during cha-ching)
	_coin = _rect(COIN, Vector2(92, 75), Vector2(8, 8))
	_coin.visible = false


func _rect(color: Color, pos: Vector2, sz: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = sz
	add_child(r)
	return r


func _start_idle() -> void:
	var t := create_tween().set_loops()
	t.tween_property(self, "position:y", _base_y - 4.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "position:y", _base_y, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_blink() -> void:
	_schedule_blink()


func _schedule_blink() -> void:
	await get_tree().create_timer(randf_range(2.0, 4.5)).timeout
	if not is_inside_tree():
		return
	_eye_l.size.y = 2.0; _eye_r.size.y = 2.0
	_pupil_l.visible = false; _pupil_r.visible = false
	await get_tree().create_timer(0.09).timeout
	if not is_inside_tree():
		return
	_eye_l.size.y = 10.0; _eye_r.size.y = 10.0
	_pupil_l.visible = true; _pupil_r.visible = true
	_schedule_blink()


func _start_ear_twitch() -> void:
	_schedule_ear_twitch()


func _schedule_ear_twitch() -> void:
	await get_tree().create_timer(randf_range(1.5, 4.0)).timeout
	if not is_inside_tree():
		return
	var t := create_tween()
	t.tween_property(_ear_l, "position:y", -2.0, 0.08)
	t.tween_property(_ear_l, "position:y", 2.0, 0.12)
	t.tween_property(_ear_l, "position:y", 0.0, 0.10)
	await get_tree().create_timer(0.15).timeout
	if not is_inside_tree():
		return
	var t2 := create_tween()
	t2.tween_property(_ear_r, "position:y", -2.0, 0.08)
	t2.tween_property(_ear_r, "position:y", 2.0, 0.12)
	t2.tween_property(_ear_r, "position:y", 0.0, 0.10)
	await t2.finished
	if not is_inside_tree():
		return
	_schedule_ear_twitch()


func _start_register_cha_ching() -> void:
	_schedule_cha_ching()


func _schedule_cha_ching() -> void:
	await get_tree().create_timer(randf_range(3.0, 6.0)).timeout
	if not is_inside_tree():
		return
	# Drawer pops open
	var t := create_tween()
	t.tween_property(_reg_drawer, "position:y", 86.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_mimic_tooth_l, "position:y", 72.0, 0.12)
	t.tween_property(_mimic_tooth_r, "position:y", 72.0, 0.12)
	# Mimic eye pulses
	t.parallel().tween_property(_mimic_eye, "color", Color(1.0, 0.9, 0.1, 1.0), 0.1)
	# Coin pops out
	_coin.visible = true
	_coin.position.y = 75.0
	t.tween_property(_coin, "position:y", 60.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_coin, "modulate:a", 0.0, 0.3)
	# Close up
	t.tween_property(_reg_drawer, "position:y", 80.0, 0.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(_mimic_tooth_l, "position:y", 78.0, 0.2)
	t.tween_property(_mimic_tooth_r, "position:y", 78.0, 0.2)
	t.tween_property(_mimic_eye, "color", MIMIC_EYE, 0.2)
	await t.finished
	if not is_inside_tree():
		return
	_coin.visible = false
	_coin.modulate.a = 1.0
	_schedule_cha_ching()
