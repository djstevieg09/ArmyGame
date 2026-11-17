class_name UI
## Small helpers for building the chunky, rounded toy-box interface in code.

const BG := Color(0.07, 0.09, 0.12)
const PANEL := Color(0.12, 0.15, 0.20, 0.94)
const GREEN := Color(0.30, 0.78, 0.38)
const ORANGE := Color(0.98, 0.55, 0.20)
const YELLOW := Color(0.98, 0.82, 0.25)
const BLUE := Color(0.30, 0.62, 0.98)
const RED := Color(0.92, 0.32, 0.30)
const GREY := Color(0.35, 0.38, 0.45)
const TEXT := Color(0.97, 0.97, 0.95)


static func box(color: Color, radius := 18, border := 0, border_color := Color.BLACK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	return s


static func button(text: String, color := GREEN, font_size := 30, min_size := Vector2(200, 72)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_stylebox_override("normal", box(color, 20, 0))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 20, 0))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.18), 20, 0))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.55), 20, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): Sfx.play("click", -6.0))
	b.button_down.connect(func():
		b.pivot_offset = b.size / 2.0
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.05))
	b.button_up.connect(func():
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return b


static func label(text: String, font_size := 28, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	return l


static func panel(color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, 26)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", s)
	return p


static func pill(text: String, color: Color, font_size := 26) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, 40)
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.shadow_size = 3
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, font_size)
	l.name = "Label"
	p.add_child(l)
	return p


static func vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func center_overlay(parent: Node, dim := 0.55) -> CenterContainer:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(c)
	return c


static func pop_in(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2(0.7, 0.7)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, 0.18)


static func fmt_time(seconds: int) -> String:
	return "%d:%02d" % [int(seconds / 60), seconds % 60]


static func stars(n: int, size_px := 28.0) -> StarRow:
	return StarRow.new(n, size_px)
