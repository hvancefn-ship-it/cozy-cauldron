extends Control
class_name GnomeManager
## Manages all active gnomes. Spawns/removes gnomes based on gnome_slots upgrade.
## Sits invisible in Main — gnomes brew and sell automatically in the background.

signal gnome_brewed(count: int)
signal gnome_event(text: String, gold: int)

@onready var _gnome_row: HBoxContainer = $GnomeRow
@onready var _event_label: Label       = $EventLabel
@onready var _orc_sprite: TextureRect  = $OrcManagerSprite

const GnomeScene := preload("res://scenes/gnome/gnome.tscn")

var _gnomes: Array[Gnome] = []


func _ready() -> void:
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_sync_gnomes()
	_refresh_orc_sprite()


func _on_upgrade_purchased(id: String) -> void:
	if id == "gnome_slots":
		_sync_gnomes()
	if id == "manager_orc":
		_refresh_orc_sprite()


func _refresh_orc_sprite() -> void:
	const ORC_TEX_PATH := "res://assets/orc_manager.png"
	if _orc_sprite.texture == null and ResourceLoader.exists(ORC_TEX_PATH):
		_orc_sprite.texture = load(ORC_TEX_PATH)
	var unlocked: bool = UpgradeManager.get_level("manager_orc") > 0
	var target_alpha: float = 1.0 if unlocked else 0.0
	if _orc_sprite.modulate.a != target_alpha:
		var t := create_tween()
		t.tween_property(_orc_sprite, "modulate:a", target_alpha, 0.5)


func _sync_gnomes() -> void:
	var target: int = int(UpgradeManager.get_value("gnome_slots"))
	# Spawn more gnomes if needed
	while _gnomes.size() < target:
		_spawn_gnome()
	# Remove extras (shouldn't happen but safe)
	while _gnomes.size() > target:
		var g: Gnome = _gnomes.pop_back()
		g.queue_free()


func _spawn_gnome() -> void:
	var g: Gnome = GnomeScene.instantiate()
	g.gnome_index = _gnomes.size()
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.gnome_brewed.connect(_on_gnome_brewed)
	g.gnome_event.connect(_on_gnome_event)
	_gnome_row.add_child(g)
	_gnomes.append(g)


func _on_gnome_brewed(count: int) -> void:
	gnome_brewed.emit(count)


func _on_gnome_event(text: String, gold: int) -> void:
	gnome_event.emit(text, gold)
	_event_label.text = text
	_event_label.visible = true
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(_event_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		_event_label.visible = false
		_event_label.modulate.a = 1.0
	)


func get_gnome_count() -> int:
	return _gnomes.size()
