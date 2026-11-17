class_name MapScreen
extends Control
## World map: ten mission nodes along a winding path, plus lives, currencies,
## shop, daily reward and the Roll of Honour.

var main
var _lives_label: Label
var _coins_label: Label
var _gems_label: Label
var _popup: Control

const NODE_POS := [
	Vector2(0.10, 0.70), Vector2(0.20, 0.45), Vector2(0.31, 0.68), Vector2(0.41, 0.42), Vector2(0.50, 0.66),
	Vector2(0.59, 0.40), Vector2(0.68, 0.64), Vector2(0.77, 0.40), Vector2(0.85, 0.65), Vector2(0.92, 0.38),
]


func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)
	var bg := _MapBackground.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# satellite-style recon photo of the campaign area, under the route lines
	var photo := TextureRect.new()
	photo.texture = load("res://assets/ui/campaign_map.jpg")
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo.show_behind_parent = true
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(photo)
	_build_top_bar()
	_build_nodes()
	_build_bottom_bar()
	Game.changed.connect(_refresh)
	_refresh()
	if Game.daily_available() and not "--nodaily" in OS.get_cmdline_user_args():
		_show_daily.call_deferred()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _process(_d: float) -> void:
	if Engine.get_process_frames() % 30 == 0:
		_refresh()


func _build_top_bar() -> void:
	var bar := UI.hbox(14)
	bar.position = Vector2(20, 16)
	add_child(bar)
	var lives := UI.pill("", Color(0.85, 0.25, 0.3), 26)
	_lives_label = lives.get_node("Label")
	bar.add_child(lives)
	var coins := UI.pill("", Color(0.75, 0.55, 0.1), 26)
	_coins_label = coins.get_node("Label")
	bar.add_child(coins)
	var gems := UI.pill("", Color(0.5, 0.3, 0.85), 26)
	_gems_label = gems.get_node("Label")
	bar.add_child(gems)
	var title := UI.label("FIRETEAM FURY", 44, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	title.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	title.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	title.position = Vector2(-340, 12)
	title.size = Vector2(320, 60)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.2, 0.1))
	add_child(title)


func _build_bottom_bar() -> void:
	var bar := UI.hbox(14)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position = Vector2(20, -20)
	add_child(bar)
	var shop := UI.button("Shop", Color(0.4, 0.28, 0.55), 28, Vector2(160, 70))
	shop.pressed.connect(_show_shop)
	bar.add_child(shop)
	var honour := UI.button("Roll of Honour", UI.GREY, 26, Vector2(260, 70))
	honour.pressed.connect(_show_honour)
	bar.add_child(honour)
	var squad := UI.button("Squad", UI.BLUE, 28, Vector2(150, 70))
	squad.pressed.connect(_show_squad)
	bar.add_child(squad)
	var daily := UI.button("Daily", UI.ORANGE, 28, Vector2(140, 70))
	daily.pressed.connect(_show_daily)
	bar.add_child(daily)
	var stars := UI.label("", 28, UI.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT)
	stars.name = "StarTotal"
	stars.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stars.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stars.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stars.position = Vector2(-300, -64)
	stars.size = Vector2(280, 44)
	add_child(stars)


func _build_nodes() -> void:
	var holder := Control.new()
	holder.name = "Nodes"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.resized.connect(_layout_nodes)
	for i in Levels.count():
		var unlocked := i < Game.unlocked
		var d := Levels.get_level(i)
		var col: Color = (UI.ORANGE if i == Game.unlocked - 1 else UI.GREEN) if unlocked else UI.GREY
		var b := UI.button(str(i + 1), col, 40, Vector2(96, 96))
		var st: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		st.set_corner_radius_all(48)
		st.set_border_width_all(5)
		st.border_color = Color(1, 0.95, 0.85, 0.95) if i == Game.unlocked - 1 else Color(0.05, 0.05, 0.04, 0.75)
		b.add_theme_stylebox_override("normal", st)
		var st2: StyleBoxFlat = st.duplicate()
		st2.bg_color = col.lightened(0.15)
		b.add_theme_stylebox_override("hover", st2)
		b.add_theme_stylebox_override("pressed", st2)
		b.disabled = not unlocked
		var dis: StyleBoxFlat = st.duplicate()
		dis.bg_color = Color(0.18, 0.19, 0.18, 0.85)
		b.add_theme_stylebox_override("disabled", dis)
		b.pressed.connect(_show_brief.bind(i))
		b.name = "L%d" % i
		holder.add_child(b)
		var sr := UI.stars(int(Game.stars.get(str(i), 0)), 26)
		sr.name = "S%d" % i
		holder.add_child(sr)
		var nl := UI.label(d["name"], 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		nl.name = "N%d" % i
		nl.custom_minimum_size = Vector2(170, 0)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		holder.add_child(nl)
		if i == Game.unlocked - 1:
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	_layout_nodes.call_deferred()


func _layout_nodes() -> void:
	var holder := get_node("Nodes")
	var sz: Vector2 = holder.size
	for i in Levels.count():
		var p: Vector2 = NODE_POS[i] * sz
		var b: Control = holder.get_node("L%d" % i)
		b.position = p - Vector2(48, 48)
		b.pivot_offset = Vector2(48, 48)
		var s: Control = holder.get_node("S%d" % i)
		s.position = p + Vector2(-s.custom_minimum_size.x / 2.0, 54)
		var n: Control = holder.get_node("N%d" % i)
		n.position = p + Vector2(-85, 84)
	var bg := get_child(0)
	bg.points = NODE_POS
	bg.queue_redraw()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var lt := "Lives %d/%d" % [Game.lives, Game.MAX_LIVES]
	if Game.unlimited_lives:
		lt = "Lives: unlimited"
	elif Game.lives < Game.MAX_LIVES:
		lt += "  " + UI.fmt_time(Game.seconds_to_next_life())
	_lives_label.text = lt
	_coins_label.text = "Coins %d" % Game.coins
	_gems_label.text = "Gems %d" % Game.gems
	var st := get_node_or_null("StarTotal")
	if st:
		st.text = "Stars %d / %d" % [Game.total_stars(), Levels.count() * 3]


# ------------------------------------------------------------------ popups

func _open_popup() -> VBoxContainer:
	_close_popup()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	_popup = holder
	var c := UI.center_overlay(holder)
	var p := UI.panel()
	c.add_child(p)
	var v := UI.vbox(14)
	p.add_child(v)
	p.ready.connect(func(): UI.pop_in(p))
	return v


func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null


func _close_button(v: VBoxContainer, text := "Close") -> void:
	var b := UI.button(text, UI.GREY, 26, Vector2(180, 64))
	b.pressed.connect(_close_popup)
	var cc := CenterContainer.new()
	cc.add_child(b)
	v.add_child(cc)


func _show_brief(i: int) -> void:
	var d := Levels.get_level(i)
	var v := _open_popup()
	v.add_child(UI.label("Mission %d" % (i + 1), 24, Color(1, 1, 1, 0.6)))
	v.add_child(UI.label(d["name"], 46, UI.YELLOW))
	var brief := UI.label(d["brief"], 26)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size = Vector2(640, 0)
	v.add_child(brief)
	var squad := Game.squad_for(d["squad"])
	var names: PackedStringArray = []
	for s in squad:
		names.append("%s %s" % [Game.rank_name(s["rank"]), s["name"]])
	var sl := UI.label("Squad: " + ", ".join(names), 22, Color(0.8, 1, 0.8))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(640, 0)
	v.add_child(sl)
	if Game.bonus_grenades + Game.bonus_rockets > 0:
		v.add_child(UI.label("Bonus kit: +%d grenades, +%d rockets" % [Game.bonus_grenades, Game.bonus_rockets], 22, UI.YELLOW))
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var back := UI.button("Back", UI.GREY, 28, Vector2(160, 76))
	back.pressed.connect(_close_popup)
	row.add_child(back)
	var go := UI.button("Deploy", UI.GREEN, 34, Vector2(240, 76))
	row.add_child(go)
	if i < Game.FREE_LIVES_LEVELS or Game.unlimited_lives:
		v.add_child(UI.label("This mission never costs a life.", 20, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		v.add_child(UI.label("Failing uses 1 life. Winning is always free.", 20, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	go.pressed.connect(func():
		if Game.has_life_for(i):
			main.start_mission(i)
		else:
			_show_no_lives(i))


func _show_no_lives(i: int) -> void:
	var v := _open_popup()
	v.add_child(UI.label("Out of lives", 46, UI.RED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Next life in %s" % UI.fmt_time(Game.seconds_to_next_life()), 28, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var ad := UI.button("+1 life (watch ad)", UI.BLUE, 24, Vector2(260, 72))
	ad.disabled = not Ads.can_show_rewarded()
	ad.pressed.connect(func():
		Ads.show_rewarded(self)
		var ok: bool = await Ads.rewarded_finished
		if ok:
			Game.add_lives(1)
			_show_brief(i))
	row.add_child(ad)
	var gem := UI.button("Refill (%d gems)" % Game.GEMS_FOR_LIVES, Color(0.4, 0.28, 0.55), 24, Vector2(240, 72))
	gem.disabled = Game.gems < Game.GEMS_FOR_LIVES
	gem.pressed.connect(func():
		if Game.buy_lives_with_gems():
			_show_brief(i))
	row.add_child(gem)
	_close_button(v)


func _show_daily() -> void:
	var v := _open_popup()
	v.add_child(UI.label("Daily supply drop", 44, UI.ORANGE, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var next_day := 0
	if Game.daily_available():
		next_day = (Game.daily_streak + 1) % Game.DAILY_REWARDS.size() if Game.last_daily_day == Game.today_index() - 1 else 0
	for k in Game.DAILY_REWARDS.size():
		var r: Dictionary = Game.DAILY_REWARDS[k]
		var txt := "Day %d\n" % (k + 1)
		if r.has("coins"):
			txt += "%d coins" % r["coins"]
		elif r.has("gems"):
			txt += "%d gems" % r["gems"]
		else:
			txt += "%d grenades" % r["grenades"]
		var col := UI.GREY
		if Game.daily_available() and k == next_day:
			col = UI.ORANGE
		elif (not Game.daily_available()) and k == Game.daily_streak:
			col = UI.GREEN
		var cell := UI.pill(txt, col, 20)
		cell.custom_minimum_size = Vector2(110, 80)
		row.add_child(cell)
	if Game.daily_available():
		var claim := UI.button("Claim", UI.GREEN, 32, Vector2(220, 76))
		claim.pressed.connect(func():
			var r := Game.claim_daily()
			Sfx.play("win")
			_close_popup()
			var v2 := _open_popup()
			var parts: PackedStringArray = []
			for key in r:
				parts.append("+%d %s" % [r[key], key])
			v2.add_child(UI.label("Supplies received!", 40, UI.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
			v2.add_child(UI.label(", ".join(parts), 30, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER))
			_close_button(v2, "Great"))
		var cc := CenterContainer.new()
		cc.add_child(claim)
		v.add_child(cc)
	else:
		v.add_child(UI.label("Come back tomorrow for the next drop.", 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		_close_button(v)


func _show_shop() -> void:
	var v := _open_popup()
	v.add_child(UI.label("Shop", 46, Color(0.75, 0.55, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for pid in Ads.PRODUCTS:
		if pid == "no_ads" and Game.no_ads:
			continue
		var p: Dictionary = Ads.PRODUCTS[pid]
		var b := UI.button("%s\n%s" % [p["title"], p["price"]], Color(0.4, 0.28, 0.55), 22, Vector2(240, 84))
		b.tooltip_text = p["desc"]
		b.pressed.connect(func():
			Ads.purchase(self, pid)
			await Ads.purchase_finished
			_show_shop())
		grid.add_child(b)
	var kit := UI.button("3 grenades\n300 coins", Color(0.45, 0.6, 0.25), 22, Vector2(240, 84))
	kit.disabled = Game.coins < 300
	kit.pressed.connect(func():
		if Game.coins >= 300:
			Game.coins -= 300
			Game.bonus_grenades += 3
			Game.save_game()
			Sfx.play("pickup")
			_show_shop())
	grid.add_child(kit)
	var rk := UI.button("2 rockets\n400 coins", UI.ORANGE, 22, Vector2(240, 84))
	rk.disabled = Game.coins < 400
	rk.pressed.connect(func():
		if Game.coins >= 400:
			Game.coins -= 400
			Game.bonus_rockets += 2
			Game.save_game()
			Sfx.play("pickup")
			_show_shop())
	grid.add_child(rk)
	v.add_child(UI.label("Paint jobs", 30, UI.TEXT))
	var srow := UI.hbox(10)
	v.add_child(srow)
	for key in Game.SKINS:
		var s: Dictionary = Game.SKINS[key]
		var owned: bool = key in Game.owned_skins
		var label: String = s["name"] + ("\n(equipped)" if Game.skin == key else ("\nowned" if owned else "\n%d coins" % s["price"]))
		var b2 := UI.button(label, s["color"].darkened(0.15), 18, Vector2(150, 72))
		b2.disabled = not owned and Game.coins < s["price"]
		b2.pressed.connect(func():
			if not owned:
				if Game.coins < s["price"]:
					return
				Game.coins -= s["price"]
				Game.owned_skins.append(key)
			Game.skin = key
			Game.save_game()
			_show_shop())
		srow.add_child(b2)
	v.add_child(UI.label("Purchases are simulated in this test build.", 18, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	_close_button(v)


func _show_honour() -> void:
	var v := _open_popup()
	v.add_child(UI.label("Roll of Honour", 44, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER))
	if Game.fallen.is_empty():
		v.add_child(UI.label("No soldiers lost yet. Keep it that way!", 26, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(620, 320)
		v.add_child(sc)
		var list := UI.vbox(6)
		sc.add_child(list)
		var rev := Game.fallen.duplicate()
		rev.reverse()
		for f in rev:
			list.add_child(UI.label("%s %s  ·  fell in mission %d" % [Game.rank_name(int(f["rank"])), f["name"], int(f["level"])], 24))
	_close_button(v)


func _show_squad() -> void:
	var v := _open_popup()
	v.add_child(UI.label("Your squad", 44, UI.BLUE, HORIZONTAL_ALIGNMENT_CENTER))
	for s in Game.squad_for(5):
		v.add_child(UI.label("%s %s  ·  %d missions  ·  %d enemies" % [Game.rank_name(int(s["rank"])), s["name"], int(s["missions"]), int(s["kills"])], 26))
	v.add_child(UI.label("Survivors are promoted after every win. Higher ranks shoot faster and straighter.", 20, Color(1, 1, 1, 0.6)))
	_close_button(v)


class _MapBackground:
	extends Control
	var points: Array = []

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.12))
		if points.size() > 1:
			var pts := PackedVector2Array()
			for p in points:
				pts.append(p * sz)
			# dashed trail between missions
			for i in pts.size() - 1:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var n := int(a.distance_to(b) / 22.0)
				for k in n:
					if k % 2 == 0:
						draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(0.95, 0.25, 0.15, 0.85), 5.0, true)
