extends Node2D
class_name DrawingCanvas
## Captures mouse/touch input and draws a Line2D stroke.
## Emits stroke_completed when the player lifts input.

## Stroke colour — change in inspector for theming.
@export var stroke_color: Color = Color(0.2, 0.8, 1.0, 1.0)
## Stroke width in pixels.
@export var stroke_width: float = 6.0
## Minimum distance (pixels) between recorded points (reduces noise).
@export var min_point_distance: float = 8.0
## Whether input is currently accepted.
@export var enabled: bool = true

## Emitted with the raw drawn points when the player lifts their finger/mouse.
signal stroke_completed(points: PackedVector2Array)
## Emitted when drawing starts.
signal stroke_started()

@onready var _line: Line2D = $Line2D

var _drawing := false
var _points := PackedVector2Array()


func _ready() -> void:
	_line.default_color = stroke_color
	_line.width = stroke_width
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_clear_stroke()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return

	# --- Mouse ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_stroke(mb.position)
			else:
				_end_stroke()

	elif event is InputEventMouseMotion and _drawing:
		_extend_stroke((event as InputEventMouseMotion).position)

	# --- Touch ---
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_begin_stroke(st.position)
		else:
			_end_stroke()

	elif event is InputEventScreenDrag and _drawing:
		_extend_stroke((event as InputEventScreenDrag).position)


# ---------------------------------------------------------------------------
# Stroke helpers
# ---------------------------------------------------------------------------

func _begin_stroke(pos: Vector2) -> void:
	_clear_stroke()
	_drawing = true
	_add_point(pos)
	stroke_started.emit()


func _extend_stroke(pos: Vector2) -> void:
	if _points.is_empty() or pos.distance_to(_points[-1]) >= min_point_distance:
		_add_point(pos)


func _end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	if _points.size() >= 2:
		stroke_completed.emit(_points)


func _add_point(pos: Vector2) -> void:
	_points.append(pos)
	_line.add_point(pos)


func _clear_stroke() -> void:
	_points = PackedVector2Array()
	_line.clear_points()


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

## Clear the drawn stroke programmatically (e.g. after successful match).
func clear() -> void:
	_clear_stroke()
