extends Control
class_name Main

const TAB_GATHER := 0
const TAB_BREW := 1
const TAB_SHOP := 2
const TAB_UPGRADES := 3
const TAB_PRESTIGE := 4

const SLIME_PER_BREW := 5
const IDLE_SAVE_PATH := "user://idle_state.json"
const OFFLINE_CAP_SECONDS := 12 * 60 * 60
const ORC_HARVEST_INTERVAL := 8.0
const RATFOLK_SELL_INTERVAL := 2.5
const MIN_ORC_INTERVAL := 3.0
const MIN_RATFOLK_INTERVAL := 0.9
const AD_BOOST_DURATION_SECONDS := 6 * 60 * 60
const AD_BOOST_MULTIPLIER := 1.5

@onready var _cauldron: Cauldron = $Cauldron
@onready var _scroll: Scroll = $Scroll
@onready var _brew_hud: BrewHUD = $BrewHUD
@onready var _shop: Shop = $Shop
@onready var _upgrades: Upgrades = $Upgrades
@onready var _prestige: Prestige = $Prestige
@onready var _bottom_nav: BottomNav = $BottomNav
@onready var _gnomes: GnomeManager = $GnomeManager
@onready var _onboarding: Onboarding = $Onboarding
@onready var _training: Training = $Training
@onready var _slime_harvest: SlimeHarvest = $SlimeHarvest
@onready var _offline_summary: Control = $OfflineSummary
@onready var _settings: Control = $Settings
@onready var _settings_btn: Button = $SettingsBtn

var _slime: int = 0
var _active_tab: int = TAB_BREW
var _first_brew_done: bool = false
var _ratfolk_timer: Timer
var _orc_timer: Timer
## Static so other scenes can read active tab without a reference to Main.
static var current_tab: int = 1

var _ad_boost_stacks: int = 0
var _ad_boost_expires_unix: int = 0
var _offline_slime_gained: int = 0
var _offline_potions_brewed: int = 0
var _offline_potions_sold: int = 0
var _offline_gold_earned: int = 0
var _offline_elapsed_seconds: int = 0


func _ready() -> void:
	# Core scene wiring
	_cauldron.set_scroll(_scroll)
	_cauldron.set_hud(_brew_hud)

	# Gameplay events
	_cauldron.potion_completed.connect(_on_potion_completed)
	_shop.potion_sold.connect(_on_potion_sold_prestige_bonus)
	_shop.gold_changed.connect(_on_gold_changed)
	_upgrades.gold_spent.connect(_on_gold_spent)
	_upgrades.ad_boost_requested.connect(_on_ad_boost_requested)
	_prestige.prestige_completed.connect(_on_prestige_completed)
	_gnomes.gnome_brewed.connect(_on_gnome_brewed)
	_slime_harvest.slime_collected.connect(_on_slime_collected)
	_slime_harvest.closed.connect(_on_slime_harvest_closed)
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)

	# Nav / UI events
	_bottom_nav.tab_selected.connect(_on_tab_selected)
	_settings_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("sfx_button_tap")
		_settings.open())

	_training.visible = false
	_slime_harvest.visible = false

	_setup_manager_timers()
	_apply_offline_idle_progress()
	AdMobBridge.no_ads_purchased.connect(_on_no_ads_granted)
	AdMobBridge.no_ads_restored.connect(_on_no_ads_granted)
	AdMobBridge.banner_visibility_changed.connect(_on_banner_visibility_changed)
	_sync_ad_boost_ui()
	if _offline_elapsed_seconds > 60:
		_offline_summary.show_summary(
			_offline_elapsed_seconds,
			_offline_slime_gained,
			_offline_potions_brewed,
			_offline_potions_sold,
			_offline_gold_earned
		)

	# Start on Brew tab
	_show_tab(TAB_BREW)
	_refresh_gold_views()

	# First-run onboarding — show if no save exists OR no upgrades purchased yet
	var is_fresh_run: bool = not FileAccess.file_exists(IDLE_SAVE_PATH) or \
		(UpgradeManager.get_level("sell_value_1") == 0 and _shop.get_gold() < 10)
	if _onboarding.should_show() or is_fresh_run:
		_onboarding.start()


func _process(_delta: float) -> void:
	if _ad_boost_stacks <= 0:
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	if now_unix >= _ad_boost_expires_unix:
		_ad_boost_stacks = 0
		_update_manager_timer_rates()
	_sync_ad_boost_ui()


func _on_tab_selected(index: int) -> void:
	_show_tab(index)


func _show_tab(index: int) -> void:
	# If leaving Brew tab mid-brew, abort cleanly
	if _active_tab == TAB_BREW and index != TAB_BREW:
		_cauldron.abort_brew()

	_active_tab = index
	Main.current_tab = index

	# Hide all tab panels first
	_cauldron.visible = false
	_scroll.visible = false
	_brew_hud.visible = false
	_shop.visible = false
	_upgrades.visible = false
	_prestige.visible = false
	_slime_harvest.visible = false

	match index:
		TAB_GATHER:
			_slime_harvest.open_harvest()
		TAB_BREW:
			_cauldron.visible = true
		TAB_SHOP:
			_shop.visible = true
		TAB_UPGRADES:
			_upgrades.visible = true
		TAB_PRESTIGE:
			_prestige.visible = true
		_:
			_cauldron.visible = true


func consume_slime_for_brew_attempt() -> bool:
	if _slime < SLIME_PER_BREW:
		return false
	_slime -= SLIME_PER_BREW
	_update_gather_status()
	return true


func _on_potion_completed() -> void:
	var add_count := 1 + int(UpgradeManager.get_value("brew_yield"))

	# First brew bonus: double output once per app session if unlocked
	if not _first_brew_done and UpgradeManager.get_level("brew_morning") > 0:
		add_count *= 2
	_first_brew_done = true

	_shop.add_potions(add_count)


func _on_potion_sold_prestige_bonus(gold_earned: int) -> void:
	if _prestige.get_prestige_level() <= 0:
		return
	var mult: float = _get_prestige_gold_multiplier()
	var bonus: int = int(float(gold_earned) * (mult - 1.0))
	if bonus <= 0:
		return
	_shop.set_gold_amount(_shop.get_gold() + bonus)


func _on_gold_changed(new_total: int) -> void:
	_shop.gold = new_total
	_refresh_gold_views()
	_prestige.set_gold(new_total)


func _on_gold_spent(amount: int) -> void:
	_shop.gold = max(0, _shop.gold - amount)
	_refresh_gold_views()
	_prestige.set_gold(_shop.gold)


func _refresh_gold_views() -> void:
	_upgrades.refresh_gold(_shop.gold)
	_upgrades.refresh_prestige(_prestige.get_prestige_level())


func _get_prestige_gold_multiplier() -> float:
	## Free +10% gold per prestige level, stacks with prestige_gold upgrade.
	var base_bonus: float = float(_prestige.get_prestige_level()) * 0.10
	var upgrade_bonus: float = float(_prestige.get_prestige_level()) * UpgradeManager.get_value("prestige_gold")
	return 1.0 + base_bonus + upgrade_bonus


func _setup_manager_timers() -> void:
	_ratfolk_timer = Timer.new()
	_ratfolk_timer.one_shot = false
	_ratfolk_timer.wait_time = RATFOLK_SELL_INTERVAL
	add_child(_ratfolk_timer)
	_ratfolk_timer.timeout.connect(_on_ratfolk_tick)
	_ratfolk_timer.start()

	_orc_timer = Timer.new()
	_orc_timer.one_shot = false
	_orc_timer.wait_time = ORC_HARVEST_INTERVAL
	add_child(_orc_timer)
	_orc_timer.timeout.connect(_on_orc_tick)
	_orc_timer.start()
	_update_manager_timer_rates()


func _on_upgrade_purchased(_id: String) -> void:
	_update_manager_timer_rates()


func _sync_ad_boost_ui() -> void:
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _ad_boost_expires_unix <= now_unix:
		_ad_boost_stacks = 0
	_upgrades.set_ad_boost_state(_ad_boost_stacks, _ad_boost_expires_unix)


func _on_ad_boost_requested() -> void:
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _ad_boost_expires_unix <= now_unix:
		_ad_boost_stacks = 0
		_ad_boost_expires_unix = 0
	if _ad_boost_stacks >= 2:
		_sync_ad_boost_ui()
		return
	AdMobBridge.show_rewarded_ad(_on_ad_reward_result)


func _on_ad_reward_result(success: bool) -> void:
	if not success:
		return
	AudioManager.play_sfx("sfx_ad_boost")
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _ad_boost_stacks == 0:
		_ad_boost_stacks = 1
		_ad_boost_expires_unix = now_unix + AD_BOOST_DURATION_SECONDS
	else:
		_ad_boost_stacks = 2
		_ad_boost_expires_unix = max(now_unix, _ad_boost_expires_unix) + AD_BOOST_DURATION_SECONDS
	_update_manager_timer_rates()
	_sync_ad_boost_ui()


func _ad_boost_multiplier_at(unix_time: int, stacks_override: int = -1, expiry_override: int = -1) -> float:
	# No-ads IAP: permanent max boost, no timer needed
	if AdMobBridge.no_ads:
		return AD_BOOST_MULTIPLIER
	var stacks: int = _ad_boost_stacks if stacks_override < 0 else stacks_override
	var expiry: int = _ad_boost_expires_unix if expiry_override < 0 else expiry_override
	if stacks <= 0:
		return 1.0
	if unix_time >= expiry:
		return 1.0
	return AD_BOOST_MULTIPLIER


func _on_no_ads_granted() -> void:
	_ad_boost_stacks = 2
	_ad_boost_expires_unix = 0
	_update_manager_timer_rates()
	_sync_ad_boost_ui()
	_apply_banner_safe_zone()


func _on_banner_visibility_changed(is_visible: bool) -> void:
	_apply_banner_safe_zone(is_visible)


func _apply_banner_safe_zone(banner_visible: bool = false) -> void:
	## Shift game content down by banner height when banner is showing.
	## AdMob banner is an OS-level overlay; without this it covers top content.
	const BANNER_HEIGHT := 90
	var top_offset: float = float(BANNER_HEIGHT) if banner_visible else 0.0
	for child in get_children():
		if child == _bottom_nav or child == _settings or child == _settings_btn:
			continue
		if child is Control:
			(child as Control).offset_top = top_offset



func _manager_global_eff() -> float:
	var now_unix: int = int(Time.get_unix_time_from_system())
	var base_eff: float = clampf(0.35 + float(UpgradeManager.get_value("manager_offline_eff")), 0.2, 0.9)
	return clampf(base_eff * _ad_boost_multiplier_at(now_unix), 0.2, 1.5)


func _manager_orc_eff() -> float:
	return clampf(0.8 + float(UpgradeManager.get_value("manager_orc_eff")), 0.5, 1.5)


func _manager_gnome_eff() -> float:
	return clampf(0.8 + float(UpgradeManager.get_value("manager_gnome_eff")), 0.5, 1.5)


func _manager_ratfolk_eff() -> float:
	return clampf(0.8 + float(UpgradeManager.get_value("manager_rat_eff")), 0.5, 1.5)


func _effective_units(units: int, efficiency: float) -> int:
	if units <= 0:
		return 0
	var scaled: float = float(units) * efficiency
	var whole: int = int(floor(scaled))
	var frac: float = scaled - float(whole)
	if randf() < frac:
		whole += 1
	return max(0, whole)


func _update_manager_timer_rates() -> void:
	if _ratfolk_timer:
		var rat_eff: float = max(0.1, _manager_global_eff() * _manager_ratfolk_eff())
		_ratfolk_timer.wait_time = max(MIN_RATFOLK_INTERVAL, RATFOLK_SELL_INTERVAL / rat_eff)
	if _orc_timer:
		var orc_eff: float = max(0.1, _manager_global_eff() * _manager_orc_eff())
		_orc_timer.wait_time = max(MIN_ORC_INTERVAL, ORC_HARVEST_INTERVAL / orc_eff)


func _on_gnome_brewed(count: int) -> void:
	if UpgradeManager.get_level("manager_gnome") <= 0:
		return
	var brew_attempts: int = _effective_units(count, _manager_global_eff() * _manager_gnome_eff())
	if brew_attempts <= 0:
		return
	var slime_needed := brew_attempts * SLIME_PER_BREW
	if _slime < slime_needed:
		brew_attempts = _slime / SLIME_PER_BREW
	if brew_attempts <= 0:
		return
	_slime -= brew_attempts * SLIME_PER_BREW
	var add_count := brew_attempts * (1 + int(UpgradeManager.get_value("brew_yield")))
	_shop.add_potions(add_count)
	_update_gather_status()


func _on_ratfolk_tick() -> void:
	if UpgradeManager.get_level("manager_ratfolk") <= 0:
		return
	if not _shop.can_auto_sell():
		return
	var eff: float = _manager_global_eff() * _manager_ratfolk_eff()
	if _effective_units(1, eff) <= 0:
		return
	var sell_mult := 1.0 + (float(UpgradeManager.get_value("gnome_sell")) / 10.0)
	_shop.auto_sell_once(sell_mult)


func _on_orc_tick() -> void:
	if UpgradeManager.get_level("manager_orc") <= 0:
		return
	var base_gain: int = 1 + int(UpgradeManager.get_value("gather_yield"))
	var gain: int = _effective_units(base_gain, _manager_global_eff() * _manager_orc_eff())
	_slime += gain
	_update_gather_status()


func _on_slime_collected(amount: int) -> void:
	_slime += amount
	_update_gather_status()


func _on_slime_harvest_closed() -> void:
	# If gather panel has an explicit close action in the future, go back to brew.
	_show_tab(TAB_BREW)


func _update_gather_status() -> void:
	# SlimeHarvest currently owns its own labels for run status.
	# Keeping this hook for future shared top-bar status.
	pass


func _on_prestige_completed(_new_level: int) -> void:
	var carried_gold := _prestige.get_gold_carry()

	# Keep current upgrade-defined prestige/meta progress, reset run economy.
	UpgradeManager.reset_for_prestige()
	_shop.reset_for_prestige(carried_gold)
	_first_brew_done = false

	_refresh_gold_views()
	_prestige.set_gold(_shop.gold)



func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE, \
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save_idle_state()


func _build_state_signature() -> String:
	var entries: Array[String] = []
	for def in UpgradeManager.get_all():
		var id: String = str(def.get("id", ""))
		var lvl: int = UpgradeManager.get_level(id)
		if lvl > 0:
			entries.append("%s:%d" % [id, lvl])
	entries.sort()
	return "p%d|%s" % [_prestige.get_prestige_level(), "|".join(entries)]


func _estimate_offline_potion_demand(elapsed_eff_seconds: float) -> int:
	if elapsed_eff_seconds <= 0.0:
		return 0
	var spawn_mult: float = UpgradeManager.get_value("sell_spawn")
	var spawn_interval: float = max(1.5, _shop.base_spawn_interval * spawn_mult)
	var arrivals: float = elapsed_eff_seconds / spawn_interval
	var max_customers: int = _shop.base_max_customers + int(UpgradeManager.get_value("sell_capacity"))
	var patience: float = max(5.0, _shop.base_customer_patience + UpgradeManager.get_value("sell_patience"))
	var capacity_customers: float = elapsed_eff_seconds * (float(max_customers) / patience)
	var served_customers: float = min(arrivals, capacity_customers)
	var avg_request: float = 1.8
	return max(0, int(floor(served_customers * avg_request)))


func _save_idle_state() -> void:
	var now_unix: int = int(Time.get_unix_time_from_system())
	var payload := {
		"version": 2,
		"last_seen": int(now_unix),
		"gold": _shop.get_gold(),
		"slime": _slime,
		"stock": _shop.get_stock(),
		"ad_stacks": _ad_boost_stacks,
		"ad_expires": _ad_boost_expires_unix,
		"state_sig": _build_state_signature(),
	}
	var f := FileAccess.open(IDLE_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
		f.close()


func _apply_offline_idle_progress() -> void:
	if not FileAccess.file_exists(IDLE_SAVE_PATH):
		return
	var f := FileAccess.open(IDLE_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var d := parsed as Dictionary
	var saved_ad_stacks: int = int(d.get("ad_stacks", 0))
	var saved_ad_expires: int = int(d.get("ad_expires", 0))
	_ad_boost_stacks = saved_ad_stacks
	_ad_boost_expires_unix = saved_ad_expires
	var last_seen: int = int(d.get("last_seen", 0))
	if last_seen <= 0:
		return
	var now_unix: int = int(Time.get_unix_time_from_system())
	var elapsed: int = int(clamp(now_unix - last_seen, 0, OFFLINE_CAP_SECONDS))
	if elapsed <= 0:
		return

	# Always restore core resources — gold, slime, stock are saved every close
	var saved_gold: int = int(d.get("gold", 0))
	var saved_slime: int = int(d.get("slime", 0))
	var saved_stock: int = int(d.get("stock", 0))
	_slime = saved_slime
	if saved_stock > 0:
		_shop.add_potions(saved_stock)
	if saved_gold > 0:
		_shop.set_gold_amount(saved_gold)

	var has_gnome: bool = UpgradeManager.get_level("manager_gnome") > 0
	var has_orc: bool = UpgradeManager.get_level("manager_orc") > 0
	var has_ratfolk: bool = UpgradeManager.get_level("manager_ratfolk") > 0
	if not has_gnome and not has_orc and not has_ratfolk:
		_refresh_gold_views()
		_prestige.set_gold(_shop.get_gold())
		return

	var base_global_eff: float = clampf(0.35 + float(UpgradeManager.get_value("manager_offline_eff")), 0.2, 0.9)
	var boosted_seconds: int = 0
	if saved_ad_stacks > 0 and saved_ad_expires > last_seen:
		var boost_end: int = min(now_unix, saved_ad_expires)
		boosted_seconds = max(0, boost_end - last_seen)
	boosted_seconds = min(boosted_seconds, elapsed)
	var normal_seconds: int = max(0, elapsed - boosted_seconds)
	var boosted_global_eff: float = clampf(base_global_eff * _ad_boost_multiplier_at(last_seen, saved_ad_stacks, saved_ad_expires), 0.2, 1.5)

	_offline_elapsed_seconds = elapsed
	_offline_slime_gained = 0
	_offline_potions_brewed = 0
	_offline_potions_sold = 0
	_offline_gold_earned = 0

	# Orcs gather slime while offline.
	if has_orc:
		var orc_role_eff: float = _manager_orc_eff()
		var orc_elapsed_eff: float = float(normal_seconds) * (base_global_eff * orc_role_eff)
		orc_elapsed_eff += float(boosted_seconds) * (boosted_global_eff * orc_role_eff)
		var orc_cycles: int = int(floor(orc_elapsed_eff / ORC_HARVEST_INTERVAL))
		var orc_gain: int = orc_cycles * (1 + int(UpgradeManager.get_value("gather_yield")))
		_slime += orc_gain
		_offline_slime_gained += orc_gain

	# Gnomes brew using available slime while offline.
	if has_gnome:
		var gnome_role_eff: float = _manager_gnome_eff()
		var gnome_elapsed_eff: float = float(normal_seconds) * (base_global_eff * gnome_role_eff)
		gnome_elapsed_eff += float(boosted_seconds) * (boosted_global_eff * gnome_role_eff)
		var gnome_cycle_time: float = max(5.0, 20.0 * float(UpgradeManager.get_value("gnome_speed")))
		var gnome_count: int = max(1, int(UpgradeManager.get_value("gnome_slots")))
		var gnome_cycles: int = int(floor(gnome_elapsed_eff / gnome_cycle_time)) * gnome_count
		var brew_attempts: int = min(gnome_cycles, _slime / SLIME_PER_BREW)
		if brew_attempts > 0:
			_slime -= brew_attempts * SLIME_PER_BREW
			var potions: int = brew_attempts * (1 + int(UpgradeManager.get_value("brew_yield")) + int(UpgradeManager.get_value("gnome_brew")))
			_shop.add_potions(potions)
			_offline_potions_brewed += potions

	# Ratfolk sell potions while offline (capped by simulated customer demand).
	if has_ratfolk:
		var rat_role_eff: float = _manager_ratfolk_eff()
		var rat_elapsed_eff: float = float(normal_seconds) * (base_global_eff * rat_role_eff)
		rat_elapsed_eff += float(boosted_seconds) * (boosted_global_eff * rat_role_eff)
		var rat_cycles: int = int(floor(rat_elapsed_eff / RATFOLK_SELL_INTERVAL))
		var demand_units: int = _estimate_offline_potion_demand(rat_elapsed_eff)
		var sold: int = min(rat_cycles, min(demand_units, _shop.get_stock()))
		if sold > 0:
			var sell_mult: float = 1.0 + (float(UpgradeManager.get_value("gnome_sell")) / 10.0)
			var earned: int = int(float(_shop.get_unit_sale_value() * sold) * sell_mult)
			_shop.set_gold_amount(_shop.get_gold() + earned)
			_shop.add_potions(-sold)
			_offline_potions_sold += sold
			_offline_gold_earned += earned

	_refresh_gold_views()
	_prestige.set_gold(_shop.get_gold())
	_update_manager_timer_rates()
	_sync_ad_boost_ui()
