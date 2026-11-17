class_name Mission
extends Node3D
## One playable mission: builds the level from its ASCII map, runs the
## simulation, handles touch input and decides win or loss.

signal ended(won: bool)
signal message(text: String, color: Color)
signal stats_changed

enum Cell { FLOOR, BLOCK, CRATE, TREE, WATER, FORT, TURRET }

const BULLET_SPEED := 15.0
const GRENADE_RANGE := 8.5
const GRENADE_RADIUS := 2.0
const ROCKET_RADIUS := 1.6
const SHELL_RADIUS := 1.4
const FORT_HP := 2
const FORT_SPAWN_EVERY := 7.0
const FORT_MAX_ALIVE := 2

var level_index := 0
var data: Dictionary
var theme: Dictionary
var theme_name := ""
var W := 0
var H := 0
var cells: PackedByteArray = PackedByteArray()
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()

var squad: Array = []
var enemies: Array = []
var hostages: Array = []
var tank: Unit = null
var forts: Array = []  # {cell, hp, node, cd, alive}
var crates := {}  # Vector2i -> Node3D
var pickups: Array = []  # {cell, kind, node}
var extraction: Array = []  # Vector2i
var bullets: Array = []  # {pos, vel, team, dmg, life, node, src}
var throws: Array = []  # grenades {from, to, t, dur, node}
var rockets: Array = []  # {pos, vel, life, node, radius, dmg, fort_dmg, src}

var grenades := 3
var rocket_count := 0
var mode := ""  # "", "grenade", "rocket"
var time := 0.0
var state := "play"  # play, won, lost
var kills := {}  # roster index -> kills
var losses := 0
var revived := false
var autoplay := false
var demo := false
var _bot_cd := 0.0
var _obj_cd := 0.0
var spawn_cell := Vector2i.ZERO
var ui_blocks: Callable = func(_p): return false

var world: Node3D
var camera: Camera3D
var camera_follow: Node3D = null
var cam_focus := Vector3.ZERO
var pan_offset := Vector3.ZERO
var zoom := 1.0
var shake := 0.0
var _touches := {}
var _drag_moved := false
var _pinch_start := 0.0
var _zoom_start := 1.0
var _bullet_mesh_p: Mesh
var _bullet_mesh_e: Mesh


func setup(index: int, roster: Array, opts := {}) -> void:
	level_index = index
	data = Levels.get_level(index)
	theme_name = data["theme"]
	theme = Levels.THEMES[theme_name]
	autoplay = opts.get("autoplay", false)
	demo = opts.get("demo", false)
	rng.seed = opts.get("seed", 1000 + index)
	grenades = 2 + int(opts.get("bonus_grenades", 0))
	rocket_count = int(opts.get("bonus_rockets", 0))
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_build_environment()
	_parse_map(roster, opts.get("god", false))
	_build_floor()
	_setup_camera()
	if not demo:
		(func(): message.emit(["Go go go!", "Move out!", "Lock and load!", "Let's do this!"][index % 4], UI.YELLOW)).call_deferred()


# =================================================================== building

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/sky/%s.hdr" % theme["sky"])
	psm.energy_multiplier = 1.0
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = theme["fog"]
	env.fog_density = 0.0065
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = theme["sun"]
	sun.light_energy = theme["sun_energy"]
	sun.light_color = theme["sun_color"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.light_angular_distance = 0.6
	add_child(sun)


func debris_color() -> Color:
	match theme["ground"]:
		"sand": return Color(0.72, 0.6, 0.42)
		"snow": return Color(0.85, 0.87, 0.9)
		"concrete", "asphalt": return Color(0.5, 0.5, 0.5)
		"grass", "mossy": return Color(0.36, 0.32, 0.22)
	return Color(0.42, 0.36, 0.28)


func _parse_map(roster: Array, god: bool) -> void:
	var rows: Array = data["map"]
	H = rows.size()
	W = rows[0].length()
	cells.resize(W * H)
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var enemy_col: Color = Color(0.96, 0.50, 0.18)
	var player_col: Color = Game.skin_color()
	var seed := 0
	var tank_cell := Vector2i(-1, -1)
	for z in H:
		var row: String = rows[z]
		for x in W:
			var ch := row[x]
			var c := Vector2i(x, z)
			var cell := Cell.FLOOR
			seed += 1
			match ch:
				"#":
					cell = Cell.BLOCK
					var edge := x == 0 or z == 0 or x == W - 1 or z == H - 1
					if not edge:
						_place(Models.block(theme["block"], seed * 31 + level_index), c).rotation.y = (seed % 4) * PI / 2.0
				"c":
					cell = Cell.CRATE
					crates[c] = _place(Models.crate(seed), c)
				"T":
					cell = Cell.TREE
					var styles: Array = theme["trees"]
					_place(Models.tree(styles[(seed * 7) % styles.size()], seed * 17 + level_index), c).rotation.y = seed * 1.3
				"~":
					cell = Cell.WATER
				"S":
					spawn_cell = c
				"X":
					extraction.append(c)
				"E", "N":
					_spawn_enemy("rifle" if ch == "E" else "sniper", c, enemy_col)
				"B":
					cell = Cell.TURRET
					var t := _spawn_enemy("turret", c, enemy_col)
					t.set_meta("cell", c)
				"F":
					cell = Cell.FORT
					var node := _place(Models.fort(1), c)
					forts.append({"cell": c, "hp": FORT_HP, "node": node, "cd": 3.0 + forts.size() * 2.0, "alive": true})
				"H":
					var h := Unit.new()
					h.setup(self, Unit.Team.HOSTAGE, "hostage", Color.WHITE)
					h.position = cell_center(c)
					h.display_name = "Pilot"
					world.add_child(h)
					hostages.append(h)
				"g", "r":
					pickups.append({"cell": c, "kind": ch, "node": _place(Models.pickup(ch), c)})
				"V":
					tank_cell = c
			cells[z * W + x] = cell
			if cell != Cell.FLOOR:
				astar.set_point_solid(c, true)
	# squad
	var slots := _ring_cells(spawn_cell, roster.size())
	for i in roster.size():
		var s := Unit.new()
		s.setup(self, Unit.Team.PLAYER, "soldier", player_col)
		s.display_name = roster[i]["name"]
		s.roster_idx = i
		s.apply_rank(int(roster[i].get("rank", 0)))
		if god:
			s.hp = 9999.0
			s.max_hp = 9999.0
		s.position = cell_center(slots[i])
		s.face_dir = Vector3(1, 0, 0)
		world.add_child(s)
		squad.append(s)
	if tank_cell.x >= 0:
		tank = Unit.new()
		tank.setup(self, Unit.Team.PLAYER, "tank", player_col.darkened(0.1))
		tank.position = cell_center(tank_cell)
		tank.face_dir = Vector3(1, 0, 0)
		if god:
			tank.hp = 9999.0
			tank.max_hp = 9999.0
		world.add_child(tank)
	if not extraction.is_empty():
		var sum := Vector3.ZERO
		for c in extraction:
			sum += cell_center(c)
		var marker := Models.extraction_marker()
		marker.position = sum / extraction.size()
		world.add_child(marker)


func _spawn_enemy(kind: String, c: Vector2i, color: Color) -> Unit:
	var e := Unit.new()
	e.setup(self, Unit.Team.ENEMY, kind, color)
	e.position = cell_center(c)
	e.home = e.position
	e.face_dir = Vector3(-1, 0, 0)
	world.add_child(e)
	enemies.append(e)
	return e


func _place(node: Node3D, c: Vector2i) -> Node3D:
	node.position = cell_center(c)
	world.add_child(node)
	return node


const MARGIN := 22
const HILL_START := 2.5


func _height_at(x: float, z: float, noise: FastNoiseLite) -> float:
	# 0 inside the play area; rolling hills grow with distance outside it.
	var dx := maxf(maxf(-x, x - W), 0.0)
	var dz := maxf(maxf(-z, z - H), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	if d <= 0.0:
		return 0.0
	var t := clampf((d - 0.5) / HILL_START, 0.0, 1.0)
	var hills := (noise.get_noise_2d(x * 1.4, z * 1.4) * 0.5 + 0.5) * (0.6 + d * 0.22)
	return t * t * (0.4 + hills * 1.6)


func _water_depth(x: int, z: int) -> float:
	# vertex (x, z) is shared by up to four cells; lower it when all are water.
	var water := 0
	var total := 0
	for oz in [-1, 0]:
		for ox in [-1, 0]:
			var c := Vector2i(x + ox, z + oz)
			if not in_bounds(c):
				continue
			total += 1
			if get_cell(c) == Cell.WATER:
				water += 1
	if total == 0 or water == 0:
		return 0.0
	return -0.45 * float(water) / float(total)


func _build_floor() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77 + level_index * 13
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var patch := FastNoiseLite.new()
	patch.seed = 5 + level_index
	patch.frequency = 0.09
	patch.fractal_octaves = 3
	var x0 := -MARGIN
	var z0 := -MARGIN
	var nx := W + MARGIN * 2 + 1
	var nz := H + MARGIN * 2 + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var any_water := false
	for iz in nz:
		for ix in nx:
			var x := x0 + ix
			var z := z0 + iz
			var h := _height_at(float(x), float(z), noise)
			if x >= 0 and z >= 0 and x <= W and z <= H:
				var wd := _water_depth(x, z)
				if wd < 0.0:
					any_water = true
					h = wd
			heights[iz * nx + ix] = h
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := float(x0 + ix)
			var z := float(z0 + iz)
			var h := heights[iz * nx + ix]
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iz - 1, 0) * nx + ix]
			var hu := heights[mini(iz + 1, nz - 1) * nx + ix]
			var n := Vector3(hl - hr, 2.0, hd - hu).normalized()
			var blend := clampf(patch.get_noise_2d(x, z) * 0.9 + float(theme.get("patch", 0.35)), 0.0, 1.0)
			# paths of the second surface on hills look odd; fade to base there
			if h > 0.6:
				blend *= 0.5
			var wet := clampf(-h * 4.0, 0.0, 1.0)
			if not any_water:
				wet = 0.0
			elif h >= 0.0 and _near_water(int(x), int(z)):
				wet = 0.55
			st.set_color(Color(blend, wet, 0, 1))
			st.set_normal(n)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h, z))
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = st.commit()
	terrain.material_override = _terrain_mat()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	world.add_child(terrain)
	if any_water:
		_build_water()
	_scatter_scenery(noise)
	_ambient_particles()
	var bm := CapsuleMesh.new()
	bm.radius = 0.018
	bm.height = 0.5
	bm.radial_segments = 6
	bm.rings = 1
	_bullet_mesh_p = bm
	_bullet_mesh_e = bm


func _near_water(x: int, z: int) -> bool:
	for oz in range(-2, 2):
		for ox in range(-2, 2):
			var c := Vector2i(x + ox, z + oz)
			if in_bounds(c) and get_cell(c) == Cell.WATER:
				return true
	return false


func _terrain_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/terrain.gdshader")
	var a: String = theme["ground"]
	var b: String = theme["ground2"]
	m.set_shader_parameter("a_albedo", Models.tex("res://assets/tex/%s_albedo.jpg" % a))
	m.set_shader_parameter("a_normal", Models.tex("res://assets/tex/%s_normal.jpg" % a))
	m.set_shader_parameter("a_rough", Models.tex("res://assets/tex/%s_rough.jpg" % a))
	m.set_shader_parameter("b_albedo", Models.tex("res://assets/tex/%s_albedo.jpg" % b))
	m.set_shader_parameter("b_normal", Models.tex("res://assets/tex/%s_normal.jpg" % b))
	m.set_shader_parameter("b_rough", Models.tex("res://assets/tex/%s_rough.jpg" % b))
	m.set_shader_parameter("tint_a", theme["tint"])
	m.set_shader_parameter("tint_b", theme["tint2"])
	m.set_shader_parameter("scale_a", 0.28)
	m.set_shader_parameter("scale_b", 0.3)
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	nt.noise = fn
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	m.set_shader_parameter("macro_noise", nt)
	return m


func _build_water() -> void:
	# One sheet over the whole play area just below ground level; the terrain
	# dips under it where there is water, so shorelines follow the terrain.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in H:
		for x in W:
			var near := false
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var c := Vector2i(x + ox, z + oz)
					if in_bounds(c) and get_cell(c) == Cell.WATER:
						near = true
			if not near:
				continue
			for q in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var vx: int = x + q[0]
				var vz: int = z + q[1]
				var depth := -_water_depth(vx, vz) / 0.45
				st.set_color(Color(1, 1, 1, clampf(1.0 - depth, 0.0, 1.0)))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(vx, -0.09, vz))
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water.gdshader")
	m.set_shader_parameter("normal_tex", Models.tex("res://assets/tex/water_normal.jpg"))
	if theme_name == "beach":
		m.set_shader_parameter("deep", Color(0.02, 0.16, 0.22))
		m.set_shader_parameter("shallow", Color(0.08, 0.32, 0.32))
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(water)


func _scatter_scenery(noise: FastNoiseLite) -> void:
	# Trees and rocks on the hills around the battlefield so it reads as a real place.
	var r := RandomNumberGenerator.new()
	r.seed = 4242 + level_index
	var styles: Array = theme["trees"]
	var placed := 0
	var tries := 0
	while placed < 90 and tries < 600:
		tries += 1
		var x := r.randf_range(-MARGIN + 1, W + MARGIN - 1)
		var z := r.randf_range(-MARGIN + 1, H + MARGIN - 1)
		if x > -1.5 and x < W + 1.5 and z > -1.5 and z < H + 1.5:
			continue
		var node: Node3D
		if r.randf() < 0.72:
			node = Models.tree(styles[r.randi() % styles.size()], r.randi())
			node.scale *= r.randf_range(0.9, 1.4)
		else:
			node = Models.block(theme["block"] if theme["block"] in ["rock", "sandrock", "snowrock"] else "rock", r.randi())
			node.scale *= r.randf_range(0.7, 1.5)
		node.position = Vector3(x, _height_at(x, z, noise) - 0.05, z)
		node.rotation.y = r.randf() * TAU
		world.add_child(node)
		placed += 1


func _ambient_particles() -> void:
	var kind: String = theme["particles"]
	if kind == "":
		return
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 4, 10)
	var mi := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = Models.soft_circle()
	mat.vertex_color_use_as_albedo = true
	mi.material = mat
	if kind == "snow":
		p.amount = 500
		p.lifetime = 6.0
		pm.direction = Vector3(0.3, -1, 0.1)
		pm.spread = 15.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 1.4
		pm.gravity = Vector3(0, -0.4, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.color = Color(1, 1, 1, 0.9)
		mi.size = Vector2(0.07, 0.07)
	else:
		p.amount = 70
		p.lifetime = 7.0
		pm.direction = Vector3(1, 0.05, 0.3)
		pm.spread = 20.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3.ZERO
		pm.color = Color(0.85, 0.75, 0.6, 0.12)
		pm.scale_min = 8.0
		pm.scale_max = 16.0
		mi.size = Vector2(0.25, 0.25)
		mat.albedo_texture = Models.tex("res://assets/fx/smoke.png")
	p.process_material = pm
	p.draw_pass_1 = mi
	p.visibility_aabb = AABB(Vector3(-20, -6, -16), Vector3(40, 14, 32))
	p.preprocess = 4.0
	p.position = Vector3(0, 3.5, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.name = "Weather"
	camera_follow = p
	world.add_child(p)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.3
	camera.far = 220.0
	add_child(camera)
	cam_focus = squad_center()
	_update_camera(1.0)


# =================================================================== grid helpers

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return Cell.BLOCK
	return cells[c.y * W + c.x]


func set_cell(c: Vector2i, v: int) -> void:
	cells[c.y * W + c.x] = v
	astar.set_point_solid(c, v != Cell.FLOOR)


func walkable_cell(c: Vector2i) -> bool:
	return get_cell(c) == Cell.FLOOR


func walkable_pos(p: Vector3) -> bool:
	return walkable_cell(cell_of(p))


func blocks_sight(c: Vector2i) -> bool:
	var v := get_cell(c)
	return v == Cell.BLOCK or v == Cell.CRATE or v == Cell.TREE or v == Cell.FORT


func has_los(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	d.y = 0.0
	var dist := d.length()
	if dist < 0.01:
		return true
	var steps := int(dist / 0.25)
	var ca := cell_of(a)
	var cb := cell_of(b)
	for i in range(1, steps):
		var p := a + d * (float(i) / steps)
		var c := cell_of(p)
		if c == ca or c == cb:
			continue
		if blocks_sight(c):
			return false
	return true


func _ring_cells(center: Vector2i, n: int) -> Array:
	var out: Array = []
	var r := 0
	while out.size() < n and r < 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(absi(dx), absi(dz)) != r:
					continue
				var c := center + Vector2i(dx, dz)
				if walkable_cell(c) and not out.has(c):
					out.append(c)
					if out.size() >= n:
						return out
		r += 1
	while out.size() < n:
		out.append(center)
	return out


func nearest_walkable(c: Vector2i) -> Vector2i:
	if walkable_cell(c):
		return c
	for r in range(1, 8):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(absi(dx), absi(dz)) != r:
					continue
				var n := c + Vector2i(dx, dz)
				if walkable_cell(n):
					var d := Vector2(dx, dz).length()
					if d < bd:
						bd = d
						best = n
		if best.x >= 0:
			return best
	return c


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := nearest_walkable(cell_of(from))
	var b := nearest_walkable(cell_of(to))
	var ids := astar.get_id_path(a, b)
	var pts := PackedVector3Array()
	if ids.is_empty():
		return pts
	for i in range(1, ids.size()):
		pts.append(cell_center(ids[i]))
	if walkable_cell(cell_of(to)) and cell_of(to) == b:
		if pts.is_empty():
			pts.append(Vector3(to.x, 0, to.z))
		else:
			pts[pts.size() - 1] = Vector3(to.x, 0, to.z)
	return _smooth(from, pts)


## Drop waypoints we can walk straight past, so units move in natural lines.
func _smooth(from: Vector3, pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector3Array()
	var cur := from
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not _clear_walk(cur, pts[j]):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out


func _clear_walk(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var dist := d.length()
	var steps := int(dist / 0.2) + 1
	var side := Vector3(-d.z, 0, d.x).normalized() * 0.28
	for k in range(1, steps + 1):
		var p := a + d * (float(k) / steps)
		if not walkable_pos(p) or not walkable_pos(p + side) or not walkable_pos(p - side):
			return false
	return true


func separation(u: Unit) -> Vector3:
	var push := Vector3.ZERO
	var group: Array = squad if u.team == Unit.Team.PLAYER else (enemies if u.team == Unit.Team.ENEMY else hostages)
	for o in group:
		if o == u or not o.alive or o.boarded:
			continue
		var d: Vector3 = u.position - o.position
		d.y = 0.0
		var l := d.length()
		if l < 0.45 and l > 0.001:
			push += d / l * (0.45 - l) * 6.0
	return push


func in_extraction(p: Vector3) -> bool:
	return extraction.has(cell_of(p))


func squad_in_extraction() -> bool:
	for s in squad_and_tank():
		if s.alive and not s.boarded and (s.kind != "tank" or s.occupied) and in_extraction(s.position):
			return true
	return false


func nearest_extraction(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for c in extraction:
		var d := cell_center(c).distance_to(p)
		if d < bd:
			bd = d
			best = cell_center(c)
	return best


# =================================================================== queries

func alive_squad() -> Array:
	return squad.filter(func(s): return s.alive)


func squad_and_tank() -> Array:
	var a := squad.duplicate()
	if tank:
		a.append(tank)
	return a


func player_targets() -> Array:
	var out: Array = []
	for s in squad:
		if s.is_targetable():
			out.append(s)
	if tank and tank.is_targetable():
		out.append(tank)
	return out


func enemy_targets() -> Array:
	return enemies.filter(func(e): return e.alive)


func squad_center() -> Vector3:
	if tank and tank.occupied and tank.alive:
		return tank.position
	var alive := alive_squad()
	if alive.is_empty():
		return cell_center(spawn_cell)
	var c := Vector3.ZERO
	for s in alive:
		c += s.position
	return c / alive.size()


func crew_in_tank() -> bool:
	return tank != null and tank.alive and tank.occupied


# =================================================================== main loop

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	step(minf(delta, 0.05))
	_update_camera(delta)


func step(dt: float) -> void:
	if state != "play":
		for u in squad:
			u.step(dt)
		for h in hostages:
			h.step(dt)
		return
	time += dt
	for s in squad:
		s.step(dt)
	if tank:
		tank.step(dt)
		if tank.occupied:
			for s in squad:
				if s.boarded:
					s.position = tank.position
	for e in enemies:
		e.step(dt)
	for h in hostages:
		h.step(dt)
	_step_forts(dt)
	_step_bullets(dt)
	_step_throws(dt)
	_step_rockets(dt)
	_step_pickups()
	if autoplay:
		_bot(dt)
	_obj_cd -= dt
	if _obj_cd <= 0.0:
		_obj_cd = 0.2
		_check_end()
	for p in pickups:
		var b: Node3D = p["node"].get_node("Body")
		b.rotation.y += dt * 1.5
		b.position.y = 0.05 + sin(time * 3.0 + p["cell"].x) * 0.05
	for f in forts:
		if f["alive"]:
			var flag: Node3D = f["node"].get_node("Flag")
			flag.rotation.y = sin(time * 4.0 + f["cell"].x) * 0.25


func _step_forts(dt: float) -> void:
	var center := squad_center()
	for i in forts.size():
		var f: Dictionary = forts[i]
		if not f["alive"]:
			continue
		f["cd"] -= dt
		if f["cd"] > 0.0:
			continue
		f["cd"] = FORT_SPAWN_EVERY
		var fpos := cell_center(f["cell"])
		if fpos.distance_to(center) > 14.0:
			continue
		var count := 0
		for e in enemies:
			if e.alive and e.fort_id == i:
				count += 1
		if count >= FORT_MAX_ALIVE:
			continue
		var c := nearest_walkable(f["cell"] + Vector2i(0, 1))
		var e := _spawn_enemy("rifle", c, Color(0.96, 0.50, 0.18))
		e.fort_id = i
		e.saw_player = true
		e.alert_pos = center
		e.react_cd = 1.0
		e.model.scale = Vector3(0.1, 0.1, 0.1)


func fire_bullet(src: Unit, at: Vector3, spread: float, dmg: float) -> void:
	var from := src.position + Vector3(0, 0.43, 0)
	var dir := at - src.position
	dir.y = 0.0
	dir = dir.normalized().rotated(Vector3.UP, rng.randf_range(-spread, spread))
	var mi := MeshInstance3D.new()
	mi.mesh = _bullet_mesh_p
	var col := Color(1.0, 0.95, 0.55) if src.team == Unit.Team.PLAYER else Color(1.0, 0.45, 0.25)
	var bmat := Models.unshaded(col * 1.8)
	bmat.albedo_color.a = 1.0
	mi.material_override = bmat
	Fx.muzzle_flash(world, from + dir * 0.35, dir)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = from + dir * 0.3
	mi.look_at_from_position(mi.position, mi.position + dir + Vector3(0, 0.0001, 0), Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	world.add_child(mi)
	bullets.append({"pos": from + dir * 0.3, "vel": dir * BULLET_SPEED, "team": src.team, "dmg": dmg, "life": src.fire_range / BULLET_SPEED + 0.15, "node": mi, "src": src})
	var snd := "shot" if src.team == Unit.Team.PLAYER else ("sniper" if src.kind == "sniper" else "enemy_shot")
	Sfx.play(snd, -9.0 if src.team == Unit.Team.PLAYER else -11.0, 0.1)


func _step_bullets(dt: float) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		var hit := false
		var substeps := 2
		for _k in substeps:
			b["pos"] += b["vel"] * dt / substeps
			b["life"] -= dt / substeps
			var c := cell_of(b["pos"])
			if blocks_sight(c) or get_cell(c) == Cell.TURRET and b["team"] == Unit.Team.ENEMY:
				hit = true
				Fx.spark(world, b["pos"])
				break
			var victims: Array = enemies if b["team"] == Unit.Team.PLAYER else player_targets()
			for v in victims:
				if not v.is_targetable():
					continue
				var r := 0.55 if v.kind in ["tank", "turret"] else 0.3
				var d := Vector2(v.position.x - b["pos"].x, v.position.z - b["pos"].z).length()
				if d < r:
					hit = true
					v.hurt(b["dmg"], b["src"].position if is_instance_valid(b["src"]) else b["pos"])
					if not v.alive and b["team"] == Unit.Team.PLAYER:
						_credit_kill(b["src"])
					Fx.spark(world, b["pos"], Color(1, 0.6, 0.3) if v.team == Unit.Team.ENEMY else Color(0.6, 1, 0.6))
					if v.team == Unit.Team.PLAYER:
						Sfx.play("hurt", -8.0)
					break
			if hit:
				break
		if hit or b["life"] <= 0.0:
			b["node"].queue_free()
			bullets.remove_at(i)
		else:
			b["node"].position = b["pos"]
		i -= 1


func _credit_kill(src) -> void:
	if src == null or not is_instance_valid(src):
		return
	if src.kind == "tank":
		# Shared between the crew
		for s in squad:
			if s.boarded and s.alive:
				kills[s.roster_idx] = kills.get(s.roster_idx, 0) + 1
				return
	if src.roster_idx >= 0:
		kills[src.roster_idx] = kills.get(src.roster_idx, 0) + 1


# ----------------------------------------------------------------- explosives

func nearest_thrower(to: Vector3) -> Unit:
	var best: Unit = null
	var bd := 1e9
	for s in squad:
		if s.alive and not s.boarded:
			var d: float = s.position.distance_to(to)
			if d < bd:
				bd = d
				best = s
	return best


func throw_grenade(to: Vector3) -> bool:
	if grenades <= 0:
		return false
	var s := nearest_thrower(to)
	if s == null:
		return false
	var from := s.position + Vector3(0, 0.5, 0)
	var d := to - s.position
	d.y = 0.0
	if d.length() > GRENADE_RANGE:
		to = s.position + d.normalized() * GRENADE_RANGE
	grenades -= 1
	s.face_dir = d.normalized()
	var node := Models.part(world, Models.sphere_mesh(0.09), Models.mat(Color(0.25, 0.38, 0.22), 0.4), from)
	var dist := from.distance_to(to)
	throws.append({"from": from, "to": Vector3(to.x, 0.08, to.z), "t": 0.0, "dur": 0.45 + dist * 0.05, "h": 1.2 + dist * 0.15, "node": node, "src": s})
	Sfx.play("throw", -4.0)
	stats_changed.emit()
	return true


func _step_throws(dt: float) -> void:
	var i := throws.size() - 1
	while i >= 0:
		var g: Dictionary = throws[i]
		g["t"] += dt
		var k := clampf(g["t"] / g["dur"], 0.0, 1.0)
		var p: Vector3 = g["from"].lerp(g["to"], k)
		p.y += sin(k * PI) * g["h"]
		g["node"].position = p
		g["node"].rotation.x += dt * 12.0
		if k >= 1.0:
			g["node"].queue_free()
			throws.remove_at(i)
			explode(g["to"], GRENADE_RADIUS, 5.0, 1, g["src"])
		i -= 1


func fire_rocket(to: Vector3) -> bool:
	if rocket_count <= 0:
		return false
	var s := nearest_thrower(to)
	if s == null:
		return false
	rocket_count -= 1
	_launch(s, to, 12.0, ROCKET_RADIUS, 8.0, 2, UI.ORANGE)
	stats_changed.emit()
	return true


func fire_shell(src: Unit, to: Vector3) -> void:
	_launch(src, to, 13.0, SHELL_RADIUS, 6.0, 1, Color(0.2, 0.2, 0.2))
	Sfx.play("shot", -2.0, 0.02)


func _launch(src: Unit, to: Vector3, speed: float, radius: float, dmg: float, fort_dmg: int, col: Color) -> void:
	var dir := to - src.position
	dir.y = 0.0
	var dist := dir.length()
	dir = dir.normalized()
	src.face_dir = dir
	var start := src.position + Vector3(0, 0.45, 0) + dir * 0.4
	var node := Node3D.new()
	Models.part(node, Models.cyl_mesh(0.05, 0.05, 0.3), Models.mat(col, 0.3, 0.5), Vector3.ZERO, Vector3(90, 0, 0))
	Models.part(node, Models.sphere_mesh(0.07), Models.mat(Color(1, 0.8, 0.3), 0.3, 3.0), Vector3(0, 0, 0.18))
	node.position = start
	world.add_child(node)
	node.look_at(start + dir, Vector3.UP)
	rockets.append({"pos": start, "vel": dir * speed, "life": dist / speed + 0.05, "node": node, "radius": radius, "dmg": dmg, "fort_dmg": fort_dmg, "src": src})
	Sfx.play("throw", -2.0)


func _step_rockets(dt: float) -> void:
	var i := rockets.size() - 1
	while i >= 0:
		var r: Dictionary = rockets[i]
		r["pos"] += r["vel"] * dt
		r["life"] -= dt
		var c := cell_of(r["pos"])
		var boom: bool = r["life"] <= 0.0
		var v := get_cell(c)
		if v == Cell.BLOCK or v == Cell.CRATE or v == Cell.TREE or v == Cell.FORT or v == Cell.TURRET:
			boom = true
		if not boom:
			for e in enemies:
				if e.alive and Vector2(e.position.x - r["pos"].x, e.position.z - r["pos"].z).length() < 0.45:
					boom = true
					break
		if boom:
			r["node"].queue_free()
			rockets.remove_at(i)
			explode(Vector3(r["pos"].x, 0.1, r["pos"].z), r["radius"], r["dmg"], r["fort_dmg"], r["src"])
		else:
			r["node"].position = r["pos"]
		i -= 1


func explode(pos: Vector3, radius: float, dmg: float, fort_dmg: int, src) -> void:
	Fx.explosion(world, pos, radius, debris_color())
	Sfx.play("boom", 0.0)
	shake = maxf(shake, 0.35)
	var pc := cell_of(pos)
	var reach := int(ceil(radius))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := pc + Vector2i(dx, dz)
			if cell_center(c).distance_to(Vector3(pos.x, 0, pos.z)) > radius + 0.3:
				continue
			if crates.has(c):
				var n: Node3D = crates[c]
				crates.erase(c)
				set_cell(c, Cell.FLOOR)
				Fx.explosion(world, cell_center(c), 0.6, Color(0.78, 0.58, 0.34))
				n.queue_free()
	for f in forts:
		if not f["alive"]:
			continue
		if cell_center(f["cell"]).distance_to(Vector3(pos.x, 0, pos.z)) <= radius + 0.5:
			f["hp"] -= fort_dmg
			var node: Node3D = f["node"]
			var tw := node.create_tween()
			tw.tween_property(node, "scale", Vector3(1.12, 0.85, 1.12), 0.08)
			tw.tween_property(node, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
			if f["hp"] <= 0:
				_destroy_fort(f)
			else:
				message.emit("Bunker damaged!", UI.YELLOW)
	var blasted := 0
	for e in enemies.duplicate():
		if not e.alive:
			continue
		var d: float = Vector2(e.position.x - pos.x, e.position.z - pos.z).length()
		if d <= radius:
			var k := 1.0 - d / radius * 0.5
			e.hurt(dmg * k * (2.0 if e.kind == "turret" else 1.0), pos, true)
			if not e.alive:
				_credit_kill(src)
				blasted += 1
	if blasted >= 2 and not demo:
		var calls := ["", "", "Double whammy!", "Triple trouble!", "Mega boom!"]
		message.emit(calls[mini(blasted, 4)], UI.ORANGE)
	for s in player_targets():
		var d2: float = Vector2(s.position.x - pos.x, s.position.z - pos.z).length()
		if d2 <= radius * 0.8:
			s.hurt(dmg * 0.4, pos, true)
	stats_changed.emit()


func _destroy_fort(f: Dictionary) -> void:
	f["alive"] = false
	set_cell(f["cell"], Cell.FLOOR)
	var node: Node3D = f["node"]
	Fx.explosion(world, node.position, 1.6, Color(0.85, 0.8, 0.7))
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(1.3, 0.05, 1.3), 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)
	shake = 0.6
	message.emit("Bunker destroyed!", UI.GREEN)


func _step_pickups() -> void:
	var i := pickups.size() - 1
	while i >= 0:
		var p: Dictionary = pickups[i]
		var pos := cell_center(p["cell"])
		for s in squad_and_tank():
			if s.alive and not s.boarded and (s.kind != "tank" or s.occupied) and s.position.distance_to(pos) < 0.7:
				if p["kind"] == "g":
					grenades += 2
					Fx.float_text(world, pos, "+2 grenades", UI.YELLOW)
				else:
					rocket_count += 1
					Fx.float_text(world, pos, "+1 rocket", UI.ORANGE)
				Sfx.play("pickup")
				p["node"].queue_free()
				pickups.remove_at(i)
				stats_changed.emit()
				break
		i -= 1


# ----------------------------------------------------------------- tank

func request_board() -> void:
	if tank == null or not tank.alive or tank.occupied:
		return
	for s in alive_squad():
		s.focus = null
		s.move_to(tank.position)
	set_meta("boarding", true)


func _check_boarding() -> void:
	if not has_meta("boarding") or tank == null or tank.occupied or not tank.alive:
		return
	for s in alive_squad():
		if s.position.distance_to(tank.position) < 1.3:
			board_tank()
			return


func board_tank() -> void:
	remove_meta("boarding")
	tank.occupied = true
	for s in alive_squad():
		s.boarded = true
		s.stop()
		s.visible = false
	message.emit("All aboard the tank!", UI.GREEN)
	Sfx.play("pickup")
	stats_changed.emit()


func exit_tank() -> void:
	if tank == null or not tank.occupied:
		return
	tank.occupied = false
	tank.stop()
	var crew := squad.filter(func(s): return s.alive and s.boarded)
	var slots := _ring_cells(cell_of(tank.position), crew.size() + 1)
	for i in crew.size():
		var s: Unit = crew[i]
		s.boarded = false
		s.visible = true
		s.position = cell_center(slots[(i + 1) % slots.size()])
	stats_changed.emit()


# ----------------------------------------------------------------- objectives

func objective_status() -> Array:
	var out: Array = []
	for o in data["objectives"]:
		match o:
			"kill_all":
				var left := 0
				for e in enemies:
					if e.alive:
						left += 1
				for f in forts:
					if f["alive"]:
						left += 1
				out.append({"id": o, "text": "Defeat all enemies (%d left)" % left, "done": left == 0})
			"forts":
				var fl := 0
				for f in forts:
					if f["alive"]:
						fl += 1
				out.append({"id": o, "text": "Destroy the bunkers (%d left)" % fl, "done": fl == 0})
			"rescue":
				var saved := 0
				for h in hostages:
					if h.rescued:
						saved += 1
				out.append({"id": o, "text": "Rescue the pilots (%d/%d)" % [saved, hostages.size()], "done": saved == hostages.size()})
			"extract":
				var inside := false
				for s in squad_and_tank():
					if s.alive and not s.boarded and (s.kind != "tank" or s.occupied) and in_extraction(s.position):
						inside = true
				out.append({"id": o, "text": "Reach the landing zone", "done": inside})
	return out


func _check_end() -> void:
	_check_boarding()
	if tank and tank.occupied and not tank.alive:
		pass
	var all_done := true
	for o in objective_status():
		if not o["done"]:
			all_done = false
	if all_done:
		state = "won"
		for s in alive_squad():
			s.stop()
		Sfx.jingle("win")
		ended.emit(true)
		return
	if alive_squad().is_empty():
		state = "lost"
		Sfx.jingle("lose")
		ended.emit(false)


const QUIPS := ["Gotcha!", "Oof!", "Bye bye!", "Down he goes!", "Nailed it!", "Ouch!", "Tango down!", "See ya!", "Boom!"]


func on_unit_died(u: Unit) -> void:
	if u.team == Unit.Team.ENEMY and u.kind in ["rifle", "sniper"] and rng.randf() < 0.4:
		Fx.float_text(world, u.position, QUIPS[rng.randi() % QUIPS.size()], Color(1, 0.95, 0.7))
	if u.team == Unit.Team.PLAYER and u.kind == "soldier":
		losses += 1
		message.emit("%s is down!" % u.display_name, UI.RED)
	elif u.kind == "tank":
		message.emit("The tank is wrecked!", UI.RED)
		Fx.explosion(world, u.position, 1.4)
		var crew := squad.filter(func(s): return s.alive and s.boarded)
		u.occupied = false
		var slots := _ring_cells(cell_of(u.position), crew.size() + 1)
		for i in crew.size():
			var s: Unit = crew[i]
			s.boarded = false
			s.visible = true
			s.position = cell_center(slots[(i + 1) % slots.size()])
			s.hurt(1.0, u.position)
	elif u.kind == "turret":
		var c: Vector2i = u.get_meta("cell")
		set_cell(c, Cell.FLOOR)
		Fx.explosion(world, u.position, 1.2)
	stats_changed.emit()


func on_hostage_found(_h: Unit) -> void:
	Sfx.play("pickup")
	message.emit("Pilot found! Lead them to the landing zone.", UI.YELLOW)


func on_hostage_rescued(h: Unit) -> void:
	Sfx.play("rescue")
	Fx.float_text(world, h.position, "Rescued!", UI.GREEN)
	stats_changed.emit()


func revive_squad() -> void:
	revived = true
	var c := nearest_walkable(cell_of(cell_center(spawn_cell)))
	var slots := _ring_cells(c, squad.size())
	for i in squad.size():
		var s: Unit = squad[i]
		if s.alive:
			continue
		var fresh := Unit.new()
		fresh.setup(self, Unit.Team.PLAYER, "soldier", Game.skin_color())
		fresh.display_name = s.display_name
		fresh.roster_idx = s.roster_idx
		fresh.apply_rank(s.rank)
		fresh.position = cell_center(slots[i])
		world.add_child(fresh)
		squad[i] = fresh
		losses = max(0, losses - 1)
	state = "play"
	cam_focus = squad_center()
	message.emit("Squad revived. Back to it!", UI.GREEN)
	stats_changed.emit()


func star_count() -> int:
	if losses == 0 and not revived and time <= float(data["par"]):
		return 3
	if losses <= 1 and not revived:
		return 2
	return 1


func coins_earned() -> int:
	var k := 0
	for v in kills.values():
		k += v
	return 100 + 50 * star_count() + 10 * k


func survivors_and_dead() -> Array:
	var alive: Array = []
	var dead: Array = []
	for s in squad:
		if s.alive:
			alive.append(s.roster_idx)
		else:
			dead.append(s.roster_idx)
	return [alive, dead]


# =================================================================== input

func command_tap(world_pos: Vector3) -> void:
	if state != "play":
		return
	if mode == "grenade":
		mode = ""
		if throw_grenade(world_pos):
			Fx.tap_marker(world, world_pos, UI.YELLOW)
		stats_changed.emit()
		return
	if mode == "rocket":
		mode = ""
		if fire_rocket(world_pos):
			Fx.tap_marker(world, world_pos, UI.ORANGE)
		stats_changed.emit()
		return
	# Did we tap the tank?
	if tank and tank.alive and not tank.occupied and world_pos.distance_to(tank.position) < 0.9:
		request_board()
		Fx.tap_marker(world, tank.position, UI.GREEN)
		return
	# Did we tap an enemy? Focus fire.
	var best: Unit = null
	var bd := 0.9
	for e in enemies:
		if e.alive:
			var d: float = Vector2(e.position.x - world_pos.x, e.position.z - world_pos.z).length()
			if d < bd:
				bd = d
				best = e
	if best != null:
		if crew_in_tank():
			tank.focus = best
			fire_shell_at(best.position)
		for s in alive_squad():
			s.focus = best
			s.retarget_cd = 0.0
		Fx.tap_marker(world, best.position, UI.RED)
		return
	# Forts: tapping one with no explosive selected focuses the tank cannon.
	for f in forts:
		if f["alive"] and cell_center(f["cell"]).distance_to(Vector3(world_pos.x, 0, world_pos.z)) < 0.9:
			if crew_in_tank():
				fire_shell_at(cell_center(f["cell"]))
			else:
				message.emit("Bunkers need explosives: use a grenade or rocket.", UI.YELLOW)
			Fx.tap_marker(world, cell_center(f["cell"]), UI.RED)
			return
	move_squad(world_pos)
	Fx.tap_marker(world, Vector3(world_pos.x, 0, world_pos.z), Color(1, 1, 1))


func fire_shell_at(p: Vector3) -> void:
	if tank.fire_cd <= 0.0:
		tank.fire_cd = tank.fire_rate
		fire_shell(tank, p)


func move_squad(p: Vector3) -> void:
	if has_meta("boarding"):
		remove_meta("boarding")
	pan_offset = Vector3.ZERO
	if crew_in_tank():
		tank.move_to(p)
		return
	var alive := alive_squad()
	var target := nearest_walkable(cell_of(p))
	var base := cell_center(target) if not walkable_cell(cell_of(p)) else Vector3(p.x, 0, p.z)
	for i in alive.size():
		var s: Unit = alive[i]
		var off := Vector3.ZERO
		if i > 0:
			var a: float = TAU * float(i - 1) / maxf(1.0, alive.size() - 1.0)
			off = Vector3(cos(a), 0, sin(a)) * 0.6
		var dest := base + off
		if not walkable_pos(dest):
			dest = base
		s.move_to(dest)


func _unhandled_input(event: InputEvent) -> void:
	if demo or state != "play" or camera == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and ui_blocks.call(event.position):
			return
		if event.pressed:
			_touches[event.index] = {"start": event.position, "pos": event.position, "t": Time.get_ticks_msec()}
			if _touches.size() == 1:
				_drag_moved = false
			elif _touches.size() == 2:
				_drag_moved = true
				_pinch_start = _pinch_distance()
				_zoom_start = zoom
		else:
			if _touches.has(event.index):
				var t: Dictionary = _touches[event.index]
				_touches.erase(event.index)
				if _touches.is_empty() and not _drag_moved and Time.get_ticks_msec() - t["t"] < 600:
					var wp = screen_to_ground(event.position)
					if wp != null:
						command_tap(wp)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		_touches[event.index]["pos"] = event.position
		if _touches.size() >= 2:
			var d := _pinch_distance()
			if _pinch_start > 1.0:
				zoom = clampf(_zoom_start * _pinch_start / maxf(1.0, d), 0.45, 1.6)
		else:
			var start: Vector2 = _touches[event.index]["start"]
			if start.distance_to(event.position) > 22.0:
				_drag_moved = true
			if _drag_moved:
				var vp := get_viewport().get_visible_rect().size
				var k := 22.0 * zoom / vp.y
				pan_offset -= Vector3(event.relative.x, 0, event.relative.y) * k
				pan_offset = pan_offset.limit_length(14.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.45, 1.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.45, 1.6)


func _pinch_distance() -> float:
	var pts: Array = []
	for k in _touches:
		pts.append(_touches[k]["pos"])
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1])


func screen_to_ground(sp: Vector2):
	var o := camera.project_ray_origin(sp)
	var n := camera.project_ray_normal(sp)
	if absf(n.y) < 0.0001:
		return null
	var t := -o.y / n.y
	if t < 0.0:
		return null
	return o + n * t


func _update_camera(delta: float) -> void:
	var want := squad_center() + pan_offset
	want.x = clampf(want.x, 3.0, W - 3.0)
	want.z = clampf(want.z, 2.0, H - 1.0)
	cam_focus = cam_focus.lerp(want, minf(1.0, delta * 4.0))
	var offset := Vector3(0, 9.2, 8.4) * zoom
	var p := cam_focus + offset
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 1.5)
		p += Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * shake * 0.25
	camera.look_at_from_position(p, cam_focus + Vector3(0, 0, -0.6), Vector3.UP)
	if camera_follow:
		camera_follow.position = Vector3(cam_focus.x, 3.5, cam_focus.z)


# =================================================================== autoplay bot
## A simple bot that plays the mission. Used by the automated level tests and
## for the title-screen demo.

func _bot(dt: float) -> void:
	_bot_cd -= dt
	if _bot_cd > 0.0:
		return
	_bot_cd = 0.5
	var alive := alive_squad()
	if alive.is_empty():
		return
	var c := squad_center()
	# Board the tank if there is one.
	if tank and tank.alive and not tank.occupied:
		if not has_meta("boarding"):
			request_board()
		return
	var actor: Unit = tank if crew_in_tank() else nearest_thrower(c)
	# Explosives on forts and turrets in range
	for f in forts:
		if not f["alive"]:
			continue
		var fp := cell_center(f["cell"])
		var d := fp.distance_to(actor.position)
		if d < 7.5:
			if crew_in_tank():
				if tank.fire_cd <= 0.0 and has_los(tank.position, fp):
					fire_shell_at(fp)
					return
			elif d > GRENADE_RADIUS + 0.6 and grenades > 0:
				throw_grenade(fp)
				_bot_cd = 0.9
				return
			elif rocket_count > 0 and d > ROCKET_RADIUS + 0.6 and has_los(actor.position, fp):
				fire_rocket(fp)
				return
	for e in enemies:
		if e.alive and e.kind == "turret" and rocket_count > 0 and not crew_in_tank():
			var d2: float = e.position.distance_to(actor.position)
			if d2 < 7.5 and d2 > 2.4 and has_los(actor.position, e.position):
				fire_rocket(e.position)
				return
	# Decide where to go next.
	var goal = null
	var status := objective_status()
	var need := {}
	for o in status:
		need[o["id"]] = not o["done"]
	# 1. hostages that are not following yet
	if need.get("rescue", false):
		var following := false
		for h in hostages:
			if not h.rescued and h.follow != null:
				following = true
		var unfound := hostages.filter(func(h): return not h.rescued and h.follow == null)
		if not unfound.is_empty():
			goal = _closest(c, unfound.map(func(h): return h.position))
		elif following:
			goal = cell_center(extraction[0])
	# 2. explosives pickups if forts remain and we have none
	var forts_left := forts.filter(func(f): return f["alive"])
	if goal == null and not forts_left.is_empty() and grenades + rocket_count == 0 and not crew_in_tank() and not pickups.is_empty():
		goal = _closest(c, pickups.map(func(p): return cell_center(p["cell"])))
	# 3. enemies and forts
	if goal == null and (need.get("kill_all", false) or need.get("forts", false)):
		var pts: Array = []
		if need.get("kill_all", false):
			for e in enemies:
				if e.alive:
					pts.append(e.position)
		for f in forts_left:
			pts.append(cell_center(f["cell"]))
		if not pts.is_empty():
			goal = _closest(c, pts)
	# 4. extraction
	if goal == null and need.get("extract", false):
		goal = cell_center(extraction[0])
	if goal != null:
		var any_moving := false
		var lead: Unit = tank if crew_in_tank() else alive[0]
		if not lead.path.is_empty():
			any_moving = true
		var close: bool = lead.position.distance_to(goal) < 4.0 and lead.target != null
		if not any_moving and not close:
			var dest: Vector3 = goal
			move_squad(dest)


func _closest(from: Vector3, pts: Array) -> Vector3:
	var best: Vector3 = pts[0]
	var bd := 1e9
	for p in pts:
		var d := from.distance_to(p)
		if d < bd:
			bd = d
			best = p
	return best
