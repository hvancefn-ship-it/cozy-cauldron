extends Control
class_name Prestige
## Prestige panel — shown when player has earned enough gold to prestige.
## Resets gold/stock/upgrades but grants Wizard Reputation and permanent bonuses.

const SAVE_PATH := "user://prestige.json"
const SAVE_VERSION := 1
const BASE_PRESTIGE_COST := 6500

signal prestige_completed(new_level: int)

@onready var _level_label: Label   = $VBox/LevelLabel
@onready var _cost_label: Label    = $VBox/CostLabel
@onready var _bonus_label: Label   = $VBox/BonusLabel
@onready var _prestige_btn: Button = $VBox/PrestigeBtn
@onready var _desc_label: Label    = $VBox/DescLabel

var prestige_level: int = 0
var _current_gold: int  = 0


func _ready() -> void:
	_load()
	_prestige_btn.pressed.connect(_on_prestige_pressed)
	_refresh()


# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

func set_gold(gold: int) -> void:
	_current_gold = gold
	_refresh()


func get_prestige_level() -> int:
	return prestige_level


## Gold multiplier from prestige level
func get_gold_multiplier() -> float:
	return 1.0 + (float(prestige_level) * UpgradeManager.get_value("prestige_gold"))


## Starting customers bonus
func get_starting_customers() -> int:
	return int(UpgradeManager.get_value("prestige_customer")) * prestige_level


## Symbols reduction from prestige
func get_symbol_reduction() -> int:
	return int(UpgradeManager.get_value("prestige_symbol")) * prestige_level


# ---------------------------------------------------------------------------
# Prestige action
# ---------------------------------------------------------------------------

func _on_prestige_pressed() -> void:
	var cost := _get_prestige_cost()
	if _current_gold < cost:
		return
	AudioManager.play_sfx("sfx_prestige")
	prestige_level += 1
	_save()
	prestige_completed.emit(prestige_level)
	_refresh()


func _get_prestige_cost() -> int:
	return int(BASE_PRESTIGE_COST * pow(2.5, prestige_level))


func _get_gold_carry() -> int:
	var carry_pct: float = UpgradeManager.get_value("prestige_carry")
	return int(float(_current_gold) * carry_pct)


func get_gold_carry() -> int:
	return _get_gold_carry()

## Debug-only helper: hard reset prestige progression.
func debug_reset_all() -> void:
	prestige_level = 0
	_current_gold = 0
	_save()
	_refresh()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var cost := _get_prestige_cost()
	var carry := _get_gold_carry()
	var gnome_keep: int = int(UpgradeManager.get_value("prestige_gnome")) * min(1, prestige_level)

	_level_label.text = "⭐ Wizard Reputation: %d" % prestige_level
	_cost_label.text  = "Prestige costs: 🪙 %s" % _fmt(cost)
	_prestige_btn.disabled = _current_gold < cost

	var bonuses := ""
	bonuses += "• +%.0f%% gold multiplier per prestige\n" % (UpgradeManager.get_value("prestige_gold") * 100.0)
	if carry > 0:
		bonuses += "• Keep 🪙 %s gold\n" % _fmt(carry)
	if gnome_keep > 0:
		bonuses += "• Keep %d gnome slot(s)\n" % gnome_keep
	var sym_red := int(UpgradeManager.get_value("prestige_symbol"))
	if sym_red < 0:
		bonuses += "• Start with %d fewer symbol(s)\n" % abs(sym_red)
	var start_cust := int(UpgradeManager.get_value("prestige_customer"))
	if start_cust > 0:
		bonuses += "• +%d starting customers\n" % start_cust
	_bonus_label.text = bonuses if bonuses != "" else "Buy Prestige upgrades to gain bonuses!"

	if prestige_level == 0:
		_desc_label.text = "Prestige resets your run but grants permanent wizard power. The shop gets bigger and busier!"
	else:
		_desc_label.text = "Prestige %d complete! You are known throughout the realm." % prestige_level

	_prestige_btn.text = "✨ PRESTIGE (costs 🪙%s)" % _fmt(cost)


func _fmt(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (float(n) / 1000000.0)
	elif n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"version": SAVE_VERSION,
		"level": prestige_level,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var parsed_dict := parsed as Dictionary
	if parsed_dict.has("level"):
		prestige_level = max(0, int(parsed_dict.get("level", 0)))
