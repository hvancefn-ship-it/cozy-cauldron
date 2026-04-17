extends Control
class_name Training
## Symbol training tool. Draw a stroke, see what it matched and at what score,
## then save it as a template for any symbol to improve recognition.
## Accessible via a hidden gesture or debug button — not a game tab.

@onready var _canvas: DrawingCanvas       = $DrawingCanvas
@onready var _ghost: Line2D               = $GhostLine
@onready var _result_label: Label         = $Panel/VBox/ResultLabel
@onready var _score_label: Label          = $Panel/VBox/ScoreLabel
@onready var _symbol_option: OptionButton = $Panel/VBox/SymbolOption
@onready var _save_btn: Button            = $Panel/VBox/ButtonRow/SaveBtn
@onready var _clear_btn: Button           = $Panel/VBox/ButtonRow/ClearBtn
@onready var _delete_btn: Button          = $Panel/VBox/ButtonRow/DeleteBtn
@onready var _status_label: Label         = $Panel/VBox/StatusLabel
@onready var _threshold_slider: HSlider   = $Panel/VBox/ThresholdRow/ThresholdSlider
@onready var _threshold_label: Label      = $Panel/VBox/ThresholdRow/ThresholdValueLabel
@onready var _threshold_title: Label      = $Panel/VBox/ThresholdRow/ThresholdTitle
@onready var _reset_threshold_btn: Button = $Panel/VBox/ThresholdRow/ResetBtn
@onready var _export_btn: Button          = $Panel/VBox/ExportBtn
@onready var _trained_label: Label        = $Panel/VBox/TrainedLabel
@onready var _bad_trained_label: Label    = $Panel/VBox/BadTrainedLabel
@onready var _mode_toggle: CheckButton    = $Panel/VBox/ModeToggle
@onready var _delete_bad_btn: Button      = $Panel/VBox/ButtonRow/DeleteBadBtn
@onready var _close_btn: Button           = $CloseBtn

var _last_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_canvas.stroke_completed.connect(_on_stroke_completed)
	_save_btn.pressed.connect(_on_save_pressed)
	_clear_btn.pressed.connect(_on_clear_pressed)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_delete_bad_btn.pressed.connect(_on_delete_bad_pressed)
	_mode_toggle.toggled.connect(_on_mode_toggled)
	_threshold_slider.value_changed.connect(_on_threshold_changed)
	_threshold_slider.drag_started.connect(_on_slider_drag_started)
	_threshold_slider.drag_ended.connect(_on_slider_drag_ended)
	_reset_threshold_btn.pressed.connect(_on_reset_threshold_pressed)
	_export_btn.pressed.connect(export_trained_to_output)
	_close_btn.pressed.connect(func() -> void: visible = false)
	_symbol_option.item_selected.connect(_on_symbol_selected)

	_save_btn.disabled = true
	_status_label.text = "Draw the symbol shown above"
	_mode_toggle.button_pressed = false
	_mode_toggle.text = "Save as FAIL example"

	_threshold_slider.min_value = 0.0
	_threshold_slider.max_value = 1.0
	_threshold_slider.step = 0.01

	_rebuild_symbol_list()
	_update_threshold_ui()


func _rebuild_symbol_list() -> void:
	_symbol_option.clear()
	for sym_name in SymbolLibrary.get_symbol_names():
		_symbol_option.add_item(sym_name.capitalize())
	_update_trained_label()
	_draw_ghost()


func _update_trained_label() -> void:
	var sym_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	var good_count := SymbolLibrary.trained_count(sym_name)
	var bad_count := SymbolLibrary.negative_trained_count(sym_name)
	_trained_label.text = "PASS examples for '%s': %d" % [sym_name.capitalize(), good_count]
	_bad_trained_label.text = "FAIL examples for '%s': %d" % [sym_name.capitalize(), bad_count]
	_delete_btn.disabled = good_count == 0
	_delete_bad_btn.disabled = bad_count == 0


func _draw_ghost() -> void:
	_ghost.clear_points()
	var sym_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	var template_pts := SymbolLibrary.get_template_points(sym_name)
	if template_pts.is_empty():
		return
	# Center ghost in the top drawing area (above the divider at 53%)
	var draw_area_center := Vector2(get_viewport_rect().size.x * 0.5,
									get_viewport_rect().size.y * 0.27)
	var display_pts := SymbolMatcher.get_display_points(template_pts, draw_area_center, 200.0)
	for p in display_pts:
		_ghost.add_point(p)


func _on_symbol_selected(_index: int) -> void:
	_update_trained_label()
	_update_threshold_ui()
	_draw_ghost()
	_canvas.clear()
	_last_points = PackedVector2Array()
	_save_btn.disabled = true
	_result_label.text = ""
	_score_label.text = ""
	_status_label.text = "Draw the symbol shown above"


func _update_threshold_ui() -> void:
	var sym_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	var has_override := SymbolLibrary.symbol_thresholds.has(sym_name)
	var value := SymbolLibrary.get_threshold(sym_name)
	_threshold_slider.set_value_no_signal(value)
	_threshold_label.text = "%.2f" % value
	if has_override:
		_threshold_title.text = "%s:" % sym_name.capitalize()
		_threshold_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3, 1.0))
		_reset_threshold_btn.disabled = false
	else:
		_threshold_title.text = "Global:"
		_threshold_title.remove_theme_color_override("font_color")
		_reset_threshold_btn.disabled = true


func _on_slider_drag_started() -> void:
	_canvas.enabled = false


func _on_slider_drag_ended(_value_changed: bool) -> void:
	_canvas.enabled = true


func _on_stroke_completed(points: PackedVector2Array) -> void:
	_last_points = points
	_save_btn.disabled = false

	var selected_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]

	# What the system actually thinks you drew (best match across ALL symbols)
	var best := SymbolMatcher.recognize(points, SymbolLibrary._templates)

	# How well your stroke matched the SELECTED symbol specifically
	var selected_templates: Array = []
	for t in SymbolLibrary._templates:
		if t.name == selected_name:
			selected_templates.append(t)
	var selected_score := 0.0
	if not selected_templates.is_empty():
		var selected_result := SymbolMatcher.recognize(points, selected_templates)
		selected_score = selected_result.score

	var passes_threshold := selected_score >= SymbolLibrary.match_threshold
	var pass_fail := "✓ PASS" if passes_threshold else "✗ FAIL"
	var pass_color := Color.GREEN if passes_threshold else Color.RED

	# Line 1: what the system thought you drew
	if best.name == selected_name:
		_result_label.text = "Best match: %s ← correct!" % best.name.capitalize()
		_result_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_result_label.text = "Best match: %s (you selected %s)" % [
			best.name.capitalize(), selected_name.capitalize()
		]
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))

	# Line 2: score for the SELECTED symbol
	_score_label.text = "%s score: %.1f%%  |  %s" % [
		selected_name.capitalize(), selected_score * 100.0, pass_fail
	]
	_score_label.add_theme_color_override("font_color", pass_color)
	if _mode_toggle.button_pressed:
		_status_label.text = "Hit Save to add this stroke as a FAIL '%s' example" % selected_name.capitalize()
	else:
		_status_label.text = "Hit Save to add this stroke as a PASS '%s' example" % selected_name.capitalize()


func _on_save_pressed() -> void:
	if _last_points.is_empty():
		return
	var selected_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	if _mode_toggle.button_pressed:
		SymbolLibrary.register_negative_symbol(selected_name, _last_points)
		_status_label.text = "✓ Saved FAIL example. Draw another or switch symbol."
	else:
		SymbolLibrary.register_symbol(selected_name, _last_points)
		_status_label.text = "✓ Saved PASS example. Draw another or switch symbol."
	_canvas.clear()
	_draw_ghost()
	_save_btn.disabled = true
	_last_points = PackedVector2Array()
	_update_trained_label()


func _on_clear_pressed() -> void:
	_canvas.clear()
	_save_btn.disabled = true
	_last_points = PackedVector2Array()
	_result_label.text = ""
	_score_label.text = ""
	_status_label.text = "Draw a symbol above"


func _on_delete_pressed() -> void:
	var selected_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	SymbolLibrary.clear_trained(selected_name)
	_status_label.text = "🗑 Cleared PASS templates for '%s'" % selected_name.capitalize()
	_update_trained_label()

func _on_delete_bad_pressed() -> void:
	var selected_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	SymbolLibrary.clear_negative_trained(selected_name)
	_status_label.text = "🗑 Cleared FAIL templates for '%s'" % selected_name.capitalize()
	_update_trained_label()

func _on_mode_toggled(is_fail_mode: bool) -> void:
	if is_fail_mode:
		_status_label.text = "FAIL mode: save bad drawings as rejection examples."
	else:
		_status_label.text = "PASS mode: save good drawings as accepted examples."


## Prints all trained templates as GDScript to the Output panel.
## Copy-paste the output into symbol_library.gd _register_defaults() to ship them.
func export_trained_to_output() -> void:
	print("# ---- TRAINED TEMPLATE EXPORT ----")
	for t in SymbolLibrary._templates:
		if not t.get("trained", false):
			continue
		var pts: PackedVector2Array = t.points
		var lines: Array[String] = []
		for p in pts:
			lines.append("Vector2(%.4f, %.4f)" % [p.x, p.y])
		print('_register_raw("%s", [%s])' % [t.name, ", ".join(lines)])
	print("# ---- END EXPORT ----")
	_status_label.text = "Exported to Output panel — copy into _register_defaults()"


func _on_threshold_changed(value: float) -> void:
	var sym_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	SymbolLibrary.set_threshold(sym_name, value)
	_threshold_label.text = "%.2f" % value
	_update_threshold_ui()


func _on_reset_threshold_pressed() -> void:
	var sym_name := SymbolLibrary.get_symbol_names()[_symbol_option.selected]
	SymbolLibrary.clear_threshold(sym_name)
	_update_threshold_ui()
	_status_label.text = "'%s' now uses global threshold (%.2f)" % [
		sym_name.capitalize(), SymbolLibrary.match_threshold
	]
