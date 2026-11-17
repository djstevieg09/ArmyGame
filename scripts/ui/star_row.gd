class_name StarRow
extends Control
## Draws 0..3 filled stars as vector polygons (no font glyphs needed).

var count := 0
var star_size := 28.0
var total := 3


func _init(n := 0, size_px := 28.0, of := 3) -> void:
	count = n
	star_size = size_px
	total = of
	custom_minimum_size = Vector2(star_size * 1.15 * total, star_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for i in total:
		var c := Vector2(star_size * 0.5 + i * star_size * 1.15, star_size * 0.5)
		var pts := PackedVector2Array()
		for k in 10:
			var r := star_size * (0.5 if k % 2 == 0 else 0.22)
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var col := UI.YELLOW if i < count else Color(1, 1, 1, 0.18)
		draw_colored_polygon(pts, col)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, 0.35), 2.0, true)
