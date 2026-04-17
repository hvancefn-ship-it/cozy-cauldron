extends Node

## HapticsManager — autoload singleton
## Wraps Input.vibrate_handheld with haptics/platform guards.
## Silently no-ops on desktop or when haptics are disabled.


func _is_mobile() -> bool:
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS"


func _can_vibrate() -> bool:
	return _is_mobile() and AudioManager.is_haptics_enabled()


func vibrate_light() -> void:
	if _can_vibrate():
		Input.vibrate_handheld(40)


func vibrate_medium() -> void:
	if _can_vibrate():
		Input.vibrate_handheld(80)


func vibrate_heavy() -> void:
	if _can_vibrate():
		Input.vibrate_handheld(150)
