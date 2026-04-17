extends Control
class_name Onboarding

signal finished

const SAVE_PATH := "user://onboarding_seen.save"

@onready var _title: Label = $Backdrop/Panel/VBox/Title
@onready var _body: RichTextLabel = $Backdrop/Panel/VBox/Body
@onready var _next_btn: Button = $Backdrop/Panel/VBox/ButtonRow/NextBtn
@onready var _skip_btn: Button = $Backdrop/Panel/VBox/ButtonRow/SkipBtn

var _step := 0

var _steps := [
	{
		"title": "Welcome to Cozy Cauldron ✨",
		"body": "You run a tiny magical potion shop.\n\nGather ingredients, brew potions, sell to customers — and automate everything while you sleep."
	},
	{
		"title": "🫧 Gather",
		"body": "Tap [color=#f2d16b]Gather[/color] to slice slimes and collect slime essence.\n\nSlime is your brewing fuel — you need it to make potions."
	},
	{
		"title": "🧪 Brew",
		"body": "Tap the cauldron to start a brew.\nDraw the symbol shown on the scroll.\nMatch enough symbols to complete a potion.\n\nEach attempt costs 5 slime."
	},
	{
		"title": "🏪 Shop",
		"body": "Customers arrive and request potions.\nTap them to sell before their patience runs out.\n\nMore upgrades = bigger payouts and faster customers."
	},
	{
		"title": "👥 Managers",
		"body": "Unlock [color=#f2d16b]Gnomes[/color] to auto-brew, [color=#f2d16b]Orcs[/color] to auto-harvest, and [color=#f2d16b]Ratfolk[/color] to auto-sell.\n\nWith all three unlocked, your shop runs itself — even when you're offline."
	},
	{
		"title": "⭐ Prestige",
		"body": "When you've earned enough gold, [color=#f2d16b]Prestige[/color] to reset your run and gain permanent wizard power.\n\nEach prestige makes every future run stronger."
	}
]


func _ready() -> void:
	_next_btn.pressed.connect(_on_next_pressed)
	_skip_btn.pressed.connect(_finish)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	

func should_show() -> bool:
	return not FileAccess.file_exists(SAVE_PATH)


func start() -> void:
	_step = 0
	_update_step()
	visible = true


func _on_next_pressed() -> void:
	_step += 1
	if _step >= _steps.size():
		_finish()
		return
	_update_step()


func _update_step() -> void:
	var data: Dictionary = _steps[_step]
	_title.text = data.get("title", "")
	_body.text = data.get("body", "")
	_next_btn.text = "Finish" if _step == _steps.size() - 1 else "Next"


func _finish() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string("seen")
		file.close()
	visible = false
	finished.emit()
