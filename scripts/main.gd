extends Node
## Screen flow: title -> world map -> mission -> results -> map.

var current: Node
var _mission: Mission
var _hud: Hud
var _level := 0
var _roster_used: Array = []


func _ready() -> void:
	_apply_theme()
	get_tree().root.content_scale_factor = 1.0
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			_screenshot_mode(a.substr(7))
			return
	show_title()


func _apply_theme() -> void:
	var t := Theme.new()
	var f := load("res://assets/Oswald.ttf") as FontFile
	if f:
		t.default_font = f
	t.default_font_size = 26
	get_tree().root.theme = t


func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	add_child(n)


# ------------------------------------------------------------------- title

func show_title() -> void:
	Sfx.music("theme")
	var root := Node.new()
	# Live demo battle in the background, played by the bot.
	var demo := Mission.new()
	demo.setup(2, Game.squad_for(4), {"autoplay": true, "demo": true, "god": true, "seed": 99})
	root.add_child(demo)
	demo.zoom = 0.85
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.3)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	var v := UI.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var logo := UI.label("FIRETEAM FURY", 110, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	logo.add_theme_constant_override("outline_size", 14)
	logo.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.04))
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	logo.add_theme_constant_override("shadow_offset_y", 8)
	v.add_child(logo)
	var tag := UI.label("TEN WAR ZONES.  ONE FIRETEAM.  NO RETREAT.", 30, UI.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(tag)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	v.add_child(sp)
	var play := UI.button("DEPLOY", UI.GREEN, 48, Vector2(340, 100))
	play.pressed.connect(show_map)
	var pc := CenterContainer.new()
	pc.add_child(play)
	v.add_child(pc)
	var tw := play.create_tween().set_loops()
	tw.tween_property(play, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(play, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	play.resized.connect(func(): play.pivot_offset = play.size / 2.0)
	_swap(root)
	# loop the demo mission forever
	demo.ended.connect(func(_w): if is_instance_valid(root) and current == root: show_title())


# ------------------------------------------------------------------- world map

func show_map() -> void:
	get_tree().paused = false
	Sfx.music("theme")
	var map := MapScreen.new()
	map.main = self
	_swap(map)


func start_mission(index: int) -> void:
	if not Game.has_life_for(index):
		return
	_level = index
	Sfx.music("mission")
	var d := Levels.get_level(index)
	var roster := Game.squad_for(d["squad"])
	_roster_used = roster
	var root := Node.new()
	_mission = Mission.new()
	_mission.setup(index, roster, {"bonus_grenades": Game.bonus_grenades, "bonus_rockets": Game.bonus_rockets})
	# Bonus explosives are consumed once they are brought into a mission.
	Game.bonus_grenades = 0
	Game.bonus_rockets = 0
	Game.save_game()
	root.add_child(_mission)
	_hud = Hud.new()
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_hud)
	_hud.bind(_mission)
	_hud.leave.connect(_on_leave)
	_swap(root)


func _on_leave(action: String) -> void:
	get_tree().paused = false
	var won := _mission.state == "won"
	var sd := _mission.survivors_and_dead()
	var coins := _mission.coins_earned() if won else 0
	if won and _hud.has_meta("double"):
		coins *= 2
	Game.finish_mission(_level, won, sd[0], sd[1], _mission.kills, _mission.star_count() if won else 0, coins)
	var next := _level
	match action:
		"next":
			next = min(_level + 1, Levels.count() - 1)
		"retry":
			next = _level
		_:
			next = -1
	await Ads.maybe_show_interstitial(self, _level)
	if next >= 0 and Game.has_life_for(next):
		start_mission(next)
	else:
		show_map()


# ------------------------------------------------------------------- screenshots
# Used by the build pipeline: `--shot=title|map|mission:<n>` renders a few
# seconds then saves a PNG to user://shot.png and quits.

func _screenshot_mode(what: String) -> void:
	if what == "title":
		show_title()
	elif what == "map":
		show_map()
	elif what.begins_with("mission:"):
		var i := int(what.substr(8)) - 1
		Game.unlimited_lives = true
		Game.gore = "--gore" in OS.get_cmdline_user_args()
		start_mission(i)
		_mission.autoplay = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--zoom="):
				_mission.zoom = float(a.substr(7))
	var secs := 6.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
	await get_tree().create_timer(secs).timeout
	var img := get_viewport().get_texture().get_image()
	var out := "user://shot.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	img.save_png(out)
	get_tree().quit()
