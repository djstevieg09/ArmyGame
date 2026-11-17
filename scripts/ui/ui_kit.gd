class_name UI
## Helpers for building the military-style interface in code: dark gunmetal
## panels, khaki trim and stencil headings.

const BG := Color(0.07, 0.08, 0.07)
const PANEL := Color(0.09, 0.10, 0.09, 0.92)
const GREEN := Color(0.33, 0.45, 0.22)
const ORANGE := Color(0.78, 0.42, 0.12)
const YELLOW := Color(0.93, 0.78, 0.36)
const BLUE := Color(0.22, 0.36, 0.46)
const RED := Color(0.66, 0.18, 0.15)
const GREY := Color(0.24, 0.26, 0.25)
const TEXT := Color(0.95, 0.94, 0.88)
const KHAKI := Color(0.76, 0.69, 0.5)

static var _stencil: Font


static func stencil() -> Font:
	if _stencil == null:
		_stencil = load("res://assets/BlackOpsOne-Regular.ttf")
	return _stencil


static func box(color: Color, radius := 18, border := 0, border_color := Color.BLACK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(mini(radius, 4))
	s.set_border_width_all(border)
	s.border_color = border_color
	s.anti_aliasing = true
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
	b.add_theme_font_override("font", stencil())
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)
	b.add_theme_stylebox_override("normal", _btn_box(color))
	b.add_theme_stylebox_override("hover", _btn_box(color.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", _btn_box(color.darkened(0.2), true))
	b.add_theme_stylebox_override("disabled", _btn_box(color.darkened(0.5).lerp(Color(0.15, 0.15, 0.15), 0.4)))
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


static func _btn_box(color: Color, pressed := false) -> StyleBoxFlat:
	var s := box(color, 3, 0)
	s.border_width_top = 2
	s.border_width_bottom = 1 if pressed else 5
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_color = color.darkened(0.45)
	s.border_blend = false
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	s.shadow_color = Color(0, 0, 0, 0.45)
	return s


static func label(text: String, font_size := 28, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	if font_size >= 40:
		l.add_theme_font_override("font", stencil())
		l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func panel(color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color, 4, 1, Color(KHAKI, 0.45))
	s.border_width_top = 3
	s.border_color = Color(KHAKI, 0.55)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", s)
	return p


static func pill(text: String, color: Color, font_size := 26) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(color.darkened(0.25), 4, 1, color.lightened(0.2))
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
