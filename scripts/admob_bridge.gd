extends Node
## AdMob bridge — wraps the Poing Studios GodotAdMob v4 plugin.
## Classes like MobileAds/AdView only exist at runtime on Android.
## All AdMob class references are made via ClassDB/call() to avoid editor parse errors.

signal rewarded_ad_completed()
signal rewarded_ad_failed()
signal no_ads_purchased()
signal no_ads_restored()
signal banner_visibility_changed(visible: bool)

# ── Ad Unit IDs ────────────────────────────────────────────────────────────
const APP_ID_ANDROID              := "ca-app-pub-7490319266490177~4523185667"
const REWARDED_AD_UNIT_ID_ANDROID := "ca-app-pub-7490319266490177/5031511614"
const REWARDED_AD_UNIT_ID_IOS     := "ca-app-pub-7490319266490177/5031511614"
const BANNER_AD_UNIT_ID_ANDROID   := "ca-app-pub-7490319266490177/6834501694"
const BANNER_AD_UNIT_ID_IOS       := "ca-app-pub-7490319266490177/6834501694"

const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS     := "ca-app-pub-3940256099942544/1712485313"
const TEST_BANNER_ANDROID   := "ca-app-pub-3940256099942544/6300978111"
const TEST_BANNER_IOS       := "ca-app-pub-3940256099942544/2934735716"

const SETTINGS_PATH      := "user://settings.json"
const BANNER_ON_SECONDS  := 45.0
const BANNER_OFF_SECONDS := 90.0

var _is_mobile: bool = false
var _initialized: bool = false
var _banner_showing: bool = false
var _banner_cycle_timer: Timer = null
var _ad_view: Object = null
var _rewarded_ad: Object = null
var _pending_reward_callback: Callable = Callable()
var _use_test_ads: bool = false

## Persisted — true when no-ads IAP purchased.
var no_ads: bool = false


func _ready() -> void:
	_load_no_ads()
	_is_mobile = OS.get_name() in ["Android", "iOS"]
	if not _is_mobile:
		push_warning("AdMobBridge: not on mobile — stub mode.")
		if not no_ads:
			_start_banner_cycle()
		return
	if not ClassDB.class_exists("MobileAds"):
		push_warning("AdMobBridge: MobileAds not found — plugin not active on this build.")
		return
	ClassDB.instantiate("MobileAds")  # triggers initialize via the singleton
	if ClassDB.class_exists("MobileAds"):
		var ma := Engine.get_singleton("MobileAds") if Engine.has_singleton("MobileAds") else null
		if ma:
			ma.initialize()
	_initialized = true
	_load_rewarded_ad()
	if not no_ads:
		_start_banner_cycle()


# ── Banner cycle ─────────────────────────────────────────────────────────────

func _start_banner_cycle() -> void:
	if no_ads or _banner_cycle_timer != null:
		return
	_banner_cycle_timer = Timer.new()
	_banner_cycle_timer.one_shot = true
	add_child(_banner_cycle_timer)
	_banner_cycle_timer.timeout.connect(_on_banner_cycle_tick)
	_banner_cycle_timer.start(BANNER_OFF_SECONDS)


func _stop_banner_cycle() -> void:
	if _banner_cycle_timer == null:
		return
	_banner_cycle_timer.stop()
	_banner_cycle_timer.queue_free()
	_banner_cycle_timer = null


func _on_banner_cycle_tick() -> void:
	if no_ads:
		return
	if _banner_showing:
		_hide_banner_internal()
		_banner_cycle_timer.start(BANNER_OFF_SECONDS)
	else:
		_show_banner_internal()
		_banner_cycle_timer.start(BANNER_ON_SECONDS)


func _show_banner_internal() -> void:
	if no_ads or _banner_showing:
		return
	if not _is_mobile or not _initialized:
		_banner_showing = true
		banner_visibility_changed.emit(true)
		return
	# Use string-based construction to avoid parse errors in editor
	if ClassDB.class_exists("AdView"):
		_ad_view = ClassDB.instantiate("AdView")
		_ad_view.call("initialize", _get_banner_id(), 0, 0)  # BANNER size, TOP position
		_ad_view.call("load_ad")
	_banner_showing = true
	banner_visibility_changed.emit(true)


func _hide_banner_internal() -> void:
	if not _banner_showing:
		return
	if _ad_view != null:
		if _ad_view.has_method("destroy"):
			_ad_view.destroy()
		_ad_view = null
	_banner_showing = false
	banner_visibility_changed.emit(false)


func hide_banner() -> void:
	_stop_banner_cycle()
	_hide_banner_internal()


# ── Rewarded ─────────────────────────────────────────────────────────────────

func _load_rewarded_ad() -> void:
	if not _initialized or not ClassDB.class_exists("RewardedAdLoader"):
		return
	var loader: Object = ClassDB.instantiate("RewardedAdLoader")
	var request: Object = ClassDB.instantiate("AdRequest") if ClassDB.class_exists("AdRequest") else null
	var cb: Object = ClassDB.instantiate("RewardedAdLoadCallback") if ClassDB.class_exists("RewardedAdLoadCallback") else null
	if cb:
		cb.set("on_ad_loaded", Callable(self, "_on_rewarded_loaded"))
		cb.set("on_ad_failed_to_load", Callable(self, "_on_rewarded_failed_to_load"))
	if loader and request and cb:
		loader.call("load", _get_rewarded_id(), request, cb)


func _on_rewarded_loaded(ad: Object) -> void:
	_rewarded_ad = ad


func _on_rewarded_failed_to_load(_error: Object) -> void:
	_rewarded_ad = null


func show_rewarded_ad(callback: Callable) -> void:
	_pending_reward_callback = callback
	if not _is_mobile or not _initialized:
		# Stub
		push_warning("AdMobBridge: stub mode — simulating rewarded ad.")
		await get_tree().create_timer(0.5).timeout
		rewarded_ad_completed.emit()
		if _pending_reward_callback.is_valid():
			_pending_reward_callback.call(true)
		_pending_reward_callback = Callable()
		return
	if _rewarded_ad == null:
		push_warning("AdMobBridge: rewarded ad not ready.")
		callback.call(false)
		_pending_reward_callback = Callable()
		_load_rewarded_ad()
		return
	if ClassDB.class_exists("OnUserEarnedRewardListener"):
		var reward_cb: Object = ClassDB.instantiate("OnUserEarnedRewardListener")
		reward_cb.set("on_user_earned_reward", Callable(self, "_on_reward_earned"))
		_rewarded_ad.call("show", reward_cb)
	else:
		callback.call(false)


func _on_reward_earned(_reward: Object) -> void:
	_rewarded_ad = null
	_load_rewarded_ad()
	rewarded_ad_completed.emit()
	if _pending_reward_callback.is_valid():
		_pending_reward_callback.call(true)
	_pending_reward_callback = Callable()


func is_rewarded_ready() -> bool:
	if not _is_mobile:
		return true
	return _rewarded_ad != null


# ── No-Ads IAP ───────────────────────────────────────────────────────────────

func grant_no_ads() -> void:
	no_ads = true
	_save_no_ads()
	hide_banner()
	no_ads_purchased.emit()


func restore_no_ads() -> void:
	no_ads = true
	_save_no_ads()
	hide_banner()
	no_ads_restored.emit()


func _load_no_ads() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		no_ads = bool((parsed as Dictionary).get("no_ads", false))


func _save_no_ads() -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				data = parsed as Dictionary
	data["no_ads"] = true
	var fw := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_rewarded_id() -> String:
	if _use_test_ads:
		return TEST_REWARDED_IOS if OS.get_name() == "iOS" else TEST_REWARDED_ANDROID
	return REWARDED_AD_UNIT_ID_IOS if OS.get_name() == "iOS" else REWARDED_AD_UNIT_ID_ANDROID


func _get_banner_id() -> String:
	if _use_test_ads:
		return TEST_BANNER_IOS if OS.get_name() == "iOS" else TEST_BANNER_ANDROID
	return BANNER_AD_UNIT_ID_IOS if OS.get_name() == "iOS" else BANNER_AD_UNIT_ID_ANDROID
