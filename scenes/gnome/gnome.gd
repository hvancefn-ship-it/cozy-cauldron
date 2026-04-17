extends Control
class_name Gnome
## A single gnome helper. Automatically brews potions and/or sells them
## based on purchased upgrades. Shown as a little ColorRect creature.

## Emitted when gnome completes a brew cycle. Passes potion count.
signal gnome_brewed(count: int)
## Emitted when a random event fires.
signal gnome_event(event_text: String, gold_bonus: int)

@export var gnome_index: int = 0

@onready var _body: ColorRect     = $Body
@onready var _eye_l: ColorRect    = $EyeL
@onready var _eye_r: ColorRect    = $EyeR
@onready var _hat: ColorRect      = $Hat
@onready var _status: Label       = $Status
@onready var _brew_timer: Timer   = $BrewTimer
@onready var _event_timer: Timer  = $EventTimer
@onready var _progress: ColorRect = $ProgressBar/Fill

const GNOME_COLORS := [
	Color(0.6, 0.3, 0.15, 1.0),
	Color(0.2, 0.4, 0.6, 1.0),
	Color(0.5, 0.2, 0.5, 1.0),
	Color(0.2, 0.5, 0.3, 1.0),
]
const HAT_COLORS := [
	Color(0.7, 0.15, 0.15, 1.0),
	Color(0.15, 0.15, 0.7, 1.0),
	Color(0.15, 0.6, 0.15, 1.0),
	Color(0.6, 0.5, 0.1, 1.0),
]

const BASE_BREW_TIME := 20.0
const BASE_EVENT_TIME := 60.0

var _brew_elapsed: float = 0.0


func _ready() -> void:
	var idx := gnome_index % GNOME_COLORS.size()
	_body.color = GNOME_COLORS[idx]
	_hat.color  = HAT_COLORS[idx]
	_status.text = "🧹 Ready"

	_brew_timer.timeout.connect(_on_brew_timer)
	_event_timer.timeout.connect(_on_event_timer)

	_apply_timers()
	_brew_timer.start()
	_event_timer.start()

	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)


func _process(delta: float) -> void:
	# Animate progress bar
	if not _brew_timer.is_stopped():
		_brew_elapsed += delta
		var ratio := clampf(_brew_elapsed / _brew_timer.wait_time, 0.0, 1.0)
		_progress.offset_right = 60.0 * ratio


func _apply_timers() -> void:
	var speed_mult: float = UpgradeManager.get_value("gnome_speed")
	_brew_timer.wait_time = max(5.0, BASE_BREW_TIME * speed_mult)
	_event_timer.wait_time = max(20.0, BASE_EVENT_TIME / max(1.0,
		1.0 + UpgradeManager.get_value("gnome_events")))


func _on_upgrade_purchased(id: String) -> void:
	if id in ["gnome_speed", "gnome_events"]:
		_apply_timers()


func _on_brew_timer() -> void:
	_brew_elapsed = 0.0

	# Ask Main if there's enough slime before committing to a brew.
	var host: Node = get_parent()
	while host != null and not host.has_method("consume_slime_for_brew_attempt"):
		host = host.get_parent()
	if host == null:
		_status.text = "🧱 No host"
		return
	if not bool(host.consume_slime_for_brew_attempt()):
		_status.text = "🫧 Need slime..."
		return

	var base_count := 1 + int(UpgradeManager.get_value("gnome_brew"))

	# Accuracy: chance of failure reduced by upgrade
	var fail_chance := 0.15 - UpgradeManager.get_value("gnome_accuracy")
	if randf() < max(0.0, fail_chance):
		_status.text = "💥 Failed!"
		await get_tree().create_timer(1.5).timeout
		_status.text = "🔄 Retrying..."
		return

	_status.text = "🧪 Brewed x%d!" % base_count
	gnome_brewed.emit(base_count)

	await get_tree().create_timer(2.0).timeout
	_status.text = "⏳ Brewing..."


func _on_event_timer() -> void:
	# Roll a random gnome event
	var events := [
		{"text": "🧹 %s swept the floor — found a coin!" % _gnome_name(), "gold": 1 + int(UpgradeManager.get_value("gnome_find"))},
		{"text": "📦 %s found old inventory — selling at discount!" % _gnome_name(), "gold": 3},
		{"text": "👤 %s brought in a customer!" % _gnome_name(), "gold": 0},
		{"text": "🍄 %s found mushrooms — bonus ingredient!" % _gnome_name(), "gold": 0},
		{"text": "💰 %s found coins behind the cauldron!" % _gnome_name(), "gold": 2 + int(UpgradeManager.get_value("gnome_find"))},
	]
	var e: Dictionary = events[randi() % events.size()]
	_status.text = "✨ Event!"
	gnome_event.emit(e.text, e.gold)


func _gnome_name() -> String:
	var names := ["Bimble", "Snork", "Fizz", "Grub"]
	return names[gnome_index % names.size()]
