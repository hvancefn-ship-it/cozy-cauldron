extends Control

## Settings panel — shown/hidden at runtime.
## Exposes open() to callers; emits closed() when dismissed.

signal closed()

@onready var sfx_slider: HSlider = %SfxSlider
@onready var haptics_off_btn: Button = %HapticsOffBtn
@onready var haptics_on_btn: Button = %HapticsOnBtn
@onready var no_ads_btn: Button = %NoAdsBtn
@onready var restore_btn: Button = %RestoreBtn
@onready var close_btn: Button = %CloseBtn


func _ready() -> void:
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	haptics_off_btn.pressed.connect(_on_haptics_off_pressed)
	haptics_on_btn.pressed.connect(_on_haptics_on_pressed)
	no_ads_btn.pressed.connect(_on_no_ads_pressed)
	restore_btn.pressed.connect(_on_restore_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	AdMobBridge.no_ads_purchased.connect(_refresh_ui)
	AdMobBridge.no_ads_restored.connect(_refresh_ui)
	_refresh_ui.call_deferred()


func open() -> void:
	visible = true
	_refresh_ui()


func _refresh_ui() -> void:
	sfx_slider.value = AudioManager.sfx_volume
	_update_haptic_buttons(AudioManager.is_haptics_enabled())
	var no_ads: bool = AdMobBridge.no_ads
	no_ads_btn.disabled = no_ads
	no_ads_btn.text = "⭐ Ads Removed — Thank You!" if no_ads else "Remove Ads — $0.99"
	restore_btn.visible = not no_ads


func _update_haptic_buttons(enabled: bool) -> void:
	# Visual toggle: highlight the active button via disabled state trick
	# (flat + disabled gives a "pressed" look without CheckButton)
	haptics_on_btn.disabled = enabled
	haptics_off_btn.disabled = not enabled


func _on_sfx_slider_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)


func _on_haptics_off_pressed() -> void:
	AudioManager.set_haptics(false)
	_update_haptic_buttons(false)


func _on_haptics_on_pressed() -> void:
	AudioManager.set_haptics(true)
	_update_haptic_buttons(true)


func _on_no_ads_pressed() -> void:
	# IAP not wired yet — button is hidden until Play Console product ID is set up.
	pass


func _on_restore_pressed() -> void:
	# IAP restore not wired yet.
	pass


func _on_close_pressed() -> void:
	visible = false
	emit_signal("closed")
