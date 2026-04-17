extends Control
class_name ShopShelf
## Draws a cozy wooden shelf with animated potion bottles.
## Call set_stock(n) to update displayed potions.

const SHELF_COLOR     := Color(0.42, 0.26, 0.10, 1.0)
const SHELF_EDGE      := Color(0.32, 0.18, 0.06, 1.0)
const SHELF_SHADOW    := Color(0.18, 0.10, 0.03, 0.5)
const BOTTLE_COLORS   := [
	Color(0.55, 0.15, 0.70, 1.0),  # purple
	Color(0.15, 0.55, 0.70, 1.0),  # teal
	Color(0.70, 0.20, 0.15, 1.0),  # red
	Color(0.20, 0.65, 0.25, 1.0),  # green
	Color(0.70, 0.55, 0.10, 1.0),  # gold
]
const LABEL_COLOR     := Color(0.95, 0.90, 0.75, 1.0)
const CORK_COLOR      := Color(0.72, 0.52, 0.28, 1.0)
const SHINE_COLOR     := Color(1.0, 1.0, 1.0, 0.28)

var _potions: Array[Control] = []
var _max_slots: int = 8
var _stock: int = 0


func _ready() -> void:
	_draw_shelf_bg()


func set_stock(count: int, max_slots: int) -> void:
	_stock = count
	_max_slots = max_slots
	_rebuild_potions()


func _draw_shelf_bg() -> void:
	# Shadow under shelf
	var shadow := ColorRect.new()
	shadow.color = SHELF_SHADOW
	shadow.anchor_right = 1.0
	shadow.anchor_bottom = 1.0
	shadow.offset_top = 6.0
	shadow.offset_left = 4.0
	add_child(shadow)

	# Main shelf plank
	var plank := ColorRect.new()
	plank.color = SHELF_COLOR
	plank.anchor_right = 1.0
	plank.anchor_bottom = 1.0
	add_child(plank)

	# Shelf front edge (darker strip at top)
	var edge := ColorRect.new()
	edge.color = SHELF_EDGE
	edge.anchor_right = 1.0
	edge.offset_bottom = 8.0
	add_child(edge)

	# Wood grain lines
	for i in 3:
		var grain := ColorRect.new()
		grain.color = Color(0.35, 0.20, 0.07, 0.3)
		grain.anchor_right = 1.0
		grain.offset_top = 10.0 + i * 14.0
		grain.offset_bottom = 11.0 + i * 14.0
		add_child(grain)


func _rebuild_potions() -> void:
	for p in _potions:
		if is_instance_valid(p):
			p.queue_free()
	_potions.clear()

	var slots: int = min(_stock, _max_slots)
	if slots <= 0:
		return

	var w: float = size.x if size.x > 0 else 300.0
	var slot_w: float = min(52.0, w / float(_max_slots))
	var start_x: float = (w - slot_w * slots) * 0.5

	for i in slots:
		var p := _make_potion(i, start_x + i * slot_w, slot_w)
		add_child(p)
		_potions.append(p)
		_animate_potion(p, i)


func _make_potion(index: int, x: float, slot_w: float) -> Control:
	var col: Color = BOTTLE_COLORS[index % BOTTLE_COLORS.size()]
	var container := Control.new()
	container.position = Vector2(x + slot_w * 0.1, 4.0)
	container.custom_minimum_size = Vector2(slot_w * 0.8, size.y - 8.0)

	var bw: float = slot_w * 0.55
	var bh: float = (size.y - 8.0) * 0.80
	var bx: float = (slot_w * 0.8 - bw) * 0.5

	# Bottle body (rounded look via layered rects)
	var body := ColorRect.new()
	body.color = col
	body.position = Vector2(bx, 12.0)
	body.size = Vector2(bw, bh)
	container.add_child(body)

	# Bottle shoulder curves (top corners darkened)
	var tl := ColorRect.new()
	tl.color = col.darkened(0.3)
	tl.position = Vector2(bx, 12.0)
	tl.size = Vector2(4.0, 6.0)
	container.add_child(tl)

	var tr := ColorRect.new()
	tr.color = col.darkened(0.3)
	tr.position = Vector2(bx + bw - 4.0, 12.0)
	tr.size = Vector2(4.0, 6.0)
	container.add_child(tr)

	# Bottle neck
	var nw: float = bw * 0.35
	var nx: float = bx + (bw - nw) * 0.5
	var neck := ColorRect.new()
	neck.color = col.darkened(0.15)
	neck.position = Vector2(nx, 4.0)
	neck.size = Vector2(nw, 10.0)
	container.add_child(neck)

	# Cork
	var cork := ColorRect.new()
	cork.color = CORK_COLOR
	cork.position = Vector2(nx, 0.0)
	cork.size = Vector2(nw, 6.0)
	container.add_child(cork)

	# Label strip
	var lw := bw * 0.7
	var lx := bx + (bw - lw) * 0.5
	var label := ColorRect.new()
	label.color = LABEL_COLOR
	label.position = Vector2(lx, bh * 0.35 + 12.0)
	label.size = Vector2(lw, bh * 0.28)
	container.add_child(label)

	# Label cross mark (✦ style)
	var mark_h := ColorRect.new()
	mark_h.color = col.darkened(0.2)
	mark_h.position = Vector2(lx + lw * 0.2, bh * 0.35 + 12.0 + label.size.y * 0.4)
	mark_h.size = Vector2(lw * 0.6, 2.0)
	container.add_child(mark_h)

	# Shine highlight
	var shine := ColorRect.new()
	shine.color = SHINE_COLOR
	shine.position = Vector2(bx + 3.0, 14.0)
	shine.size = Vector2(4.0, bh * 0.4)
	container.add_child(shine)

	return container


func _animate_potion(p: Control, index: int) -> void:
	# Gentle float: each bottle offset slightly so they wave independently
	var base_y := p.position.y
	var delay := index * 0.18
	var t := create_tween().set_loops()
	t.tween_interval(delay)
	t.tween_property(p, "position:y", base_y - 3.0, 1.0 + index * 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "position:y", base_y, 1.0 + index * 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
