extends Control
class_name Upgrades
## Upgrade shop panel — shows all upgrades grouped by category tab.
## Reads from UpgradeManager, deducts gold via signal.

## Emitted when an upgrade is purchased. Main deducts the gold.
signal gold_spent(amount: int)
signal ad_boost_requested()

## Must be set by Main so we know current gold.
var current_gold: int = 0
## Must be set by Main so we can gate prestige-locked upgrades.
var prestige_level: int = 0

const PRESTIGE_LOCKED_IDS := ["manager_ratfolk", "manager_orc", "manager_gnome"]

@onready var _category_bar: HBoxContainer = $CategoryBar
@onready var _scroll: ScrollContainer     = $ScrollContainer
@onready var _list: VBoxContainer         = $ScrollContainer/List
@onready var _gold_label: Label           = $TopBar/GoldLabel
@onready var _feedback: Label             = $TopBar/FeedbackLabel
@onready var _ad_boost_btn: Button        = $TopBar/AdBoostBtn
@onready var _ad_boost_label: Label       = $TopBar/AdBoostLabel

var _category_buttons: Array[Button] = []
var _active_category: String = ""
var _ad_boost_stacks: int = 0
var _ad_boost_expires_unix: int = 0


func _ready() -> void:
	_build_category_tabs()
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_ad_boost_btn.pressed.connect(_on_ad_boost_pressed)
	set_process(true)
	_refresh_ad_boost_ui()


func _build_category_tabs() -> void:
	for ch in _category_bar.get_children():
		ch.queue_free()
	_category_buttons.clear()

	for cat in UpgradeManager.get_categories():
		var btn := Button.new()
		btn.text = cat
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		var c := cat  # capture
		btn.pressed.connect(func() -> void: _select_category(c))
		_category_bar.add_child(btn)
		_category_buttons.append(btn)

	# Select first category
	var cats := UpgradeManager.get_categories()
	if not cats.is_empty():
		_select_category(cats[0])


func _select_category(category: String) -> void:
	_active_category = category
	for i in range(_category_buttons.size()):
		var cats := UpgradeManager.get_categories()
		var active := cats[i] == category
		_category_buttons[i].add_theme_color_override(
			"font_color", Color(0.95, 0.8, 0.3, 1.0) if active else Color(0.7, 0.7, 0.7, 1.0)
		)
	_rebuild_list()
	var managers_tab: bool = (category == "Managers")
	_ad_boost_btn.visible = managers_tab
	_ad_boost_label.visible = managers_tab
	_refresh_ad_boost_ui()


func _rebuild_list() -> void:
	for ch in _list.get_children():
		ch.queue_free()

	for def in UpgradeManager.get_all(_active_category):
		var row := _make_row(def)
		_list.add_child(row)


func _make_row(def: Dictionary) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 80)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.18, 0.13, 0.08, 1.0)
	container.add_child(bg)

	var lvl: int = UpgradeManager.get_level(def.id)
	var maxed: bool = lvl >= int(def.max_level)
	var cost: int = UpgradeManager.get_next_cost(def.id)
	var value: float = UpgradeManager.get_value(def.id)

	# Name + desc
	var name_label := Label.new()
	name_label.text = def.name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.position = Vector2(12, 8)
	name_label.size = Vector2(280, 26)
	container.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = def.desc
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
	desc_label.position = Vector2(12, 34)
	desc_label.size = Vector2(280, 20)
	container.add_child(desc_label)

	# Level pips
	var pip_row := HBoxContainer.new()
	pip_row.position = Vector2(12, 56)
	for i in range(def.max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 8)
		pip.color = Color(0.3, 0.85, 0.3, 1.0) if i < lvl else Color(0.3, 0.3, 0.3, 1.0)
		pip_row.add_child(pip)
		if i < def.max_level - 1:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(3, 0)
			pip_row.add_child(gap)
	container.add_child(pip_row)

	# Buy button
	var prestige_locked: bool = (def.id in PRESTIGE_LOCKED_IDS) and prestige_level < 1
	var btn := Button.new()
	if prestige_locked:
		btn.text = "🔒 Prestige 1"
		btn.disabled = true
		desc_label.text = "Unlocks after your first Prestige"
		desc_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1.0))
	elif maxed:
		btn.text = "MAX"
		btn.disabled = true
	else:
		btn.text = "🪙%d" % cost
		btn.disabled = current_gold < cost
	btn.position = Vector2(310, 16)
	btn.size = Vector2(170, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE
	if not maxed and not prestige_locked:
		btn.pressed.connect(_on_buy_pressed.bind(def.id, btn))
	container.add_child(btn)

	return container


func _on_buy_pressed(upgrade_id: String, _btn: Button) -> void:
	var cost := UpgradeManager.purchase(upgrade_id, current_gold)
	if cost < 0:
		return
	AudioManager.play_sfx("sfx_upgrade_buy")
	current_gold -= cost
	gold_spent.emit(cost)
	_gold_label.text = "🪙 %d" % current_gold
	_show_feedback("-🪙%d" % cost)
	_rebuild_list()


func _on_upgrade_purchased(_id: String) -> void:
	_rebuild_list()


func _show_feedback(msg: String) -> void:
	_feedback.text = msg
	_feedback.visible = true
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_feedback, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		_feedback.visible = false
		_feedback.modulate.a = 1.0
	)


func _process(_delta: float) -> void:
	if _active_category == "Managers":
		_refresh_ad_boost_ui()


func _on_ad_boost_pressed() -> void:
	if _ad_boost_stacks >= 2:
		_show_feedback("Ad boost already maxed (2/2)")
		return
	ad_boost_requested.emit()


func set_ad_boost_state(stacks: int, expires_unix: int) -> void:
	_ad_boost_stacks = clampi(stacks, 0, 2)
	_ad_boost_expires_unix = expires_unix
	_refresh_ad_boost_ui()


func _refresh_ad_boost_ui() -> void:
	if AdMobBridge.no_ads:
		_ad_boost_label.text = "⭐ Permanent +50% boost active (No Ads)"
		_ad_boost_btn.text = "Already Active"
		_ad_boost_btn.disabled = true
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _ad_boost_expires_unix <= now_unix:
		_ad_boost_stacks = 0
	var remain: int = max(0, _ad_boost_expires_unix - now_unix)
	var h: int = remain / 3600
	var m: int = (remain % 3600) / 60
	if _ad_boost_stacks > 0 and remain > 0:
		_ad_boost_label.text = "Ad boost: +50%% (%dh %02dm left) • uses %d/2" % [h, m, _ad_boost_stacks]
	else:
		_ad_boost_label.text = "Ad boost: +50% available • uses 0/2"
	_ad_boost_btn.disabled = _ad_boost_stacks >= 2


## Call from Main whenever gold or prestige level changes.
func refresh_gold(gold: int) -> void:
	current_gold = gold
	_gold_label.text = "🪙 %d" % gold
	_rebuild_list()


func refresh_prestige(level: int) -> void:
	prestige_level = level
	_rebuild_list()
