extends Control
class_name GnomeSprite
## Animated gnome character built from ColorRects.
## Bobs idle, stirs occasionally, blinks. No image files needed.

var _body: ColorRect
var _hat_brim: ColorRect
var _hat_top: ColorRect
var _eye_l: ColorRect
var _eye_r: ColorRect
var _pupil_l: ColorRect
var _pupil_r: ColorRect
var _beard: ColorRect
var _arm_l: ColorRect
var _arm_r: ColorRect
var _leg_l: ColorRect
var _leg_r: ColorRect
var _spoon: ColorRect
var _spoon_head: ColorRect

const SKIN   := Color(0.96, 0.82, 0.62, 1.0)
const HAT    := Color(0.72, 0.12, 0.12, 1.0)
const SHIRT  := Color(0.18, 0.45, 0.22, 1.0)
const BEARD  := Color(0.95, 0.92, 0.85, 1.0)
const PANTS  := Color(0.25, 0.18, 0.10, 1.0)
const SPOON  := Color(0.72, 0.65, 0.45, 1.0)
const PUPIL  := Color(0.08, 0.05, 0.05, 1.0)
const EYE_W  := Color(0.97, 0.97, 0.97, 1.0)

var _base_y: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(80, 120)
	_build()
	_base_y = position.y
	_start_idle()
	_start_blink()
	_start_stir()


func _build() -> void:
	# Legs
	_leg_l = _rect(PANTS, Vector2(18, 68), Vector2(14, 24))
	_leg_r = _rect(PANTS, Vector2(48, 68), Vector2(14, 24))

	# Body / shirt
	_rect(SHIRT, Vector2(12, 40), Vector2(56, 34))

	# Beard
	_beard = _rect(BEARD, Vector2(22, 50), Vector2(36, 20))

	# Arms
	_arm_l = _rect(SHIRT, Vector2(2, 44), Vector2(14, 10))
	_arm_r = _rect(SHIRT, Vector2(64, 44), Vector2(14, 10))

	# Head
	_rect(SKIN, Vector2(20, 18), Vector2(40, 28))

	# Eyes
	_eye_l = _rect(EYE_W, Vector2(26, 24), Vector2(10, 8))
	_eye_r = _rect(EYE_W, Vector2(44, 24), Vector2(10, 8))
	_pupil_l = _rect(PUPIL, Vector2(29, 26), Vector2(5, 5))
	_pupil_r = _rect(PUPIL, Vector2(47, 26), Vector2(5, 5))

	# Hat brim
	_hat_brim = _rect(HAT, Vector2(14, 16), Vector2(52, 6))
	# Hat top
	_hat_top = _rect(HAT, Vector2(22, 0), Vector2(36, 18))

	# Spoon handle
	_spoon = _rect(SPOON, Vector2(70, 38), Vector2(5, 28))
	# Spoon bowl
	_spoon_head = _rect(SPOON, Vector2(64, 34), Vector2(12, 8))


func _rect(color: Color, pos: Vector2, sz: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = sz
	add_child(r)
	return r


func _start_idle() -> void:
	var t := create_tween().set_loops()
	t.tween_property(self, "position:y", _base_y - 5.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "position:y", _base_y, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_blink() -> void:
	_schedule_blink()


func _schedule_blink() -> void:
	await get_tree().create_timer(randf_range(2.5, 5.0)).timeout
	if not is_inside_tree():
		return
	# Close eyes
	_eye_l.size.y = 2.0; _eye_r.size.y = 2.0
	_pupil_l.visible = false; _pupil_r.visible = false
	await get_tree().create_timer(0.1).timeout
	if not is_inside_tree():
		return
	_eye_l.size.y = 8.0; _eye_r.size.y = 8.0
	_pupil_l.visible = true; _pupil_r.visible = true
	_schedule_blink()


func _start_stir() -> void:
	_schedule_stir()


func _schedule_stir() -> void:
	await get_tree().create_timer(randf_range(1.8, 3.5)).timeout
	if not is_inside_tree():
		return
	# Rotate spoon arm in a little circle
	var t := create_tween()
	t.tween_property(_arm_r, "position:y", 40.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_arm_r, "position:y", 48.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_arm_r, "position:y", 44.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_spoon, "position:x", 66.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_spoon, "position:x", 72.0, 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_spoon, "position:x", 70.0, 0.18).set_trans(Tween.TRANS_SINE)
	await t.finished
	if not is_inside_tree():
		return
	_schedule_stir()
