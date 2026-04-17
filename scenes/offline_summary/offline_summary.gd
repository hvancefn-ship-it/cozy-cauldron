extends Control
class_name OfflineSummary
## Shows a "While you were away" popup after offline idle progress is applied.

signal dismissed()

@onready var _backdrop: ColorRect   = $Backdrop
@onready var _panel: PanelContainer = $Panel
@onready var _title: Label          = $Panel/VBox/Title
@onready var _body: Label           = $Panel/VBox/Body
@onready var _close_btn: Button     = $Panel/VBox/CloseBtn


func _ready() -> void:
	_close_btn.pressed.connect(_on_close)
	visible = false


func show_summary(elapsed_seconds: int, slime_gained: int, potions_brewed: int, potions_sold: int, gold_earned: int) -> void:
	if elapsed_seconds < 60:
		return

	var h: int = elapsed_seconds / 3600
	var m: int = (elapsed_seconds % 3600) / 60
	var time_str: String = ""
	if h > 0:
		time_str = "%dh %02dm" % [h, m]
	else:
		time_str = "%dm" % m

	_title.text = "While you were away... (%s)" % time_str

	var lines: Array[String] = []
	if slime_gained > 0:
		lines.append("🫧 Orcs harvested %d slime" % slime_gained)
	if potions_brewed > 0:
		lines.append("🧪 Gnomes brewed %d potions" % potions_brewed)
	if potions_sold > 0:
		lines.append("🏪 Ratfolk sold %d potions" % potions_sold)
	if gold_earned > 0:
		lines.append("🪙 Earned %d gold" % gold_earned)

	if lines.is_empty():
		return

	_body.text = "\n".join(lines)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_close() -> void:
	visible = false
	dismissed.emit()
