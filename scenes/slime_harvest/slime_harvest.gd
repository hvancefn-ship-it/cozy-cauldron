extends Control
class_name SlimeHarvest

signal slime_collected(amount: int)
signal closed()

@export var base_spawn_count: int = 14
@export var harvest_cooldown_sec: float = 20.0
@export var slime_hp_min: int = 2
@export var slime_hp_max: int = 4
@export var trail_lifetime_sec: float = 0.20

@onready var _playfield: Control = $Playfield
@onready var _status: Label = $TopBar/StatusLabel
@onready var _count: Label = $TopBar/CountLabel
@onready var _close_btn: Button = $TopBar/CloseBtn
@onready var _trail: Line2D = $TrailLine

var _active: bool = false
var _harvested_this_run: int = 0
var _cooldown_until_ms: int = 0
var _slime_nodes: Array[ColorRect] = []
var _trail_points: PackedVector2Array = PackedVector2Array()
var _trail_ages: Array[float] = []

func _ready() -> void:
	_close_btn.visible = false
	_close_btn.pressed.connect(_on_close)
	visible = false

func open_harvest() -> void:
	visible = true
	_clear_trail()
	var now_ms: int = Time.get_ticks_msec()

	# If cooldown finished while closed/opening, reset cycle now.
	if _cooldown_until_ms > 0 and now_ms >= _cooldown_until_ms:
		_reset_cycle()
		return

	if _active and not _slime_nodes.is_empty():
		_update_ui()
		return

	if now_ms < _cooldown_until_ms:
		_active = not _slime_nodes.is_empty()
		_update_ui()
		return

	if _slime_nodes.is_empty():
		_harvested_this_run = 0
		_spawn_slimes()
	_active = true
	_update_ui()

func _process(delta: float) -> void:
	if visible:
		var now_ms: int = Time.get_ticks_msec()
		if _cooldown_until_ms > 0 and now_ms >= _cooldown_until_ms:
			_reset_cycle()
		_update_ui()
		_fade_trail(delta)

func _input(event: InputEvent) -> void:
	if not visible or not _active:
		return

	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_clear_trail()
		_add_trail_point((event as InputEventScreenTouch).position)
	elif event is InputEventScreenDrag:
		var p: Vector2 = (event as InputEventScreenDrag).position
		_add_trail_point(p)
		_try_slice(p)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_clear_trail()
				_add_trail_point(mb.position)
			else:
				_clear_trail()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mp: Vector2 = (event as InputEventMouseMotion).position
		_add_trail_point(mp)
		_try_slice(mp)

func _spawn_slimes() -> void:
	_clear_slimes()
	await get_tree().process_frame
	var rect: Rect2 = _playfield.get_global_rect()
	var spawn_count: int = max(1, base_spawn_count + int(UpgradeManager.get_value("gather_spawn")))
	for _i in range(spawn_count):
		var s := ColorRect.new()
		var r: float = randf_range(18.0, 34.0)
		var hp: int = randi_range(slime_hp_min, slime_hp_max)
		s.custom_minimum_size = Vector2(r * 2.0, r * 2.0)
		s.color = Color(0.45, 0.95, 0.5, 0.95)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := randf_range(rect.position.x + r, rect.end.x - r)
		var y := randf_range(rect.position.y + r, rect.end.y - r)
		s.global_position = Vector2(x - r, y - r)
		s.set_meta("radius", r)
		s.set_meta("hp", hp)
		s.set_meta("max_hp", hp)
		_playfield.add_child(s)
		_slime_nodes.append(s)

func _try_slice(pos: Vector2) -> void:
	for s in _slime_nodes.duplicate():
		if not is_instance_valid(s):
			continue
		var r: float = float(s.get_meta("radius"))
		var center: Vector2 = s.global_position + Vector2(r, r)
		if pos.distance_to(center) <= r:
			_apply_hit(s)

func _apply_hit(s: ColorRect) -> void:
	if not is_instance_valid(s):
		return
	var hp: int = int(s.get_meta("hp")) - 1
	s.set_meta("hp", hp)

	var t := create_tween()
	t.tween_property(s, "color", Color(0.95, 1.0, 0.95, 1.0), 0.05)

	if hp <= 0:
		var gain: int = 1 + int(UpgradeManager.get_value("gather_yield"))
		_harvested_this_run += gain
		slime_collected.emit(gain)
		if _cooldown_until_ms <= 0:
			_cooldown_until_ms = Time.get_ticks_msec() + int(_get_harvest_cooldown_sec() * 1000.0)
		AudioManager.play_sfx("sfx_slime_die")
		if Main.current_tab == 0:
			HapticsManager.vibrate_light()
		t.tween_property(s, "modulate:a", 0.0, 0.08)
		t.tween_callback(func() -> void:
			if is_instance_valid(s):
				s.queue_free()
		)
		_slime_nodes.erase(s)
	else:
		AudioManager.play_sfx("sfx_slime_hit" if randi() % 2 == 0 else "sfx_slime_hit_alt")
		var max_hp: int = int(s.get_meta("max_hp"))
		var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var base_col := Color(0.45 + (1.0 - ratio) * 0.2, 0.95 - (1.0 - ratio) * 0.25, 0.5, 0.95)
		t.tween_property(s, "color", base_col, 0.08)

	if _slime_nodes.is_empty():
		_active = false


func _get_harvest_cooldown_sec() -> float:
	var mult: float = UpgradeManager.get_value("gather_cooldown")
	return max(2.0, harvest_cooldown_sec * mult)

func _reset_cycle() -> void:
	_clear_slimes()
	_harvested_this_run = 0
	_cooldown_until_ms = 0
	_spawn_slimes()
	_active = true
	_update_ui()

func _clear_slimes() -> void:
	for s in _slime_nodes:
		if is_instance_valid(s):
			s.queue_free()
	_slime_nodes.clear()

func _on_close() -> void:
	visible = false
	closed.emit()

func _update_ui() -> void:
	_count.text = "Slime: %d" % _harvested_this_run
	var ms_left: int = _cooldown_until_ms - Time.get_ticks_msec()
	if _active:
		if ms_left > 0:
			_status.text = "Harvesting... reset in %.1fs" % (float(ms_left) / 1000.0)
		else:
			_status.text = "Slice slimes to harvest!"
	else:
		if ms_left > 0:
			_status.text = "Harvest cooldown: %.1fs" % (float(ms_left) / 1000.0)
		else:
			_status.text = "Ready"

func _add_trail_point(global_pos: Vector2) -> void:
	var lp: Vector2 = global_pos - global_position
	_trail_points.append(lp)
	_trail_ages.append(0.0)
	while _trail_points.size() > 28:
		_trail_points.remove_at(0)
		_trail_ages.remove_at(0)
	_trail.points = _trail_points

func _fade_trail(delta: float) -> void:
	if _trail_points.is_empty():
		return
	for i in range(_trail_ages.size()):
		_trail_ages[i] += delta
	while not _trail_ages.is_empty() and _trail_ages[0] > trail_lifetime_sec:
		_trail_ages.remove_at(0)
		_trail_points.remove_at(0)
	_trail.points = _trail_points

func _clear_trail() -> void:
	_trail_points.clear()
	_trail_ages.clear()
	_trail.clear_points()
