extends Control
class_name BottomNav

signal tab_selected(index: int)

@export var active_color: Color   = Color(0.9, 0.75, 0.4, 1.0)
@export var inactive_color: Color = Color(0.55, 0.5, 0.45, 1.0)
@export var locked_color: Color   = Color(0.35, 0.33, 0.32, 1.0)

const TABS := [
	{"label": "Gather",   "locked": false},
	{"label": "Brew",     "locked": false},
	{"label": "Shop",     "locked": false},
	{"label": "Upgrades", "locked": false},
	{"label": "Prestige", "locked": false},
]

var _buttons: Array[Button] = []
var _active_index: int = 1

@onready var _bar: HBoxContainer = $Bar

func _ready() -> void:
	for i in range(TABS.size()):
		var tab: Dictionary = TABS[i]
		var btn := Button.new()
		btn.text = str(tab.label)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(0, 72)

		btn.add_theme_color_override("font_color", inactive_color)
		var idx := i
		btn.pressed.connect(func() -> void: _on_tab_pressed(idx))

		_bar.add_child(btn)
		_buttons.append(btn)

	_set_active(1)
	tab_selected.emit(1)

func _on_tab_pressed(index: int) -> void:
	if index == _active_index:
		return
	_set_active(index)
	tab_selected.emit(index)

func _set_active(index: int) -> void:
	_active_index = index
	for i in range(_buttons.size()):
		var color := active_color if i == index else inactive_color
		_buttons[i].add_theme_color_override("font_color", color)
