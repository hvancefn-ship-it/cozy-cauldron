extends Control
class_name Shop

signal potion_sold(gold_earned: int)
signal gold_changed(new_total: int)

@export var base_potion_value: int = 10
@export_range(1, 6, 1) var base_max_customers: int = 3
@export var base_spawn_interval: float = 8.0
@export var base_customer_patience: float = 25.0
@export var gold: int = 0

@onready var _gold_label: Label           = $TopBar/GoldLabel
@onready var _stock_label: Label          = $TopBar/StockLabel
@onready var _ratfolk_sprite: Control     = $RatfolkSprite
@onready var _shelf: HBoxContainer        = $ShelfArea/Shelf
@onready var _customer_row: HBoxContainer = $CustomerRow
@onready var _feedback_label: Label       = $FeedbackLabel
@onready var _spawn_timer: Timer          = $SpawnTimer
@onready var _empty_label: Label          = $ShelfArea/EmptyLabel
@onready var _trickle_timer: Timer        = $TrickleTimer

const CustomerScene := preload("res://scenes/customer/customer.tscn")

var _shelf_stock: int = 0
var _active_customers: Array[Customer] = []
var _total_served: int = 0


func _ready() -> void:
	_apply_spawn_interval()
	_spawn_timer.timeout.connect(_on_spawn_timer)
	_spawn_timer.start()
	_trickle_timer.timeout.connect(_on_trickle)
	_trickle_timer.start()
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_refresh_ratfolk_sprite()
	_refresh_ui()


func _on_upgrade_purchased(id: String) -> void:
	match id:
		"sell_spawn":
			_apply_spawn_interval()
		"manager_ratfolk":
			_refresh_ratfolk_sprite()
		_:
			pass


func _refresh_ratfolk_sprite() -> void:
	var unlocked: bool = UpgradeManager.get_level("manager_ratfolk") > 0
	var target: float = 1.0 if unlocked else 0.0
	if _ratfolk_sprite.modulate.a != target:
		var t := create_tween()
		t.tween_property(_ratfolk_sprite, "modulate:a", target, 0.6)


func _apply_spawn_interval() -> void:
	var multiplier: float = UpgradeManager.get_value("sell_spawn")
	_spawn_timer.wait_time = max(1.5, base_spawn_interval * multiplier)


func _get_max_customers() -> int:
	return base_max_customers + int(UpgradeManager.get_value("sell_capacity"))


func _get_patience() -> float:
	return base_customer_patience + UpgradeManager.get_value("sell_patience")


func _get_potion_value(amount: int) -> int:
	var base := (base_potion_value
		+ int(UpgradeManager.get_value("sell_value_1"))
		+ int(UpgradeManager.get_value("sell_value_2"))
		+ int(UpgradeManager.get_value("sell_value_3"))
		+ int(UpgradeManager.get_value("sell_value_4"))
		+ int(UpgradeManager.get_value("sell_value_5")))

	var total := base * amount

	if amount >= 2:
		var bulk_bonus: float = UpgradeManager.get_value("sell_bulk")
		total = int(float(total) * (1.0 + bulk_bonus))

	var sale_chance: float = UpgradeManager.get_value("shop_sale")
	if sale_chance > 0.0 and randf() < sale_chance:
		total *= 2
		_show_feedback("⚡ FLASH SALE! x2 gold!", Color(1.0, 0.9, 0.1, 1.0))

	var loyalty_bonus: float = UpgradeManager.get_value("sell_loyalty")
	if loyalty_bonus > 0.0:
		var loyalty_mult := 1.0 + loyalty_bonus * float(_total_served)
		loyalty_mult = min(loyalty_mult, 1.5)
		total = int(float(total) * loyalty_mult)

	var decor: float = (
		UpgradeManager.get_value("shop_decor_1") +
		UpgradeManager.get_value("shop_decor_2") +
		UpgradeManager.get_value("shop_decor_3") +
		UpgradeManager.get_value("shop_decor_4"))
	if decor > 0.0:
		total = int(float(total) * (1.0 + decor))

	return total


func add_potions(count: int) -> void:
	_shelf_stock = max(0, _shelf_stock + count)
	_refresh_ui()


func get_stock() -> int:
	return _shelf_stock


func get_gold() -> int:
	return gold


func set_gold_amount(value: int) -> void:
	gold = max(0, value)
	gold_changed.emit(gold)
	_refresh_ui()


func get_unit_sale_value() -> int:
	return _get_potion_value(1)


func can_auto_sell() -> bool:
	if _active_customers.is_empty():
		return false
	var customer: Customer = _active_customers[0]
	if customer == null:
		return false
	return _shelf_stock >= customer.request_amount


func auto_sell_once(multiplier: float = 1.0) -> bool:
	if _active_customers.is_empty():
		return false
	var customer: Customer = _active_customers[0]
	if customer == null:
		return false
	var amount: int = customer.request_amount
	if _shelf_stock < amount:
		return false
	_shelf_stock -= amount
	var earned := int(float(_get_potion_value(amount)) * multiplier)
	gold += earned
	_total_served += 1
	potion_sold.emit(earned)
	gold_changed.emit(gold)
	customer._serve_success()
	_refresh_ui()
	return true


func spawn_bonus_customer() -> void:
	if _active_customers.size() >= _get_max_customers():
		return
	_spawn_customer()


func reset_for_prestige(new_gold: int) -> void:
	gold = new_gold
	_shelf_stock = 0
	_total_served = 0
	_refresh_ui()


func _on_spawn_timer() -> void:
	if _active_customers.size() >= _get_max_customers():
		return
	_spawn_customer()


func _spawn_customer() -> void:
	var c: Customer = CustomerScene.instantiate()
	var max_request: int = max(1, int(floor(_shelf_stock * 0.4)))
	c.request_amount = clamp(randi_range(1, 3), 1, max(1, max_request))
	c.patience = _get_patience()
	c.served.connect(_on_customer_served.bind(c))
	c.left_unserved.connect(_on_customer_left.bind(c))
	c.tree_exited.connect(_on_customer_removed.bind(c))
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_customer_row.add_child(c)
	_active_customers.append(c)
	_refresh_ui()


func _on_customer_served(amount: int, customer: Customer) -> void:
	if _shelf_stock < amount:
		_show_feedback("Need %d 🧪 — only have %d!" % [amount, _shelf_stock], Color.RED)
		customer._flash_no_stock()
		return
	_shelf_stock -= amount
	var earned := _get_potion_value(amount)
	gold += earned
	_total_served += 1
	potion_sold.emit(earned)
	gold_changed.emit(gold)
	customer._serve_success()
	AudioManager.play_sfx("sfx_gold_earn")
	_show_feedback("+%d gold 🪙" % earned, Color.GREEN, true)
	_refresh_ui()


func _on_customer_left(_customer: Customer) -> void:
	_show_feedback("Customer left unhappy! 😤", Color(1.0, 0.5, 0.1, 1.0))
	AudioManager.play_sfx("sfx_customer_leave")
	if Main.current_tab == 2:
		HapticsManager.vibrate_medium()


func _on_customer_removed(customer: Customer) -> void:
	_active_customers.erase(customer)
	_refresh_ui()


func _on_trickle() -> void:
	var trickle: int = int(UpgradeManager.get_value("shop_trickle"))
	if trickle <= 0:
		return
	gold += trickle
	gold_changed.emit(gold)
	_refresh_ui()


func _show_feedback(msg: String, color: Color = Color.WHITE, pop_gold: bool = false) -> void:
	_feedback_label.text = msg
	_feedback_label.add_theme_color_override("font_color", color)
	_feedback_label.visible = true
	_feedback_label.modulate.a = 1.0

	_feedback_label.scale = Vector2.ONE * 0.9
	var pop := create_tween()
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_feedback_label, "scale", Vector2.ONE, 0.14)
	if pop_gold:
		_gold_label.scale = Vector2.ONE
		pop.parallel().tween_property(_gold_label, "scale", Vector2.ONE * 1.12, 0.08)
		pop.tween_property(_gold_label, "scale", Vector2.ONE, 0.10)

	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void:
		_feedback_label.visible = false
		_feedback_label.modulate.a = 1.0
	)


func _refresh_ui() -> void:
	_gold_label.text = "🪙 %d" % gold
	_stock_label.text = "🧪 %d" % _shelf_stock

	for ch in _shelf.get_children():
		ch.queue_free()
	var max_slots: int = 8 + int(UpgradeManager.get_value("shop_shelf"))
	var visible_stock: int = min(_shelf_stock, max_slots)
	for _i in range(visible_stock):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(36, 56)
		dot.color = Color(0.4, 0.15, 0.55, 1.0)
		_shelf.add_child(dot)

	_empty_label.visible = _shelf_stock == 0
