extends Control

## Settings panel — shown/hidden at runtime.
## Exposes open() to callers; emits closed() when dismissed.

signal closed()

@onready var sfx_slider: HSlider = %SfxSlider
@onready var haptics_off_btn: Button = %HapticsOffBtn
@onready var haptics_on_btn: Button = %HapticsOnBtn
@onready var close_btn: Button = %CloseBtn


func _ready() -> void:
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	haptics_off_btn.pressed.connect(_on_haptics_off_pressed)
	haptics_on_btn.pressed.connect(_on_haptics_on_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	# Defer so AudioManager is guaranteed ready before we read it
	_refresh_ui.call_deferred()


func open() -> void:
	visible = true
	_refresh_ui()


func _refresh_ui() -> void:
	sfx_slider.value = AudioManager.sfx_volume
	_update_haptic_buttons(AudioManager.is_haptics_enabled())


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


func _on_close_pressed() -> void:
	visible = false
	emit_signal("closed")
