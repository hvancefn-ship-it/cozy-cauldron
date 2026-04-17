extends Node
## AdMob bridge — wraps the GodotAdMob plugin (or stubs it in editor/web builds).
## Handles: banner ads, rewarded ads, and the no-ads IAP flag.

signal rewarded_ad_completed()
signal rewarded_ad_failed()
signal no_ads_purchased()
signal no_ads_restored()
signal banner_visibility_changed(visible: bool)

# ── Ad Unit IDs ────────────────────────────────────────────────────────────
const REWARDED_AD_UNIT_ID_ANDROID := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace
const REWARDED_AD_UNIT_ID_IOS     := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace
const BANNER_AD_UNIT_ID_ANDROID   := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace
const BANNER_AD_UNIT_ID_IOS       := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace

# Test IDs (Google official test units)
const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS     := "ca-app-pub-3940256099942544/1712485313"
const TEST_BANNER_ANDROID   := "ca-app-pub-3940256099942544/6300978111"
const TEST_BANNER_IOS       := "ca-app-pub-3940256099942544/2934735716"

const SETTINGS_PATH := "user://settings.json"
const BANNER_ON_SECONDS  := 45.0
const BANNER_OFF_SECONDS := 90.0

var _admob: Node = null
var _ad_loaded: bool = false
var _banner_showing: bool = false
var _banner_cycle_timer: Timer = null
var _pending_callback: Callable = Callable()
var _use_test_ads: bool = true  # ← flip to false before release

## Set to true via IAP purchase or restore. Persisted in settings.json.
var no_ads: bool = false


func _ready() -> void:
	_load_no_ads()
	_try_init_admob()
	if not no_ads:
		_start_banner_cycle()


func _try_init_admob() -> void:
	if not Engine.has_singleton("AdMob"):
		push_warning("AdMobBridge: AdMob singleton not found — stub mode.")
		return
	_admob = Engine.get_singleton("AdMob")
	if _admob == null:
		return

	# Rewarded signals
	_admob.rewarded_ad_loaded.connect(_on_rewarded_loaded)
	_admob.rewarded_ad_failed_to_load.connect(_on_rewarded_failed_to_load)
	_admob.rewarded_ad_watched.connect(_on_rewarded_watched)
	_admob.rewarded_ad_failed_to_show.connect(_on_rewarded_failed_to_show)

	# Banner signals (optional — plugin may not emit these)
	if _admob.has_signal("banner_ad_loaded"):
		_admob.banner_ad_loaded.connect(_on_banner_loaded)
	if _admob.has_signal("banner_ad_failed_to_load"):
		_admob.banner_ad_failed_to_load.connect(_on_banner_failed)

	_load_rewarded_ad()


# ── Banner cycle ────────────────────────────────────────────────────────────

func _start_banner_cycle() -> void:
	if no_ads:
		return
	if _banner_cycle_timer != null:
		return
	_banner_cycle_timer = Timer.new()
	_banner_cycle_timer.one_shot = true
	add_child(_banner_cycle_timer)
	_banner_cycle_timer.timeout.connect(_on_banner_cycle_tick)
	# Start with the banner hidden — first show after OFF_SECONDS
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
	if _admob == null:
		# Stub — notify Main so it can adjust layout
		_banner_showing = true
		banner_visibility_changed.emit(true)
		return
	_admob.load_banner_ad(
		_get_banner_id(),
		_admob.BANNER_SIZE_SMART,
		_admob.BANNER_POSITION_TOP
	)
	_banner_showing = true
	banner_visibility_changed.emit(true)


func _hide_banner_internal() -> void:
	if not _banner_showing:
		return
	if _admob != null:
		if _admob.has_method("hide_banner_ad"):
			_admob.hide_banner_ad()
		elif _admob.has_method("destroy_banner_ad"):
			_admob.destroy_banner_ad()
	_banner_showing = false
	banner_visibility_changed.emit(false)


## Called when no-ads is granted — stops the cycle and hides immediately.
func hide_banner() -> void:
	_stop_banner_cycle()
	_hide_banner_internal()


func _on_banner_loaded() -> void:
	pass  # Banner auto-shows after load plugin-side


func _on_banner_failed(_error: Dictionary) -> void:
	_banner_showing = false
	banner_visibility_changed.emit(false)


# ── Rewarded ────────────────────────────────────────────────────────────────

func _load_rewarded_ad() -> void:
	if _admob == null:
		return
	_ad_loaded = false
	_admob.load_rewarded_ad(_get_rewarded_id())


func _on_rewarded_loaded() -> void:
	_ad_loaded = true


func _on_rewarded_failed_to_load(_error: Dictionary) -> void:
	_ad_loaded = false


func _on_rewarded_watched(_reward: Dictionary) -> void:
	_ad_loaded = false
	_load_rewarded_ad()
	rewarded_ad_completed.emit()
	if _pending_callback.is_valid():
		_pending_callback.call(true)
	_pending_callback = Callable()


func _on_rewarded_failed_to_show(_error: Dictionary) -> void:
	rewarded_ad_failed.emit()
	if _pending_callback.is_valid():
		_pending_callback.call(false)
	_pending_callback = Callable()


## Show a rewarded ad. callback(success: bool) fires on completion or failure.
func show_rewarded_ad(callback: Callable) -> void:
	_pending_callback = callback
	if _admob == null:
		push_warning("AdMobBridge: stub mode — simulating rewarded ad.")
		await get_tree().create_timer(0.5).timeout
		rewarded_ad_completed.emit()
		if _pending_callback.is_valid():
			_pending_callback.call(true)
		_pending_callback = Callable()
		return
	if not _ad_loaded:
		push_warning("AdMobBridge: ad not loaded yet.")
		_load_rewarded_ad()
		callback.call(false)
		_pending_callback = Callable()
		return
	_admob.show_rewarded_ad()


func is_rewarded_ready() -> bool:
	return _admob == null or _ad_loaded


# ── No-Ads IAP ──────────────────────────────────────────────────────────────

## Called by IAPBridge when purchase completes or is restored.
func grant_no_ads() -> void:
	no_ads = true
	_save_no_ads()
	hide_banner()
	no_ads_purchased.emit()


## Called by IAPBridge on restore.
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


# ── Helpers ─────────────────────────────────────────────────────────────────

func _get_rewarded_id() -> String:
	if _use_test_ads:
		return TEST_REWARDED_IOS if OS.get_name() == "iOS" else TEST_REWARDED_ANDROID
	return REWARDED_AD_UNIT_ID_IOS if OS.get_name() == "iOS" else REWARDED_AD_UNIT_ID_ANDROID


func _get_banner_id() -> String:
	if _use_test_ads:
		return TEST_BANNER_IOS if OS.get_name() == "iOS" else TEST_BANNER_ANDROID
	return BANNER_AD_UNIT_ID_IOS if OS.get_name() == "iOS" else BANNER_AD_UNIT_ID_ANDROID
