extends Control
class_name Customer
## A single customer waiting to buy potions.
## Tap them to serve. If patience runs out they leave unhappy.

## How many potions this customer wants.
@export var request_amount: int = 1
## How long (seconds) they wait before leaving.
@export var patience: float = 25.0

## Emitted when successfully served. Passes amount sold.
signal served(amount: int)
## Emitted when they leave without being served.
signal left_unserved()

@onready var _head: ColorRect          = $Goblin/Head
@onready var _request_label: Label    = $RequestLabel
@onready var _patience_fill: ColorRect = $PatienceBar/Fill
@onready var _reaction_label: Label   = $ReactionLabel

var _time_left: float = 0.0
var _done: bool = false

const HEAD_COLOR        := Color(0.22, 0.58, 0.16, 1.0)
const HEAD_COLOR_FLASH  := Color(0.85, 0.15, 0.1,  1.0)


func _ready() -> void:
	_time_left = patience
	_request_label.text = "x%d 🧪" % request_amount
	_reaction_label.visible = false


func _process(delta: float) -> void:
	if _done:
		return

	_time_left -= delta
	var ratio := clampf(_time_left / patience, 0.0, 1.0)
	# Shrink fill width by adjusting right offset (bar is 80px wide)
	_patience_fill.offset_right = 80.0 * ratio
	# Colour shifts green → yellow → red
	_patience_fill.color = Color(1.0 - ratio, ratio, 0.1, 1.0)

	if _time_left <= 0.0:
		_leave_unhappy()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed = true
			pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			pressed = true
			pos = st.position
	if pressed and get_global_rect().has_point(pos):
		_try_serve()


# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

## Called by Shop to attempt a sale. Pass current stock.
## Returns true if served, false if not enough stock.
func try_serve(stock: int) -> bool:
	if _done:
		return false
	if stock >= request_amount:
		_serve_success()
		return true
	else:
		_flash_no_stock()
		return false


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _try_serve() -> void:
	served.emit(request_amount)  # Shop decides if stock is available


func _serve_success() -> void:
	_done = true
	_reaction_label.text = "😊"
	_reaction_label.visible = true
	_request_label.visible = false
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _leave_unhappy() -> void:
	if _done:
		return
	_done = true
	_reaction_label.text = "😤"
	_reaction_label.visible = true
	_request_label.visible = false
	left_unserved.emit()
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _flash_no_stock() -> void:
	var tween := create_tween()
	tween.tween_property(_head, "color", HEAD_COLOR_FLASH, 0.1)
	tween.tween_property(_head, "color", HEAD_COLOR, 0.3)
