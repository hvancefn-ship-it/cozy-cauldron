extends Control
class_name Scroll
## The scroll UI shown to the player during active brewing.
## Displays the target symbol ghost, hosts the DrawingCanvas,
## and emits signals for success/failure.

## How long to show result feedback before hiding (seconds).
@export var result_display_time: float = 0.8
## Score threshold forwarded from SymbolLibrary — display-only use here.
@export var score_display: bool = true

## Emitted when the player successfully draws the correct symbol.
signal symbol_matched(symbol_name: String, score: float)
## Emitted when the drawn symbol doesn't match (or score too low).
signal symbol_failed(drawn_score: float)

@onready var _canvas: DrawingCanvas = $DrawingCanvas
@onready var _ghost: Line2D = $GhostLine
@onready var _bg: ColorRect = $Background
@onready var _result_label: Label = $ResultLabel
@onready var _symbol_label: Label = $SymbolNameLabel
@onready var _score_label: Label = $ScoreLabel

var _target_symbol: String = ""
var _result_timer: SceneTreeTimer = null


func _ready() -> void:
	_canvas.stroke_completed.connect(_on_stroke_completed)
	_result_label.visible = false
	_symbol_label.visible = false
	_score_label.visible = false
	hide()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Show the scroll with a specific target symbol.
func show_symbol(symbol_name: String) -> void:
	_target_symbol = symbol_name
	_canvas.clear()
	_canvas.enabled = true
	_result_label.visible = false
	_draw_ghost(symbol_name)

	if score_display:
		_symbol_label.text = symbol_name.capitalize()
		_symbol_label.visible = true

	show()


## Hide and reset scroll.
func dismiss() -> void:
	_canvas.enabled = false
	_canvas.clear()
	_ghost.clear_points()
	_target_symbol = ""
	_result_label.visible = false
	_symbol_label.visible = false
	hide()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _draw_ghost(symbol_name: String) -> void:
	_ghost.clear_points()
	var template_pts := SymbolLibrary.get_template_points(symbol_name)
	if template_pts.is_empty():
		return
	# Use the parchment background's global rect center, converted to local Line2D space
	var bg_rect := _bg.get_global_rect()
	var center := _ghost.to_local(bg_rect.get_center())
	var display_pts := SymbolMatcher.get_display_points(template_pts, center, 280.0)
	for p in display_pts:
		_ghost.add_point(p)


func _on_stroke_completed(points: PackedVector2Array) -> void:
	_canvas.enabled = false
	# Gameplay uses targeted validation only (expected symbol), not global best match.
	var selected_templates := SymbolLibrary._templates.filter(func(t: Dictionary) -> bool:
		return t.name == _target_symbol
	)
	var raw_target := {"name": _target_symbol, "score": 0.0}
	if not selected_templates.is_empty():
		raw_target = SymbolMatcher.recognize(points, selected_templates)
	var result := SymbolLibrary.recognize_for_symbol(points, _target_symbol)

	# Debug score for the expected symbol only
	_score_label.text = "%.0f%% %s" % [raw_target.score * 100.0, _target_symbol]
	_score_label.visible = true

	if result.name == _target_symbol:
		_show_result("✓", Color.GREEN)
		AudioManager.play_sfx("sfx_symbol_success")
		symbol_matched.emit(result.name, result.score)
	else:
		_show_result("✗", Color.RED)
		AudioManager.play_sfx("sfx_symbol_fail" if randi() % 2 == 0 else "sfx_symbol_fail_alt")
		if Main.current_tab == 1:
			HapticsManager.vibrate_medium()
		symbol_failed.emit(result.score)


func _show_result(text: String, color: Color) -> void:
	_result_label.text = text
	_result_label.add_theme_color_override("font_color", color)
	_result_label.visible = true

	if _result_timer != null:
		# Let the existing timer finish; don't double-dismiss
		return
	_result_timer = get_tree().create_timer(result_display_time)
	_result_timer.timeout.connect(_on_result_timeout)


func _on_result_timeout() -> void:
	_result_timer = null
	_canvas.enabled = true
	_result_label.visible = false
	_score_label.visible = false
