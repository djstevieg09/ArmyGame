class_name Hud
extends CanvasLayer
## In-mission interface: objectives, squad cards, explosive buttons, results.

signal leave(action: String)  # "next", "map", "retry"

var m: Mission
var _obj_label: Label
var _timer_label: Label
var _squad_box: HBoxContainer
var _grenade_btn: Button
var _rocket_btn: Button
var _exit_btn: Button
var _toast: Label
var _toast_tw: Tween
var _hint: PanelContainer
var _overlay: Control
var _cards := {}
var _won := false
var _pause_btn: Button


## True if a screen point lands on interface rather than the battlefield.
func blocks_point(p: Vector2) -> bool:
	if _overlay != null or get_tree().paused:
		return true
	for b in [_pause_btn, _grenade_btn, _rocket_btn, _exit_btn]:
		if b != null and b.is_visible_in_tree() and b.get_global_rect().grow(8).has_point(p):
			return true
	return false


func bind(mission: Mission) -> void:
	m = mission
	m.ui_blocks = blocks_point
	m.stats_changed.connect(_refresh)
	m.message.connect(show_toast)
	m.ended.connect(_on_ended)
	_build()
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# top-left: mission name and objectives
	var top := UI.panel(Color(0.08, 0.1, 0.14, 0.72))
	top.position = Vector2(16, 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var tv := UI.vbox(2)
	top.add_child(tv)
	tv.add_child(UI.label("Mission %d  ·  %s" % [m.level_index + 1, m.data["name"]], 24, UI.YELLOW))
	_obj_label = UI.label("", 22)
	tv.add_child(_obj_label)
	# top-right: timer + pause
	var tr := UI.hbox(10)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-250, 16)
	tr.size = Vector2(234, 64)
	tr.alignment = BoxContainer.ALIGNMENT_END
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(tr)
	_timer_label = UI.label("0:00", 30)
	tr.add_child(_timer_label)
	var pause := UI.button("II", UI.GREY, 28, Vector2(72, 64))
	_pause_btn = pause
	pause.pressed.connect(_show_pause)
	tr.add_child(pause)
	# bottom-left: squad cards
	_squad_box = UI.hbox(8)
	_squad_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_squad_box.position = Vector2(16, -96)
	_squad_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_squad_box)
	for s in m.squad:
		var card := _make_card(s)
		_squad_box.add_child(card)
	# bottom-right: explosives
	var br := UI.hbox(12)
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.position = Vector2(-16, -16)
	root.add_child(br)
	_exit_btn = UI.button("EXIT\nTANK", UI.BLUE, 22, Vector2(110, 110))
	_exit_btn.pressed.connect(func(): m.exit_tank())
	br.add_child(_exit_btn)
	_rocket_btn = UI.button("", UI.ORANGE, 24, Vector2(130, 110))
	_rocket_btn.toggle_mode = true
	_rocket_btn.pressed.connect(func(): _toggle_mode("rocket"))
	br.add_child(_rocket_btn)
	_grenade_btn = UI.button("", Color(0.45, 0.6, 0.25), 24, Vector2(130, 110))
	_grenade_btn.pressed.connect(func(): _toggle_mode("grenade"))
	br.add_child(_grenade_btn)
	# toast
	_toast = UI.label("", 34, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-400, 110)
	_toast.size = Vector2(800, 50)
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	# hint
	if m.data.has("hint"):
		_hint = UI.panel(Color(0.08, 0.09, 0.07, 0.86))
		var hl := UI.label(m.data["hint"], 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size = Vector2(620, 0)
		_hint.add_child(hl)
		_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hint.position = Vector2(-350, 96)
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_hint)
		var tw := _hint.create_tween()
		tw.tween_interval(7.0)
		tw.tween_property(_hint, "modulate:a", 0.0, 0.6)
		tw.tween_callback(_hint.queue_free)


func _make_card(s: Unit) -> PanelContainer:
	var card := UI.panel(Color(0.08, 0.1, 0.14, 0.78))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: StyleBoxFlat = card.get_theme_stylebox("panel")
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	var v := UI.vbox(2)
	card.add_child(v)
	var n := UI.label(s.display_name, 20)
	v.add_child(n)
	var r := UI.label(Game.rank_name(s.rank), 15, Color(1, 1, 1, 0.6))
	v.add_child(r)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(96, 10)
	bar.show_percentage = false
	bar.max_value = s.max_hp
	bar.value = s.hp
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = UI.GREEN
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)
	_cards[s.roster_idx] = {"card": card, "bar": bar, "name": n}
	return card


func _process(_delta: float) -> void:
	if m == null:
		return
	_timer_label.text = UI.fmt_time(int(m.time))
	for s in m.squad:
		if _cards.has(s.roster_idx):
			var c: Dictionary = _cards[s.roster_idx]
			c["bar"].max_value = s.max_hp
			c["bar"].value = maxf(0.0, s.hp)
			c["card"].modulate = Color(1, 1, 1, 1) if s.alive else Color(1, 0.4, 0.4, 0.55)
	if Engine.get_process_frames() % 15 == 0:
		_refresh()


func _refresh() -> void:
	if m == null:
		return
	var lines: PackedStringArray = []
	for o in m.objective_status():
		lines.append(("✔ " if o["done"] else "• ") + o["text"])
	_obj_label.text = "\n".join(lines)
	_grenade_btn.text = "GRENADE\n×%d" % m.grenades
	_rocket_btn.text = "ROCKET\n×%d" % m.rocket_count
	_grenade_btn.disabled = m.grenades <= 0 or m.crew_in_tank()
	_rocket_btn.disabled = m.rocket_count <= 0 or m.crew_in_tank()
	_rocket_btn.visible = m.rocket_count > 0 or m.level_index >= 5
	_exit_btn.visible = m.crew_in_tank()
	_set_active(_grenade_btn, m.mode == "grenade")
	_set_active(_rocket_btn, m.mode == "rocket")


func _set_active(b: Button, on: bool) -> void:
	b.modulate = Color(1.25, 1.25, 1.25) if on else Color.WHITE
	b.scale = Vector2(1.08, 1.08) if on else Vector2.ONE
	b.pivot_offset = b.size / 2.0


func _toggle_mode(which: String) -> void:
	m.mode = "" if m.mode == which else which
	if m.mode != "":
		show_toast("Tap where to %s" % ("throw the grenade" if which == "grenade" else "fire the rocket"), UI.YELLOW)
	_refresh()


func show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tw:
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = _toast.create_tween()
	_toast_tw.tween_interval(1.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------- overlays

func _clear_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _show_pause() -> void:
	if m.state != "play" or _overlay:
		return
	get_tree().paused = true
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(holder)
	_overlay = holder
	var c := UI.center_overlay(holder)
	var p := UI.panel()
	c.add_child(p)
	var v := UI.vbox(16)
	p.add_child(v)
	v.add_child(UI.label("Paused", 44, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER))
	var resume := UI.button("Resume", UI.GREEN)
	resume.pressed.connect(func():
		get_tree().paused = false
		_clear_overlay())
	v.add_child(resume)
	var music := UI.button("Music: %s" % ("On" if Game.music_on else "Off"), UI.GREY, 26)
	music.pressed.connect(func():
		Sfx.set_music(not Game.music_on)
		music.text = "Music: %s" % ("On" if Game.music_on else "Off"))
	v.add_child(music)
	var quit := UI.button("Abandon mission", UI.RED, 26)
	quit.pressed.connect(func():
		get_tree().paused = false
		leave.emit("abandon"))
	v.add_child(quit)
	UI.pop_in(p)


func _on_ended(won: bool) -> void:
	_won = won
	await get_tree().create_timer(1.4).timeout
	if won:
		_show_win()
	else:
		_show_lose()


func _show_win() -> void:
	_clear_overlay()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	_overlay = holder
	var c := UI.center_overlay(holder)
	var p := UI.panel()
	c.add_child(p)
	var v := UI.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(UI.label("Mission complete!", 48, UI.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
	var sc := CenterContainer.new()
	sc.add_child(UI.stars(m.star_count(), 64))
	v.add_child(sc)
	var coins := m.coins_earned()
	var total_kills := 0
	for k in m.kills.values():
		total_kills += k
	v.add_child(UI.label("Time %s   ·   Enemies %d   ·   Lost %d" % [UI.fmt_time(int(m.time)), total_kills, m.losses], 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var coin_label := UI.label("+%d coins" % coins, 34, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(coin_label)
	if m.star_count() < 3:
		var tip := "3 stars: no losses and finish under %s" % UI.fmt_time(int(m.data["par"]))
		v.add_child(UI.label(tip, 20, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var dbl := UI.button("Double coins (ad)", UI.BLUE, 24, Vector2(250, 72))
	dbl.pressed.connect(func():
		dbl.disabled = true
		Ads.show_rewarded(self)
		var ok: bool = await Ads.rewarded_finished
		if ok:
			set_meta("double", true)
			coin_label.text = "+%d coins" % (coins * 2)
			Sfx.play("pickup"))
	dbl.visible = Ads.can_show_rewarded()
	row.add_child(dbl)
	var map := UI.button("Map", UI.GREY, 28, Vector2(150, 72))
	map.pressed.connect(func(): leave.emit("map"))
	row.add_child(map)
	if m.level_index + 1 < Levels.count():
		var nxt := UI.button("Next mission", UI.GREEN, 28, Vector2(240, 72))
		nxt.pressed.connect(func(): leave.emit("next"))
		row.add_child(nxt)
	UI.pop_in(p)


func _show_lose() -> void:
	_clear_overlay()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	_overlay = holder
	var c := UI.center_overlay(holder)
	var p := UI.panel()
	c.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	v.add_child(UI.label("Squad lost!", 48, UI.RED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Your squad fought bravely. Revive them and carry on?", 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	if not m.revived:
		var ad := UI.button("Revive (watch ad)", UI.BLUE, 24, Vector2(250, 72))
		ad.visible = Ads.can_show_rewarded()
		ad.pressed.connect(func():
			Ads.show_rewarded(self)
			var ok: bool = await Ads.rewarded_finished
			if ok:
				_revive())
		row.add_child(ad)
		var gem := UI.button("Revive (%d gems)" % Game.GEMS_FOR_REVIVE, Color(0.4, 0.28, 0.55), 24, Vector2(230, 72))
		gem.disabled = Game.gems < Game.GEMS_FOR_REVIVE
		gem.pressed.connect(func():
			if Game.gems >= Game.GEMS_FOR_REVIVE:
				Game.gems -= Game.GEMS_FOR_REVIVE
				Game.save_game()
				_revive())
		row.add_child(gem)
	var row2 := UI.hbox(14)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	var retry := UI.button("Retry", UI.GREEN, 28, Vector2(170, 72))
	retry.pressed.connect(func(): leave.emit("retry"))
	row2.add_child(retry)
	var map := UI.button("Map", UI.GREY, 28, Vector2(150, 72))
	map.pressed.connect(func(): leave.emit("map"))
	row2.add_child(map)
	var cost := "Retrying or leaving uses 1 life." if m.level_index >= Game.FREE_LIVES_LEVELS and not Game.unlimited_lives else "Early missions never cost a life."
	v.add_child(UI.label(cost, 20, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	UI.pop_in(p)


func _revive() -> void:
	_clear_overlay()
	m.revive_squad()
	# Rebuild the squad cards for the fresh soldiers
	_cards.clear()
	for ch in _squad_box.get_children():
		ch.queue_free()
	for s in m.squad:
		_squad_box.add_child(_make_card(s))
	_refresh()
