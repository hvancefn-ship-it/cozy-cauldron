extends Node
## Autoload singleton. Holds all symbol templates.
## Each template's points are pre-normalized via SymbolMatcher.normalize().
## Trained templates are persisted to user://symbol_templates.json

## Global fallback threshold — used when a symbol has no per-symbol override.
@export_range(0.0, 1.0, 0.01)
var match_threshold: float = 0.60

## Per-symbol thresholds — override the global for specific symbols.
## e.g. { "fire": 0.55, "spirit": 0.70 }
var symbol_thresholds: Dictionary = {}

const SAVE_PATH := "user://symbol_templates.json"
const THRESHOLD_PATH := "user://symbol_thresholds.json"
const NEG_SAVE_PATH := "user://symbol_negative_templates.json"
const NEGATIVE_REJECT_MARGIN := 0.03

## Safety flag: easy rollback switch for shape sanity gates.
const ENABLE_SHAPE_SANITY_GATES := true

signal symbol_registered(symbol_name: String)

## Internal store: Array of { name: String, points: PackedVector2Array, trained: bool }
var _templates: Array = []
## Negative templates: Array of { name: String, points: PackedVector2Array }
var _negative_templates: Array = []


func _ready() -> void:
	_register_defaults()
	_register_default_thresholds()
	_load_trained()       # Adds on top of defaults — player's own trained strokes
	_load_negative()      # Loads trained failing examples
	_load_thresholds()    # Overrides defaults with any tuned values — yours from training


## Bake in your tuned thresholds here before shipping.
## These are the shipped defaults — override per-symbol as needed after playtesting.
func _register_default_thresholds() -> void:
	# symbol_thresholds["fire"]      = 0.55
	# symbol_thresholds["water"]     = 0.58
	# symbol_thresholds["earth"]     = 0.60
	# symbol_thresholds["spirit"]    = 0.65
	# symbol_thresholds["lightning"] = 0.58
	pass  # Remove this line and uncomment above once you've found your values


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func recognize(drawn: PackedVector2Array) -> Dictionary:
	if _templates.is_empty():
		push_warning("SymbolLibrary: no templates registered!")
		return {"name": "", "score": 0.0}

	var result := SymbolMatcher.recognize(drawn, _templates)
	var threshold := get_threshold(result.name)

	if result.score < threshold:
		return {"name": "", "score": result.score}

	# Negative training gate: if this stroke also strongly matches saved FAIL examples
	# for the same symbol, reject it.
	var neg_templates := _negative_templates.filter(func(t: Dictionary) -> bool:
		return t.name == result.name
	)
	if not neg_templates.is_empty():
		var neg_result := SymbolMatcher.recognize(drawn, neg_templates)
		if neg_result.score >= (result.score - NEGATIVE_REJECT_MARGIN):
			return {"name": "", "score": result.score}

	return result

## Targeted recognition for gameplay: evaluate ONLY the expected symbol.
## Returns { name: target_symbol or "", score: float }.
func recognize_for_symbol(drawn: PackedVector2Array, target_symbol: String) -> Dictionary:
	var target_templates := _templates.filter(func(t: Dictionary) -> bool:
		return t.name == target_symbol
	)
	if target_templates.is_empty():
		return {"name": "", "score": 0.0}

	var result := SymbolMatcher.recognize(drawn, target_templates)
	var threshold := get_threshold(target_symbol)

	if result.score < threshold:
		return {"name": "", "score": result.score}

	var neg_templates := _negative_templates.filter(func(t: Dictionary) -> bool:
		return t.name == target_symbol
	)
	if not neg_templates.is_empty():
		var neg_result := SymbolMatcher.recognize(drawn, neg_templates)
		if neg_result.score >= (result.score - NEGATIVE_REJECT_MARGIN):
			return {"name": "", "score": result.score}

	return {"name": target_symbol, "score": result.score}


## Get the effective threshold for a symbol — per-symbol if set, else global.
func get_threshold(symbol_name: String) -> float:
	if symbol_thresholds.has(symbol_name):
		return float(symbol_thresholds[symbol_name])
	return match_threshold


## Set a per-symbol threshold and persist it.
func set_threshold(symbol_name: String, value: float) -> void:
	symbol_thresholds[symbol_name] = value
	_save_thresholds()


## Remove per-symbol threshold override (falls back to global).
func clear_threshold(symbol_name: String) -> void:
	symbol_thresholds.erase(symbol_name)
	_save_thresholds()


## Register a trained symbol from raw points and persist it to disk.
func register_symbol(symbol_name: String, raw_points: PackedVector2Array) -> void:
	var normalized := SymbolMatcher.normalize(raw_points)
	_templates.append({"name": symbol_name, "points": normalized, "trained": true})
	symbol_registered.emit(symbol_name)
	_save_trained()

## Register a negative (failing) example for a symbol.
func register_negative_symbol(symbol_name: String, raw_points: PackedVector2Array) -> void:
	var normalized := SymbolMatcher.normalize(raw_points)
	_negative_templates.append({"name": symbol_name, "points": normalized})
	_save_negative()


## Remove all trained (user-saved) templates for a given symbol name.
func clear_trained(symbol_name: String) -> void:
	_templates = _templates.filter(func(t: Dictionary) -> bool:
		return not (t.get("trained", false) and t.name == symbol_name)
	)
	_save_trained()

func clear_negative_trained(symbol_name: String) -> void:
	_negative_templates = _negative_templates.filter(func(t: Dictionary) -> bool:
		return t.name != symbol_name
	)
	_save_negative()


## Remove ALL trained templates across all symbols.
func clear_all_trained() -> void:
	_templates = _templates.filter(func(t: Dictionary) -> bool:
		return not t.get("trained", false)
	)
	_save_trained()
	_negative_templates.clear()
	_save_negative()


## Return how many trained templates exist for a symbol.
func trained_count(symbol_name: String) -> int:
	var count := 0
	for t in _templates:
		if t.get("trained", false) and t.name == symbol_name:
			count += 1
	return count

func negative_trained_count(symbol_name: String) -> int:
	var count := 0
	for t in _negative_templates:
		if t.name == symbol_name:
			count += 1
	return count


func get_symbol_names() -> Array[String]:
	## Return only unique names (templates may have duplicates for multi-direction support)
	var seen: Dictionary = {}
	var names: Array[String] = []
	for t in _templates:
		if not seen.has(t.name):
			seen[t.name] = true
			names.append(t.name)
	return names


func get_template_points(symbol_name: String) -> PackedVector2Array:
	## Return the first matching template (used for ghost display)
	for t in _templates:
		if t.name == symbol_name:
			return t.points
	return PackedVector2Array()


# ---------------------------------------------------------------------------
# Default symbol definitions
# ---------------------------------------------------------------------------
## Rules:
## - Use 20+ points tracing the actual shape so resampling is accurate
## - Register multiple variations (CW + CCW, different start corners) for closed shapes
## - Keep shapes visually distinct from each other

func _register_defaults() -> void:

	# --- FIRE: W-shaped zigzag, drawn left→right ---
	_register_raw("fire", _zigzag(Vector2(50,200), Vector2(350,200), 4, 120.0))

	# --- WATER: gentle S-curve left→right ---
	_register_raw("water", _scurve())

	# --- EARTH: square, clockwise from top-left ---
	_register_raw("earth", _rect_points(Vector2(80,80), Vector2(320,320), true))
	# Also register counter-clockwise so either direction works
	_register_raw("earth", _rect_points(Vector2(80,80), Vector2(320,320), false))

	# --- SPIRIT: circle, clockwise ---
	_register_raw("spirit", _circle_points(Vector2(200,200), 120.0, true))
	# Also register counter-clockwise
	_register_raw("spirit", _circle_points(Vector2(200,200), 120.0, false))

	# --- LIGHTNING: sharp Z-bolt, top-right to bottom-left ---
	_register_raw("lightning", _lightning_points())


# ---------------------------------------------------------------------------
# Shape generators — return Array of Vector2
# ---------------------------------------------------------------------------

## Zigzag: n peaks between start and end, amplitude = peak height
func _zigzag(from: Vector2, to: Vector2, peaks: int, amplitude: float) -> Array:
	var pts: Array = []
	var steps := peaks * 2 + 1
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := from.x + (to.x - from.x) * t
		var y := from.y + (amplitude if i % 2 == 1 else 0.0) * -1.0
		pts.append(Vector2(x, y))
	return pts


## S-curve from left to right
func _scurve() -> Array:
	var pts: Array = []
	var steps := 24
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := 60.0 + t * 280.0
		# Two-phase sine: first half curves down, second half curves up
		var y := 200.0 + sin(t * PI * 2.0) * 100.0
		pts.append(Vector2(x, y))
	return pts


## Rectangle traced with many intermediate points, CW or CCW
func _rect_points(tl: Vector2, br: Vector2, clockwise: bool) -> Array:
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	var corners: Array
	if clockwise:
		corners = [tl, tr, br, bl, tl]
	else:
		corners = [tl, bl, br, tr, tl]
	return _densify(corners, 8)  # 8 points per side


## Circle with many points, CW or CCW
func _circle_points(center: Vector2, radius: float, clockwise: bool) -> Array:
	var pts: Array = []
	var steps := 32
	var dir := 1.0 if clockwise else -1.0
	for i in range(steps + 1):
		var angle := dir * float(i) / float(steps) * TAU - PI / 2.0
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts


## Lightning bolt: Z shape — top-left across, diagonal down-left, across right
func _lightning_points() -> Array:
	var raw: Array = [
		Vector2(100, 80),  Vector2(300, 80),   # top bar left→right
		Vector2(100, 220), Vector2(100, 220),  # diagonal to mid-left
		Vector2(300, 360),                      # across to bottom-right
	]
	return _densify(raw, 10)


## Insert intermediate points between each pair so resampling is accurate
func _densify(pts: Array, steps_per_segment: int) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for s in range(steps_per_segment):
			var t := float(s) / float(steps_per_segment)
			out.append(a.lerp(b, t))
	out.append(pts[-1])
	return out


func _register_raw(symbol_name: String, pts: Array) -> void:
	var packed := PackedVector2Array()
	for p in pts:
		packed.append(p)
	var normalized := SymbolMatcher.normalize(packed)
	_templates.append({"name": symbol_name, "points": normalized, "trained": false})


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save_trained() -> void:
	var trained_only: Array = []
	for t in _templates:
		if not t.get("trained", false):
			continue
		# Serialize PackedVector2Array → Array of {x, y}
		var pts_json: Array = []
		for p: Vector2 in t.points:
			pts_json.append({"x": p.x, "y": p.y})
		trained_only.append({"name": t.name, "points": pts_json})

	var json_string := JSON.stringify(trained_only, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SymbolLibrary: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(json_string)
	file.close()


func _save_thresholds() -> void:
	var file := FileAccess.open(THRESHOLD_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SymbolLibrary: could not write thresholds")
		return
	file.store_string(JSON.stringify(symbol_thresholds, "\t"))
	file.close()


func _save_negative() -> void:
	var payload: Array = []
	for t in _negative_templates:
		var pts_json: Array = []
		for p: Vector2 in t.points:
			pts_json.append({"x": p.x, "y": p.y})
		payload.append({"name": t.name, "points": pts_json})

	var file := FileAccess.open(NEG_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SymbolLibrary: could not open %s for writing" % NEG_SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _load_thresholds() -> void:
	if not FileAccess.file_exists(THRESHOLD_PATH):
		return
	var file := FileAccess.open(THRESHOLD_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		symbol_thresholds = parsed as Dictionary
		print("SymbolLibrary: loaded thresholds — ", symbol_thresholds)


func _load_trained() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SymbolLibrary: could not open %s for reading" % SAVE_PATH)
		return
	var raw := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Array:
		push_error("SymbolLibrary: corrupt save file — clearing")
		return

	var count := 0
	for entry: Variant in parsed as Array:
		if not entry is Dictionary:
			continue
		var d := entry as Dictionary
		if not d.has("name") or not d.has("points"):
			continue
		var packed := PackedVector2Array()
		for pt: Variant in d.points as Array:
			if pt is Dictionary:
				packed.append(Vector2((pt as Dictionary).x, (pt as Dictionary).y))
		if packed.size() > 0:
			_templates.append({"name": d.name, "points": packed, "trained": true})
			count += 1

	if count > 0:
		print("SymbolLibrary: loaded %d trained templates from disk" % count)


func _load_negative() -> void:
	if not FileAccess.file_exists(NEG_SAVE_PATH):
		return

	var file := FileAccess.open(NEG_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		return

	var count := 0
	for entry: Variant in parsed as Array:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		if not d.has("name") or not d.has("points"):
			continue
		var packed := PackedVector2Array()
		for pt in d.points:
			if pt is Dictionary:
				packed.append(Vector2((pt as Dictionary).x, (pt as Dictionary).y))
		if packed.size() > 0:
			_negative_templates.append({"name": d.name, "points": packed})
			count += 1
	if count > 0:
		print("SymbolLibrary: loaded %d negative templates from disk" % count)
