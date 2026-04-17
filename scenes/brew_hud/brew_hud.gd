extends Control
class_name BrewHUD
## Top-of-screen HUD during an active brew.
## Left side: symbol progress dots (grey → green on success).
## Right side: miss pips (dark → red on each miss).

@export var symbol_count: int = 3:
	set(v):
		symbol_count = v
		_rebuild()

@export var max_misses: int = 3:
	set(v):
		max_misses = v
		_rebuild()

## Dot size in pixels.
@export var dot_size: float = 28.0
## Gap between dots.
@export var dot_gap: float = 10.0

@export var color_pending: Color  = Color(0.4, 0.4, 0.4, 1.0)
@export var color_success: Color  = Color(0.2, 0.9, 0.3, 1.0)
@export var color_miss: Color     = Color(0.9, 0.2, 0.2, 1.0)
@export var color_miss_empty: Color = Color(0.25, 0.08, 0.08, 1.0)

@onready var _symbol_row: HBoxContainer = $HBoxOuter/SymbolRow
@onready var _miss_row: HBoxContainer = $HBoxOuter/MissRow

var _symbol_dots: Array[ColorRect] = []
var _miss_pips: Array[ColorRect] = []


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	# Clear children
	for c in _symbol_row.get_children():
		c.queue_free()
	for c in _miss_row.get_children():
		c.queue_free()
	_symbol_dots.clear()
	_miss_pips.clear()

	for _i in range(symbol_count):
		var r := _make_dot(color_pending)
		_symbol_row.add_child(r)
		_symbol_dots.append(r)

	for _i in range(max_misses):
		var r := _make_dot(color_miss_empty)
		_miss_row.add_child(r)
		_miss_pips.append(r)


func _make_dot(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(dot_size, dot_size)
	r.color = color
	return r


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_hud(symbols: int, misses: int) -> void:
	symbol_count = symbols
	max_misses = misses
	visible = true


func hide_hud() -> void:
	visible = false


func mark_symbol_success(index: int) -> void:
	if index < _symbol_dots.size():
		_symbol_dots[index].color = color_success


func mark_miss(miss_index: int) -> void:
	if miss_index < _miss_pips.size():
		_miss_pips[miss_index].color = color_miss


func reset_dots() -> void:
	for d in _symbol_dots:
		d.color = color_pending
	for p in _miss_pips:
		p.color = color_miss_empty
