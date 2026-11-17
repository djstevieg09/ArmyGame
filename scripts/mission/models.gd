class_name Models
## Builds the battlefield's 3D models. Characters come from a rigged, animated
## soldier model; everything else is assembled from primitives wrapped in
## photo-scanned PBR materials (ambientCG, CC0).

static var _mats := {}
static var _meshes := {}
static var _tex := {}
static var _soldier_scene: PackedScene


# ------------------------------------------------------------------ materials

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


## Photo-scanned surface: sand, dirt, mossy, grass, rock, cobble, concrete,
## wood, metal, plaster, brick, asphalt, snow.
static func pbr(surface: String, tint := Color.WHITE, uv := 1.0, world := true, rough_mul := 1.0) -> StandardMaterial3D:
	var key := "pbr|%s|%s|%.3f|%s|%.2f" % [surface, tint.to_html(), uv, world, rough_mul]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex("res://assets/tex/%s_albedo.jpg" % surface)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex("res://assets/tex/%s_normal.jpg" % surface)
	m.normal_scale = 1.0
	m.roughness_texture = tex("res://assets/tex/%s_rough.jpg" % surface)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough_mul
	if world:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(uv, uv, uv)
		m.uv1_triplanar_sharpness = 4.0
	else:
		m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func mat(color: Color, rough := 0.6, emission := 0.0, alpha := 1.0, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f" % [color.to_html(), rough, emission, alpha, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func unshaded(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "u|%s|%.2f" % [color.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func foliage_mat(path: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "fol|%s|%s" % [path, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(path)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.35, 0.1)
	_mats[key] = m
	return m


static var _soft_tex: Texture2D


static func soft_circle() -> Texture2D:
	if _soft_tex == null:
		_soft_tex = tex("res://assets/fx/soft.png")
	return _soft_tex


# ------------------------------------------------------------------ meshes

static func _mesh(key: String, build: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = build.call()
	return _meshes[key]


static func box_mesh(size: Vector3) -> Mesh:
	return _mesh("box%s" % size, func():
		var b := BoxMesh.new()
		b.size = size
		return b)


static func sphere_mesh(r: float, h := -1.0) -> Mesh:
	return _mesh("sph%.3f|%.3f" % [r, h], func():
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0 if h < 0.0 else h
		s.radial_segments = 16
		s.rings = 8
		if h > 0.0 and h < r * 2.0:
			s.is_hemisphere = true
		return s)


static func cyl_mesh(top: float, bottom: float, h: float, seg := 16) -> Mesh:
	return _mesh("cyl%.3f|%.3f|%.3f|%d" % [top, bottom, h, seg], func():
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		return c)


static func capsule_mesh(r: float, h: float) -> Mesh:
	return _mesh("cap%.3f|%.3f" % [r, h], func():
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = h
		c.radial_segments = 12
		c.rings = 4
		return c)


## A lumpy rock: a sphere pushed around by noise.
static func rock_mesh(variant: int) -> Mesh:
	return _mesh("rock%d" % variant, func():
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 18
		s.rings = 10
		var arrays := s.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n := FastNoiseLite.new()
		n.seed = 100 + variant
		n.frequency = 1.6
		for i in verts.size():
			var v := verts[i]
			var k := 1.0 + n.get_noise_3dv(v * 2.0) * 0.45
			v *= k
			v.y = maxf(v.y, -0.05) * 0.75
			verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.generate_normals()
		return st.commit())


## A sandbag: a squashed capsule.
static func sandbag_mesh() -> Mesh:
	return _mesh("sandbag", func():
		var c := CapsuleMesh.new()
		c.radius = 0.11
		c.height = 0.42
		c.radial_segments = 10
		c.rings = 3
		return c)


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, shadows := true, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ characters

const PLAYER_TINT := Color(0.62, 0.78, 0.52)
const ENEMY_TINT := Color(0.55, 0.52, 0.5)
const POW_TINT := Color(1.0, 0.62, 0.25)

## A rigged, animated soldier. Returns the root; the AnimationPlayer is stored
## in metadata "anim". Child "Body" is what death animations tip over.
static func soldier(team: int, kind := "soldier", tint_override = null) -> Node3D:
	if _soldier_scene == null:
		_soldier_scene = load("res://assets/models/soldier.glb")
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var inst: Node3D = _soldier_scene.instantiate()
	inst.scale = Vector3.ONE * 0.56
	# the rig already faces -Z, which is "forward" for units
	body.add_child(inst)
	var tint: Color = PLAYER_TINT if team == 0 else (ENEMY_TINT if team == 1 else POW_TINT)
	if tint_override != null:
		tint = tint_override
	var visor_col := Color(0.3, 1.0, 0.5) if team == 0 else (Color(1.0, 0.18, 0.12) if team == 1 else Color(1, 1, 1))
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var base := m.get_active_material(0)
		if base == null:
			continue
		var nm: StandardMaterial3D = base.duplicate()
		if m.name.to_lower().contains("visor"):
			nm.albedo_color = visor_col
			nm.emission_enabled = true
			nm.emission = visor_col
			nm.emission_energy_multiplier = 1.6 if team != 2 else 0.2
		else:
			nm.albedo_color = tint
		m.material_override = nm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if ap:
		for a in ["Idle", "Run", "Walk"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")
		ap.seek(randf() * 2.0, true)
		root.set_meta("anim", ap)
	# rifle held across the body, pointing forward (-Z)
	if team != 2:
		var gun := _rifle(kind == "sniper")
		gun.rotation_degrees = Vector3(-90, 0, 0)
		gun.position = Vector3(0.09, 0.56, -0.12)
		gun.scale = Vector3.ONE * 1.05
		body.add_child(gun)
	return root


static func _rifle(long := false) -> Node3D:
	var g := Node3D.new()
	var black := mat(Color(0.08, 0.08, 0.09), 0.45, 0.0, 1.0, 0.4)
	var furniture := mat(Color(0.22, 0.2, 0.16), 0.7)
	var l := 0.55 if long else 0.42
	# local axes of the hand bone: +Y runs along the fingers
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(0, 0, 0)
	holder.position = Vector3(0.0, 0.06, 0.03)
	g.add_child(holder)
	part(holder, box_mesh(Vector3(0.035, l, 0.05)), black, Vector3(0, l * 0.3, 0), Vector3.ZERO, false)
	part(holder, box_mesh(Vector3(0.03, 0.12, 0.07)), furniture, Vector3(0, -0.06, -0.02), Vector3.ZERO, false)
	part(holder, box_mesh(Vector3(0.03, 0.05, 0.09)), black, Vector3(0, 0.08, -0.05), Vector3.ZERO, false)
	if long:
		part(holder, cyl_mesh(0.018, 0.018, 0.14), black, Vector3(0, 0.12, 0.05), Vector3.ZERO, false)
	return g


static func soldier_play(root: Node3D, anim: String, speed := 1.0) -> void:
	if not root.has_meta("anim"):
		return
	var ap: AnimationPlayer = root.get_meta("anim")
	if ap.current_animation != anim and ap.has_animation(anim):
		ap.play(anim, 0.2)
	ap.speed_scale = speed


static func soldier_stop(root: Node3D) -> void:
	if root.has_meta("anim"):
		var ap: AnimationPlayer = root.get_meta("anim")
		ap.pause()


# ------------------------------------------------------------------ vehicles

static func tank(team: int) -> Node3D:
	var root := Node3D.new()
	var paint := Color(0.36, 0.42, 0.26) if team == 0 else Color(0.62, 0.55, 0.42)
	var hull_m := pbr("metal", paint, 1.2)
	var dark := pbr("metal", paint.darkened(0.35), 1.2)
	var tread := pbr("asphalt", Color(0.45, 0.45, 0.45), 2.5)
	var steel := mat(Color(0.18, 0.18, 0.17), 0.5, 0.0, 1.0, 0.6)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	for sx in [-1.0, 1.0]:
		part(body, box_mesh(Vector3(0.24, 0.24, 1.25)), tread, Vector3(0.4 * sx, 0.13, 0))
		for i in 5:
			var z := -0.44 + i * 0.22
			part(body, cyl_mesh(0.1, 0.1, 0.06, 14), steel, Vector3(0.53 * sx, 0.12, z), Vector3(0, 0, 90))
		part(body, box_mesh(Vector3(0.3, 0.03, 1.3)), dark, Vector3(0.4 * sx, 0.27, 0))
	# hull with sloped front plate
	part(body, box_mesh(Vector3(0.62, 0.22, 1.0)), hull_m, Vector3(0, 0.32, 0.06))
	part(body, box_mesh(Vector3(0.62, 0.05, 0.36)), hull_m, Vector3(0, 0.36, -0.52), Vector3(-28, 0, 0))
	part(body, box_mesh(Vector3(0.2, 0.08, 0.16)), dark, Vector3(0.2, 0.46, 0.45))
	part(body, box_mesh(Vector3(0.2, 0.08, 0.16)), dark, Vector3(-0.2, 0.46, 0.45))
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 0.45, 0.05)
	body.add_child(turret)
	part(turret, cyl_mesh(0.26, 0.3, 0.17, 8), hull_m, Vector3(0, 0.06, 0.04))
	part(turret, box_mesh(Vector3(0.22, 0.14, 0.14)), dark, Vector3(0, 0.06, -0.26))
	part(turret, cyl_mesh(0.035, 0.04, 0.75, 12), steel, Vector3(0, 0.07, -0.66), Vector3(90, 0, 0))
	part(turret, cyl_mesh(0.05, 0.05, 0.08, 12), steel, Vector3(0, 0.07, -1.02), Vector3(90, 0, 0))
	part(turret, cyl_mesh(0.07, 0.07, 0.04, 12), dark, Vector3(0.1, 0.16, 0.1))
	part(turret, cyl_mesh(0.006, 0.006, 0.6), steel, Vector3(-0.18, 0.4, 0.18))
	var star := part(turret, box_mesh(Vector3(0.12, 0.005, 0.12)), mat(Color(0.9, 0.88, 0.8), 0.6), Vector3(0, 0.152, 0.14), Vector3(0, 45, 0), false)
	star.visible = team == 0
	return root


## Machine-gun nest: a ring of sandbags with a swivelling gun.
static func turret(_team: int) -> Node3D:
	var root := Node3D.new()
	var bag := pbr("sand", Color(0.8, 0.72, 0.55), 2.0)
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.42
		part(root, sandbag_mesh(), bag, p + Vector3(0, 0.1, 0), Vector3(0, -rad_to_deg(a), 90))
		if i % 2 == 0:
			part(root, sandbag_mesh(), bag, p * 0.95 + Vector3(0, 0.27, 0), Vector3(0, -rad_to_deg(a) + 15, 90))
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.32, 0)
	root.add_child(body)
	var steel := mat(Color(0.1, 0.1, 0.1), 0.45, 0.0, 1.0, 0.5)
	part(body, cyl_mesh(0.03, 0.05, 0.25), steel, Vector3(0, -0.12, 0))
	part(body, box_mesh(Vector3(0.1, 0.1, 0.32)), steel, Vector3(0, 0.03, -0.08))
	part(body, cyl_mesh(0.022, 0.022, 0.42), steel, Vector3(0, 0.04, -0.42), Vector3(90, 0, 0))
	part(body, box_mesh(Vector3(0.26, 0.2, 0.02)), pbr("metal", Color(0.35, 0.37, 0.3), 2.0), Vector3(0, 0.08, -0.2))
	var gunner := soldier(1)
	gunner.position = Vector3(0, -0.42, 0.28)
	gunner.scale = Vector3.ONE * 0.95
	body.add_child(gunner)
	return root


## Concrete pillbox bunker that keeps sending out troops.
static func fort(_team: int) -> Node3D:
	var root := Node3D.new()
	var conc := pbr("concrete", Color(0.72, 0.7, 0.64), 1.4)
	var bag := pbr("sand", Color(0.78, 0.7, 0.52), 2.0)
	part(root, cyl_mesh(0.62, 0.7, 0.62, 8), conc, Vector3(0, 0.31, 0))
	part(root, cyl_mesh(0.5, 0.64, 0.14, 8), conc, Vector3(0, 0.68, 0))
	for i in 4:
		var a := TAU * i / 4.0 + PI / 8.0
		part(root, box_mesh(Vector3(0.36, 0.07, 0.06)), mat(Color(0.02, 0.02, 0.02), 0.9), Vector3(cos(a) * 0.66, 0.45, sin(a) * 0.66), Vector3(0, -rad_to_deg(a) + 90, 0), false)
	for i in 9:
		var a2 := PI * 0.15 + PI * 0.7 * i / 8.0
		part(root, sandbag_mesh(), bag, Vector3(cos(a2) * 0.85, 0.1, sin(a2) * 0.85), Vector3(0, -rad_to_deg(a2), 90))
	part(root, cyl_mesh(0.012, 0.012, 0.9), mat(Color(0.3, 0.3, 0.3), 0.4, 0.0, 1.0, 0.8), Vector3(0.3, 1.1, 0))
	var flag := part(root, box_mesh(Vector3(0.34, 0.2, 0.01)), mat(Color(0.7, 0.08, 0.06), 0.8), Vector3(0.48, 1.42, 0))
	flag.name = "Flag"
	part(root, box_mesh(Vector3(0.12, 0.12, 0.012)), mat(Color(0.05, 0.05, 0.05), 0.8), Vector3(0.48, 1.42, 0.008), Vector3(0, 0, 45), false)
	return root


# ------------------------------------------------------------------ scenery

static func block(style: String, seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match style:
		"ruin_brick", "ruin_plaster":
			var surf := "brick" if style == "ruin_brick" else "plaster"
			var tint := Color(1, 1, 1) if surf == "brick" else Color(0.92, 0.86, 0.74)
			var h := rng.randf_range(0.7, 1.4)
			part(root, box_mesh(Vector3(1.0, h, 1.0)), pbr(surf, tint, 1.2), Vector3(0, h / 2.0, 0))
			# broken top edge
			for i in 3:
				var bh := rng.randf_range(0.1, 0.5)
				part(root, box_mesh(Vector3(rng.randf_range(0.2, 0.45), bh, rng.randf_range(0.3, 1.0))), pbr(surf, tint, 1.2), Vector3(rng.randf_range(-0.3, 0.3), h + bh / 2.0, rng.randf_range(-0.2, 0.2)))
			for i in 4:
				var r := part(root, rock_mesh(rng.randi() % 6), pbr(surf, tint.darkened(0.1), 2.0), Vector3(rng.randf_range(-0.6, 0.6), 0.04, rng.randf_range(-0.6, 0.6)))
				r.scale = Vector3.ONE * rng.randf_range(0.15, 0.3)
		"barrier":
			var conc := pbr("concrete", Color(0.8, 0.78, 0.72), 1.6)
			part(root, box_mesh(Vector3(0.95, 0.12, 0.5)), conc, Vector3(0, 0.06, 0))
			part(root, box_mesh(Vector3(0.95, 0.5, 0.22)), conc, Vector3(0, 0.37, 0))
			part(root, box_mesh(Vector3(0.95, 0.06, 0.06)), mat(Color(0.9, 0.7, 0.1), 0.6), Vector3(0, 0.55, 0.12))
		"sandbags":
			var bag := pbr("sand", Color(0.78, 0.7, 0.52), 2.0)
			for row in 3:
				for i in 3:
					part(root, sandbag_mesh(), bag, Vector3(-0.3 + i * 0.3 + (0.15 if row % 2 else 0.0), 0.1 + row * 0.18, rng.randf_range(-0.04, 0.04)), Vector3(0, rng.randf_range(-8, 8), 90))
					part(root, sandbag_mesh(), bag, Vector3(-0.3 + i * 0.3 + (0.15 if row % 2 else 0.0), 0.1 + row * 0.18, 0.25), Vector3(0, rng.randf_range(-8, 8), 90))
		"snowrock":
			_rocks(root, rng, pbr("rock", Color(0.8, 0.8, 0.85), 1.5))
			var cap := part(root, rock_mesh(rng.randi() % 6), pbr("snow", Color.WHITE, 1.5), Vector3(0, 0.42, 0))
			cap.scale = Vector3(0.9, 0.35, 0.9)
		"sandrock":
			_rocks(root, rng, pbr("rock", Color(1.0, 0.82, 0.62), 1.5))
		_:
			_rocks(root, rng, pbr("rock", Color(0.85, 0.85, 0.82), 1.5))
	return root


static func _rocks(root: Node3D, rng: RandomNumberGenerator, m: Material) -> void:
	var big := part(root, rock_mesh(rng.randi() % 6), m, Vector3(0, 0.0, 0), Vector3(0, rng.randf() * 360, 0))
	big.scale = Vector3(rng.randf_range(1.1, 1.3), rng.randf_range(0.9, 1.3), rng.randf_range(1.1, 1.3))
	for i in 2:
		var s := part(root, rock_mesh(rng.randi() % 6), m, Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45)), Vector3(0, rng.randf() * 360, 0))
		s.scale = Vector3.ONE * rng.randf_range(0.3, 0.55)


static func tree(style: String, seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := pbr("wood", Color(0.42, 0.33, 0.25), 3.0)
	var s := rng.randf_range(0.85, 1.25)
	match style:
		"pine", "pine_snow":
			part(root, cyl_mesh(0.06 * s, 0.1 * s, 0.6 * s), bark, Vector3(0, 0.3 * s, 0))
			var needles := mat(Color(0.16, 0.3, 0.16), 0.9)
			needles.albedo_texture = tex("res://assets/tex/pine.jpg")
			needles.albedo_color = Color(1, 1, 1)
			for i in 4:
				var y := (0.5 + i * 0.42) * s
				var r := (0.75 - i * 0.16) * s
				part(root, cyl_mesh(0.0, r, 0.6 * s, 12), needles, Vector3(0, y, 0), Vector3(0, rng.randf() * 90, 0))
				if style == "pine_snow":
					part(root, cyl_mesh(0.0, r * 0.82, 0.32 * s, 12), pbr("snow", Color.WHITE, 2.0), Vector3(0, y + 0.18 * s, 0))
		"palm":
			var lean := Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
			var trunk := Node3D.new()
			trunk.rotation_degrees = lean
			root.add_child(trunk)
			for i in 6:
				part(trunk, cyl_mesh(0.065 * s, 0.08 * s, 0.32 * s, 8), bark, Vector3(0, (0.16 + i * 0.3) * s, 0))
			var top := Vector3(0, 1.85 * s, 0)
			var fm := foliage_mat("res://assets/tex/frond.png")
			for i in 9:
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(1.3 * s, 0.4 * s)
				qm.center_offset = Vector3(0.65 * s, 0, 0)
				q.mesh = qm
				q.material_override = fm
				q.position = top
				q.rotation = Vector3(deg_to_rad(90 + rng.randf_range(-10, 10)), TAU * i / 9.0, deg_to_rad(-rng.randf_range(15, 35)))
				trunk.add_child(q)
		"bush":
			_canopy(root, Vector3(0, 0.28 * s, 0), Vector3(0.42, 0.3, 0.42) * s, 9, rng, Color(0.95, 1.0, 0.85))
		"dead":
			part(root, cyl_mesh(0.04, 0.09, 1.3 * s, 8), bark, Vector3(0, 0.65 * s, 0), Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
			for i in 3:
				part(root, cyl_mesh(0.015, 0.035, 0.6 * s, 6), bark, Vector3(0, (0.7 + i * 0.2) * s, 0), Vector3(rng.randf_range(30, 60), i * 120, 0))
		"drums":
			for i in 3:
				var col := Color(0.25, 0.3, 0.2) if i % 2 == 0 else Color(0.55, 0.15, 0.1)
				part(root, cyl_mesh(0.17, 0.17, 0.5, 14), pbr("metal", col, 3.0), Vector3(-0.2 + (i % 2) * 0.38, 0.25, -0.15 + i * 0.16))
		_:
			# broadleaf / jungle tree: trunk, a couple of limbs, clustered leaf cards
			var tall := 1.25 if style == "jungle" else 1.0
			part(root, cyl_mesh(0.07 * s, 0.13 * s, 1.1 * s * tall, 8), bark, Vector3(0, 0.55 * s * tall, 0))
			for i in 2:
				part(root, cyl_mesh(0.025 * s, 0.05 * s, 0.6 * s, 6), bark, Vector3(0, 0.95 * s * tall, 0), Vector3(rng.randf_range(30, 50), i * 180 + rng.randf_range(-30, 30), 0))
			var tint := Color(0.85, 1.0, 0.8) if style != "jungle" else Color(0.7, 1.0, 0.65)
			_canopy(root, Vector3(0, 1.45 * s * tall, 0), Vector3(0.75, 0.55, 0.75) * s, 22, rng, tint)
	return root


## Leaf canopy: a dark solid core wrapped in outward-facing leaf-cluster cards.
static func _canopy(root: Node3D, center: Vector3, radii: Vector3, count: int, rng: RandomNumberGenerator, tint: Color) -> void:
	var core := part(root, sphere_mesh(1.0), mat(Color(0.09, 0.15, 0.06) * Color(tint.r, tint.g, tint.b), 0.95), center, Vector3.ZERO, true, radii * 0.72)
	core.name = "Core"
	var fm := foliage_mat("res://assets/tex/leafcluster.png", tint)
	var fm2 := foliage_mat("res://assets/tex/leafcluster_dark.png", tint)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var p := center + dir * radii * rng.randf_range(0.55, 0.9)
		var card := MeshInstance3D.new()
		card.mesh = q
		card.material_override = fm if dir.y > -0.1 else fm2
		root.add_child(card)
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var b := Basis.looking_at(-dir, up).rotated(dir, rng.randf() * TAU)
		card.transform = Transform3D(b.scaled(Vector3.ONE * radii.x * rng.randf_range(1.1, 1.5)), p)


static func crate(seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if rng.randf() < 0.4:
		# oil drums
		for i in 2:
			part(root, cyl_mesh(0.2, 0.2, 0.6, 16), pbr("metal", Color(0.6, 0.18, 0.1) if i == 0 else Color(0.3, 0.36, 0.22), 3.0), Vector3(-0.2 + i * 0.4, 0.3, rng.randf_range(-0.15, 0.15)))
	else:
		var w := pbr("wood", Color(0.48, 0.5, 0.36), 1.0)
		part(root, box_mesh(Vector3(0.75, 0.6, 0.75)), w, Vector3(0, 0.3, 0), Vector3(0, rng.randf_range(-12, 12), 0))
		part(root, box_mesh(Vector3(0.45, 0.35, 0.45)), w, Vector3(0.1, 0.78, 0.05), Vector3(0, rng.randf_range(-30, 30), 0))
	return root


static func pickup(kind: String) -> Node3D:
	var root := Node3D.new()
	var spin := Node3D.new()
	spin.name = "Body"
	root.add_child(spin)
	var olive := pbr("metal", Color(0.33, 0.38, 0.22), 3.0)
	part(spin, box_mesh(Vector3(0.5, 0.26, 0.32)), olive, Vector3(0, 0.15, 0))
	part(spin, box_mesh(Vector3(0.52, 0.04, 0.34)), mat(Color(0.95, 0.75, 0.15) if kind == "g" else Color(0.95, 0.35, 0.15), 0.5, 0.8), Vector3(0, 0.2, 0))
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.orientation = PlaneMesh.FACE_Y
	glow.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = soft_circle()
	gm.albedo_color = Color(1.0, 0.8, 0.3, 0.5) if kind == "g" else Color(1.0, 0.45, 0.2, 0.5)
	glow.material_override = gm
	glow.position.y = 0.02
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	return root


## Landing zone: painted helipad with green marker smoke.
static func extraction_marker() -> Node3D:
	var root := Node3D.new()
	var pad := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.9)
	q.orientation = PlaneMesh.FACE_Y
	pad.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = tex("res://assets/fx/helipad.png")
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.9
	pad.material_override = pm
	pad.position.y = 0.02
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pad)
	root.add_child(Fx.smoke_column(Color(0.35, 0.9, 0.45, 0.55), 0.9))
	return root
