class_name SymbolMatcher
## $1 Unistroke Recognizer - compares a drawn path against symbol templates.
## All methods are static; no instance needed.

const NUM_POINTS := 64
const SQUARE_SIZE := 250.0
## sqrt(2 * SQUARE_SIZE^2) / 2 — used to normalize scores to 0.0-1.0
const HALF_DIAGONAL := 176.77
const ANGLE_RANGE_DEG := 45.0
const ANGLE_PRECISION_DEG := 2.0
## Golden ratio for golden-section search
const PHI := 0.618034


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Normalize raw drawn points and match against pre-normalized templates.
## templates: Array of { name: String, points: PackedVector2Array }
## Returns { name: String, score: float }  score 1.0 = perfect, 0.0 = worst.
static func recognize(drawn: PackedVector2Array, templates: Array) -> Dictionary:
	if drawn.size() < 2:
		return {"name": "", "score": 0.0}

	var pts := normalize(drawn)

	var best_dist := INF
	var best_name := ""

	for t in templates:
		var d: float = _distance_at_best_angle(
			pts, t.points,
			deg_to_rad(-ANGLE_RANGE_DEG),
			deg_to_rad(ANGLE_RANGE_DEG),
			deg_to_rad(ANGLE_PRECISION_DEG)
		)
		if d < best_dist:
			best_dist = d
			best_name = t.name

	var score := 1.0 - (best_dist / HALF_DIAGONAL)
	return {"name": best_name, "score": clampf(score, 0.0, 1.0)}


## Normalize a point path: resample → rotate to indicative angle → scale → center.
## Use this when pre-processing template definitions.
static func normalize(points: PackedVector2Array) -> PackedVector2Array:
	var pts := resample(points, NUM_POINTS)
	var angle := _indicative_angle(pts)
	pts = _rotate_by(pts, -angle)
	pts = _scale_to_square(pts, SQUARE_SIZE)
	pts = _translate_to_origin(pts)
	return pts


## Convert pre-normalized template points into screen-space display points.
## center: where to draw on screen, display_size: pixel size of the bounding box.
static func get_display_points(
	template_pts: PackedVector2Array,
	center: Vector2,
	display_size: float
) -> PackedVector2Array:
	var scale := display_size / SQUARE_SIZE
	var result := PackedVector2Array()
	for p in template_pts:
		result.append(center + p * scale)
	return result


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var total := _path_length(points)
	if total == 0.0 or points.size() < 2:
		var r := PackedVector2Array()
		for _i in range(n):
			r.append(points[0] if points.size() > 0 else Vector2.ZERO)
		return r

	var interval := total / float(n - 1)
	var result := PackedVector2Array()
	result.append(points[0])

	var accumulated := 0.0
	var prev := points[0]
	var i := 1

	while i < points.size() and result.size() < n:
		var curr := points[i]
		var d := prev.distance_to(curr)

		if accumulated + d >= interval:
			var t := (interval - accumulated) / d
			var new_pt := prev.lerp(curr, t)
			result.append(new_pt)
			prev = new_pt
			accumulated = 0.0
			# Don't advance i — might squeeze more points from this segment
		else:
			accumulated += d
			prev = curr
			i += 1

	# Pad with last point if floating-point caused us to fall short
	while result.size() < n:
		result.append(points[-1])

	return result


static func _path_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for j in range(1, points.size()):
		length += points[j - 1].distance_to(points[j])
	return length


static func _indicative_angle(points: PackedVector2Array) -> float:
	var c := _centroid(points)
	return atan2(c.y - points[0].y, c.x - points[0].x)


static func _centroid(points: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in points:
		c += p
	return c / float(points.size())


static func _rotate_by(points: PackedVector2Array, radians: float) -> PackedVector2Array:
	var c := _centroid(points)
	var cos_r := cos(radians)
	var sin_r := sin(radians)
	var result := PackedVector2Array()
	for p in points:
		var dx := p.x - c.x
		var dy := p.y - c.y
		result.append(Vector2(
			dx * cos_r - dy * sin_r + c.x,
			dx * sin_r + dy * cos_r + c.y
		))
	return result


static func _scale_to_square(points: PackedVector2Array, size: float) -> PackedVector2Array:
	var min_x := INF; var max_x := -INF
	var min_y := INF; var max_y := -INF
	for p in points:
		min_x = min(min_x, p.x); max_x = max(max_x, p.x)
		min_y = min(min_y, p.y); max_y = max(max_y, p.y)
	var w: float = max(max_x - min_x, 1.0)
	var h: float = max(max_y - min_y, 1.0)
	var result := PackedVector2Array()
	for p in points:
		result.append(Vector2(p.x * (size / w), p.y * (size / h)))
	return result


static func _translate_to_origin(points: PackedVector2Array) -> PackedVector2Array:
	var c := _centroid(points)
	var result := PackedVector2Array()
	for p in points:
		result.append(Vector2(p.x - c.x, p.y - c.y))
	return result


static func _path_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var d := 0.0
	var n: int = min(a.size(), b.size())
	for j in range(n):
		d += a[j].distance_to(b[j])
	return d / float(n)


## Golden-section search for the best rotation angle between a and b.
static func _distance_at_best_angle(
	pts: PackedVector2Array,
	template: PackedVector2Array,
	a: float, b: float, threshold: float
) -> float:
	var x1 := PHI * a + (1.0 - PHI) * b
	var f1 := _path_distance(_rotate_by(pts, x1), template)
	var x2 := (1.0 - PHI) * a + PHI * b
	var f2 := _path_distance(_rotate_by(pts, x2), template)

	while abs(b - a) > threshold:
		if f1 < f2:
			b = x2
			x2 = x1; f2 = f1
			x1 = PHI * a + (1.0 - PHI) * b
			f1 = _path_distance(_rotate_by(pts, x1), template)
		else:
			a = x1
			x1 = x2; f1 = f2
			x2 = (1.0 - PHI) * a + PHI * b
			f2 = _path_distance(_rotate_by(pts, x2), template)

	return min(f1, f2)
