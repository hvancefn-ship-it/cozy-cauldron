extends Node
## Autoload singleton. Owns all upgrade definitions and purchased levels.
## Other systems call UpgradeManager.get_value("upgrade_id") to read current stat.

signal upgrade_purchased(upgrade_id: String)

const SAVE_PATH := "user://upgrades.json"
const SAVE_VERSION := 1

## Purchased levels: { upgrade_id: int }
var _levels: Dictionary = {}

## All upgrade definitions loaded on ready.
## Each entry: { id, name, desc, category, max_level, base_cost, cost_scale, base_value, value_scale, value_mode }
## value_mode: "add" = base + level*scale, "multiply" = base * scale^level
var _defs: Array[Dictionary] = []


func _ready() -> void:
	_build_definitions()
	_load()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Get current numeric value for an upgrade (factoring in purchased level).
func get_value(upgrade_id: String) -> float:
	var def := _get_def(upgrade_id)
	if def.is_empty():
		return 0.0
	var lvl := get_level(upgrade_id)
	if def.value_mode == "multiply":
		return def.base_value * pow(def.value_scale, lvl)
	else:
		# Additive upgrades should grant 0 at level 0, then +value_scale per level.
		# base_value is treated as metadata/legacy and not applied as free starting bonus.
		return lvl * def.value_scale


## Get current purchased level (0 = not bought).
func get_level(upgrade_id: String) -> int:
	return _levels.get(upgrade_id, 0)


## Get cost to purchase the next level.
func get_next_cost(upgrade_id: String) -> int:
	var def := _get_def(upgrade_id)
	if def.is_empty():
		return 0
	var lvl := get_level(upgrade_id)
	return int(def.base_cost * pow(def.cost_scale, lvl))


## True if this upgrade can be purchased (level < max, enough gold).
func can_afford(upgrade_id: String, gold: int) -> bool:
	var def := _get_def(upgrade_id)
	if def.is_empty():
		return false
	if get_level(upgrade_id) >= def.max_level:
		return false
	return gold >= get_next_cost(upgrade_id)


## Purchase one level. Returns gold spent, or -1 if failed.
func purchase(upgrade_id: String, gold: int) -> int:
	if not can_afford(upgrade_id, gold):
		return -1
	var cost := get_next_cost(upgrade_id)
	_levels[upgrade_id] = get_level(upgrade_id) + 1
	_save()
	upgrade_purchased.emit(upgrade_id)
	return cost


## Return all defs, optionally filtered by category.
func get_all(category: String = "") -> Array[Dictionary]:
	if category == "":
		return _defs
	var result: Array[Dictionary] = []
	for d in _defs:
		if d.category == category:
			result.append(d)
	return result


func get_categories() -> Array[String]:
	var seen: Dictionary = {}
	var cats: Array[String] = []
	for d in _defs:
		if not seen.has(d.category):
			seen[d.category] = true
			cats.append(d.category)
	return cats


## Reset non-prestige upgrades for prestige flow.
## Optionally keep up to `keep_gnome_slots` levels of gnome_slots.
func reset_for_prestige(keep_gnome_slots: int = 0) -> void:
	for def in get_all():
		if def.category == "Prestige":
			continue
		if def.id == "gnome_slots" and keep_gnome_slots > 0:
			var current_lvl: int = get_level("gnome_slots")
			_levels["gnome_slots"] = min(current_lvl, keep_gnome_slots)
			continue
		_levels.erase(def.id)
	_save()

## Debug-only helper: full wipe of all purchased upgrades and save file payload.
func debug_reset_all() -> void:
	_levels.clear()
	_save()


# ---------------------------------------------------------------------------
# Definitions — upgrades across core categories
# ---------------------------------------------------------------------------

func _build_definitions() -> void:

	# ── GATHERING ────────────────────────────────────────────────────────────
	_def("gather_spawn",      "Wild Patch",         "+2 slimes per harvest run",
		"Gathering", 8, 40,   1.8, 0.0, 2.0, "add")
	_def("gather_cooldown",   "Mushroom Compost",   "Harvest cooldown 10% shorter",
		"Gathering", 6, 70,   2.0, 1.0, 0.9, "multiply")
	_def("gather_yield",      "Butcher's Knife",    "+1 slime essence per slime defeated",
		"Gathering", 5, 110,  2.2, 0.0, 1.0, "add")

	# ── BREWING ──────────────────────────────────────────────────────────────
	# symbols_required floor (fewer symbols per brew)
	_def("brew_symbols_1",    "Swift Hands I",      "Potions need 1 fewer symbol",
		"Brewing", 1, 50,   1.0, 0.0, -1.0, "add")
	_def("brew_symbols_2",    "Swift Hands II",     "Potions need 2 fewer symbols total",
		"Brewing", 1, 300,  1.0, 0.0, -1.0, "add")
	_def("brew_symbols_3",    "Master Brewer",      "Potions need 3 fewer symbols total",
		"Brewing", 1, 1200, 1.0, 0.0, -1.0, "add")

	# potions per brew (bonus bottles)
	_def("brew_yield",        "Double Batch",       "+1 potion per completed brew",
		"Brewing", 5, 75,   2.2, 0.0, 1.0, "add")

	# miss tolerance (extra allowed misses before explosion)
	_def("brew_misses",       "Steady Grip",        "+1 allowed miss per brew",
		"Brewing", 4, 60,   2.0, 0.0, 1.0, "add")

	# calm focus: chance to ignore a failed stroke (implemented in cauldron.gd)
	_def("brew_time",         "Calm Focus",         "+5% chance a failed stroke won't consume a miss",
		"Brewing", 5, 40,   1.8, 0.0, 0.05, "add")

	# symbol match leniency: intentionally small to avoid over-forgiving input
	_def("brew_lenient",      "Sloppy Scrawl",      "Symbol matching 1.5% more forgiving",
		"Brewing", 4, 90,   2.0, 0.0, -0.015, "add")

	# auto-complete last symbol
	_def("brew_autocomplete", "Final Flourish",     "Last symbol auto-completes if 80%+ score",
		"Brewing", 1, 500,  1.0, 0.0, 1.0, "add")

	# reduced cauldron cooldown
	_def("brew_cooldown",     "Hot Cauldron",       "Cauldron ready 20% faster after each brew",
		"Brewing", 5, 120,  2.5, 1.0, 0.8, "multiply")

	# bonus on first brew of session
	_def("brew_morning",      "Morning Ritual",     "First brew each session gives 2x potions",
		"Brewing", 1, 250,  1.0, 0.0, 1.0, "add")


	# ── SELLING ──────────────────────────────────────────────────────────────
	# base potion value
	_def("sell_value_1",      "Better Bottles",     "+2 gold per potion sold",
		"Shop", 10, 30,  1.6, 10.0, 2.0, "add")
	_def("sell_value_2",      "Premium Label",      "+5 gold per potion sold",
		"Shop", 8,  150, 1.7, 10.0, 5.0, "add")
	_def("sell_value_3",      "Rare Blend",         "+10 gold per potion sold",
		"Shop", 6,  500, 1.8, 10.0, 10.0, "add")
	_def("sell_value_4",      "Legendary Brew",     "+25 gold per potion sold",
		"Shop", 4,  2000,1.9, 10.0, 25.0, "add")
	_def("sell_value_5",      "Mythic Formula",     "+50 gold per potion sold",
		"Shop", 3,  8000,2.0, 10.0, 50.0, "add")

	# customer patience
	_def("sell_patience",     "Cozy Atmosphere",    "+5s customer patience",
		"Shop", 6, 45,   1.7, 25.0, 5.0, "add")

	# max customers
	_def("sell_capacity",     "Bigger Shopfront",   "+1 max customer at once",
		"Shop", 3, 200,  3.0, 3.0,  1.0, "add")

	# spawn rate (lower = faster — multiplier on interval)
	_def("sell_spawn",        "Word of Mouth",      "New customers arrive 15% faster",
		"Shop", 5, 80,   2.0, 1.0,  0.85, "multiply")

	# bulk discount bonus
	_def("sell_bulk",         "Bulk Deal",          "+20% gold when selling 2+ potions at once",
		"Shop", 3, 300,  2.5, 1.0,  0.2, "add")

	# momentum bonus (scales with total sales in the run)
	_def("sell_loyalty",      "Neighborhood Buzz",  "1% gold bonus per sale served (caps at +50%)",
		"Shop", 5, 180,  2.2, 0.0,  0.01, "add")


	# ── SHOP ─────────────────────────────────────────────────────────────────
	# shelf capacity (visual only for now)
	_def("shop_shelf",        "Extra Shelving",     "+4 visible potion slots on shelf",
		"Shop", 4, 100, 2.0, 8.0, 4.0, "add")

	# idle gold trickle
	_def("shop_trickle",      "Tip Jar",            "+1 gold per 10s passively",
		"Shop", 5, 150, 2.2, 0.0, 1.0, "add")

	# decoration (reputation multiplier placeholder)
	_def("shop_decor_1",      "Cozy Rug",           "+5% all gold earned",
		"Shop", 1, 80,  1.0, 1.0, 0.05, "add")
	_def("shop_decor_2",      "Candlelight",        "+10% all gold earned",
		"Shop", 1, 250, 1.0, 1.0, 0.10, "add")
	_def("shop_decor_3",      "Enchanted Sign",     "+20% all gold earned",
		"Shop", 1, 800, 1.0, 1.0, 0.20, "add")
	_def("shop_decor_4",      "Crystal Chandelier", "+35% all gold earned",
		"Shop", 1, 3000,1.0, 1.0, 0.35, "add")

	# sale event (random bonus)
	_def("shop_sale",         "Flash Sale",         "10% chance of 2x gold per transaction",
		"Shop", 3, 350, 2.5, 0.0, 0.1, "add")


	# ── MANAGERS ────────────────────────────────────────────────────────────
	# Core faction unlocks
	_def("manager_ratfolk",   "Ratfolk Foreman",    "Ratfolk auto-sell to waiting customers (unlocks at Prestige 1)",
		"Managers", 1, 700, 1.0, 0.0, 1.0, "add")
	_def("manager_orc",       "Orc Crew Chief",     "Orcs auto-harvest slime over time (unlocks at Prestige 1)",
		"Managers", 1, 700, 1.0, 0.0, 1.0, "add")
	_def("manager_gnome",     "Gnome Brewmaster",   "Gnomes auto-brew potions over time (unlocks at Prestige 1)",
		"Managers", 1, 700, 1.0, 0.0, 1.0, "add")

	# Efficiency starts intentionally slow; upgrades improve automation throughput.
	_def("manager_offline_eff", "Ledger Discipline", "+8% manager efficiency (all factions)",
		"Managers", 6, 220, 2.0, 0.0, 0.08, "add")
	_def("manager_orc_eff",     "Orc Logistics",     "+10% Orc harvest efficiency",
		"Managers", 5, 180, 1.9, 0.0, 0.10, "add")
	_def("manager_gnome_eff",   "Gnome Workflow",    "+10% Gnome brew efficiency",
		"Managers", 5, 180, 1.9, 0.0, 0.10, "add")
	_def("manager_rat_eff",     "Ratfolk Hustle",    "+10% Ratfolk sales efficiency",
		"Managers", 5, 180, 1.9, 0.0, 0.10, "add")

	# Internal upgrade ids remain gnome_* for save compatibility.
	_def("gnome_slots",       "Crew Quarters",      "Hire 1 additional manager helper",
		"Managers", 4, 500,  3.5, 0.0, 1.0, "add")
	_def("gnome_speed",       "Orc Shift Bell",     "Managers work 15% faster",
		"Managers", 5, 200,  2.2, 1.0, 0.85, "multiply")
	_def("gnome_brew",        "Apprentice Witches", "Managers brew 1 extra potion per cycle",
		"Managers", 4, 400,  2.5, 0.0, 1.0, "add")
	_def("gnome_sell",        "Ratfolk Haggling",   "Ratfolk sales add +3 gold per potion",
		"Managers", 5, 300,  2.0, 0.0, 3.0, "add")
	_def("gnome_events",      "Orc Floor Crew",     "+1 random manager event per hour",
		"Managers", 3, 250,  2.0, 0.0, 1.0, "add")
	_def("gnome_loyalty",     "Guild Contracts",    "Managers never go on strike",
		"Managers", 1, 1000, 1.0, 0.0, 1.0, "add")
	_def("gnome_multi",       "Split Duties",       "Managers can brew & sell simultaneously",
		"Managers", 1, 2000, 1.0, 0.0, 1.0, "add")
	_def("gnome_find",        "Goblin Scavengers",  "Managers find 1 coin per sweep",
		"Managers", 5, 150,  1.8, 0.0, 1.0, "add")
	_def("gnome_customer",    "Orc Street Barkers", "Managers bring in 1 extra customer/hr",
		"Managers", 4, 350,  2.3, 0.0, 1.0, "add")
	_def("gnome_accuracy",    "Veteran Brewers",    "Manager brew cycles fail 12% less often (max 60%)",
		"Managers", 5, 280,  2.0, 0.0, 0.12, "add")


	# ── PRESTIGE ─────────────────────────────────────────────────────────────
	_def("prestige_gold",     "Golden Reputation",  "+10% gold after each prestige",
		"Prestige", 5, 6500, 2.5, 1.0, 0.1, "add")
	_def("prestige_speed",    "Legacy Knowledge",   "Brew symbols faster after prestige",
		"Prestige", 3, 10500, 3.0, 1.0, 0.15, "add")
	_def("prestige_carry",    "Heirloom Chest",     "Keep 10% gold on prestige",
		"Prestige", 5, 7500, 2.8, 0.0, 0.1, "add")
	_def("prestige_unlock",   "Wizard Renown",      "Unlock exclusive prestige-only upgrades",
		"Prestige", 1, 13000,1.0, 0.0, 1.0, "add")
	_def("prestige_gnome",    "Gnome Heirloom",     "Keep 1 gnome slot after prestige",
		"Prestige", 3, 9500, 2.5, 0.0, 1.0, "add")
	_def("prestige_customer", "Famous Shop",        "+2 starting customers after prestige",
		"Prestige", 3, 11500, 3.0, 0.0, 2.0, "add")
	_def("prestige_symbol",   "Muscle Memory",      "Start each prestige with 1 fewer symbol needed",
		"Prestige", 2, 15000,3.5, 0.0, -1.0, "add")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _def(id: String, name: String, desc: String, category: String,
		max_level: int, base_cost: int, cost_scale: float,
		base_value: float, value_scale: float, value_mode: String) -> void:
	_defs.append({
		"id": id, "name": name, "desc": desc, "category": category,
		"max_level": max_level, "base_cost": base_cost, "cost_scale": cost_scale,
		"base_value": base_value, "value_scale": value_scale, "value_mode": value_mode
	})


func _get_def(upgrade_id: String) -> Dictionary:
	for d in _defs:
		if d.id == upgrade_id:
			return d
	return {}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("UpgradeManager: cannot write save")
		return
	var payload := {
		"version": SAVE_VERSION,
		"levels": _levels,
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
		push_warning("UpgradeManager: save parse failed, ignoring malformed save")
		return

	var parsed_dict := parsed as Dictionary
	var raw_levels: Variant = {}

	# Migration path: old save format was raw levels dictionary.
	if parsed_dict.has("levels"):
		raw_levels = parsed_dict.get("levels", {})
	else:
		raw_levels = parsed_dict

	if not (raw_levels is Dictionary):
		push_warning("UpgradeManager: levels payload malformed")
		return

	_levels.clear()
	for k in (raw_levels as Dictionary).keys():
		var key := str(k)
		if _get_def(key).is_empty():
			continue
		var lvl := int((raw_levels as Dictionary).get(k, 0))
		_levels[key] = max(0, lvl)

	print("UpgradeManager: loaded %d purchased upgrades" % _levels.size())
