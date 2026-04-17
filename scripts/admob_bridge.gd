extends Node
## AdMob bridge — wraps the GodotAdMob plugin (or stubs it in editor/web builds).
## Usage: AdMobBridge.show_rewarded_ad(callback: Callable)
## callback(success: bool) is called when the ad completes or fails.

signal rewarded_ad_completed()
signal rewarded_ad_failed()

const REWARDED_AD_UNIT_ID_ANDROID := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace
const REWARDED_AD_UNIT_ID_IOS     := "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"  # ← replace
const TEST_AD_UNIT_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_AD_UNIT_IOS     := "ca-app-pub-3940256099942544/1712485313"

var _pending_callback: Callable = Callable()
var _admob: Node = null
var _ad_loaded: bool = false
var _use_test_ads: bool = true  # flip to false for production


func _ready() -> void:
	_try_init_admob()


func _try_init_admob() -> void:
	if not Engine.has_singleton("AdMob"):
		push_warning("AdMobBridge: AdMob singleton not found — running in stub mode.")
		return
	_admob = Engine.get_singleton("AdMob")
	if _admob == null:
		return
	_admob.rewarded_ad_loaded.connect(_on_rewarded_loaded)
	_admob.rewarded_ad_failed_to_load.connect(_on_rewarded_failed_to_load)
	_admob.rewarded_ad_watched.connect(_on_rewarded_watched)
	_admob.rewarded_ad_failed_to_show.connect(_on_rewarded_failed_to_show)
	_load_rewarded_ad()


func _get_ad_unit_id() -> String:
	if _use_test_ads:
		if OS.get_name() == "iOS":
			return TEST_AD_UNIT_IOS
		return TEST_AD_UNIT_ANDROID
	if OS.get_name() == "iOS":
		return REWARDED_AD_UNIT_ID_IOS
	return REWARDED_AD_UNIT_ID_ANDROID


func _load_rewarded_ad() -> void:
	if _admob == null:
		return
	_ad_loaded = false
	_admob.load_rewarded_ad(_get_ad_unit_id())


func _on_rewarded_loaded() -> void:
	_ad_loaded = true


func _on_rewarded_failed_to_load(_error_data: Dictionary) -> void:
	_ad_loaded = false


func _on_rewarded_watched(_reward: Dictionary) -> void:
	_ad_loaded = false
	_load_rewarded_ad()
	rewarded_ad_completed.emit()
	if _pending_callback.is_valid():
		_pending_callback.call(true)
	_pending_callback = Callable()


func _on_rewarded_failed_to_show(_error_data: Dictionary) -> void:
	rewarded_ad_failed.emit()
	if _pending_callback.is_valid():
		_pending_callback.call(false)
	_pending_callback = Callable()


## Call this to show a rewarded ad. callback(success: bool) fires when done.
func show_rewarded_ad(callback: Callable) -> void:
	_pending_callback = callback
	if _admob == null:
		# Stub: simulate ad in editor / non-mobile builds
		push_warning("AdMobBridge: stub mode — simulating rewarded ad.")
		await get_tree().create_timer(0.5).timeout
		rewarded_ad_completed.emit()
		if _pending_callback.is_valid():
			_pending_callback.call(true)
		_pending_callback = Callable()
		return
	if not _ad_loaded:
		push_warning("AdMobBridge: ad not loaded yet — trying to reload.")
		_load_rewarded_ad()
		callback.call(false)
		_pending_callback = Callable()
		return
	_admob.show_rewarded_ad()


func is_ready() -> bool:
	return _admob == null or _ad_loaded
