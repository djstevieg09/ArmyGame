class_name Models
## Builds every 3D model out of primitive meshes, in a glossy plastic toy style.
## No imported art: everything here is original and generated at runtime.

static var _mats := {}
static var _meshes := {}


static func mat(color: Color, rough := 0.38, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, emission, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = rough
	m.metallic_specular = 0.35
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if rough < 0.6:
		m.rim_enabled = true
		m.rim = 0.12
		m.rim_tint = 0.6
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


static var _soft_tex: Texture2D


## A soft round blob texture, used for scorch marks and shadows.
static func soft_circle() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.8))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


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


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ units

## A plastic toy soldier standing on its little base plate.
## Returns root; child "Body" is the part that hops and leans.
static func soldier(color: Color, kind := "soldier") -> Node3D:
	var root := Node3D.new()
	var dark := color.darkened(0.25)
	var m := mat(color, 0.32)
	var md := mat(dark, 0.36)
	part(root, cyl_mesh(0.2, 0.22, 0.04, 20), md, Vector3(0, 0.02, 0))
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	# legs
	part(body, box_mesh(Vector3(0.09, 0.22, 0.1)), md, Vector3(-0.06, 0.15, 0))
	part(body, box_mesh(Vector3(0.09, 0.22, 0.1)), md, Vector3(0.06, 0.15, 0))
	# torso and belt
	part(body, capsule_mesh(0.11, 0.32), m, Vector3(0, 0.38, 0))
	part(body, cyl_mesh(0.115, 0.115, 0.04), md, Vector3(0, 0.3, 0))
	# head and helmet
	part(body, sphere_mesh(0.085), m, Vector3(0, 0.6, 0))
	var helmet_col := dark if kind != "sniper" else color.lightened(0.2)
	part(body, sphere_mesh(0.105, 0.105), mat(helmet_col, 0.3), Vector3(0, 0.62, 0))
	part(body, cyl_mesh(0.12, 0.12, 0.015), mat(helmet_col, 0.3), Vector3(0, 0.625, 0))
	# arms + rifle pointing forward (-Z is forward)
	part(body, capsule_mesh(0.035, 0.2), m, Vector3(-0.12, 0.42, -0.06), Vector3(70, 0, 10))
	part(body, capsule_mesh(0.035, 0.2), m, Vector3(0.12, 0.42, -0.06), Vector3(70, 0, -10))
	var rifle_len := 0.5 if kind == "sniper" else 0.34
	part(body, box_mesh(Vector3(0.04, 0.05, rifle_len)), mat(dark.darkened(0.3), 0.4), Vector3(0.03, 0.43, -0.12 - rifle_len * 0.3))
	if kind == "medic":
		part(body, box_mesh(Vector3(0.12, 0.12, 0.02)), mat(Color.WHITE), Vector3(0, 0.42, 0.11))
	return root


## A plush teddy bear hostage.
static func hostage() -> Node3D:
	var root := Node3D.new()
	var fur := mat(Color(0.72, 0.50, 0.30), 0.85)
	var light := mat(Color(0.93, 0.80, 0.62), 0.85)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	part(body, sphere_mesh(0.17), fur, Vector3(0, 0.2, 0))
	part(body, sphere_mesh(0.1), light, Vector3(0, 0.2, -0.1))
	part(body, sphere_mesh(0.13), fur, Vector3(0, 0.46, 0))
	part(body, sphere_mesh(0.055), light, Vector3(0, 0.44, -0.11))
	part(body, sphere_mesh(0.05), fur, Vector3(-0.1, 0.57, 0))
	part(body, sphere_mesh(0.05), fur, Vector3(0.1, 0.57, 0))
	part(body, sphere_mesh(0.022), mat(Color(0.05, 0.05, 0.05), 0.2), Vector3(-0.045, 0.49, -0.115))
	part(body, sphere_mesh(0.022), mat(Color(0.05, 0.05, 0.05), 0.2), Vector3(0.045, 0.49, -0.115))
	part(body, sphere_mesh(0.065), fur, Vector3(-0.17, 0.28, 0))
	part(body, sphere_mesh(0.065), fur, Vector3(0.17, 0.28, 0))
	# a little bow tie so you can spot them
	part(body, box_mesh(Vector3(0.14, 0.05, 0.03)), mat(UI.RED, 0.3), Vector3(0, 0.35, -0.12))
	return root


static func tank(color: Color) -> Node3D:
	var root := Node3D.new()
	var m := mat(color, 0.3)
	var md := mat(color.darkened(0.3), 0.35)
	var tread := mat(Color(0.12, 0.12, 0.14), 0.6)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	part(body, box_mesh(Vector3(0.24, 0.22, 1.05)), tread, Vector3(-0.36, 0.13, 0))
	part(body, box_mesh(Vector3(0.24, 0.22, 1.05)), tread, Vector3(0.36, 0.13, 0))
	for i in 4:
		var z := -0.36 + i * 0.24
		part(body, cyl_mesh(0.09, 0.09, 0.26, 12), mat(Color(0.3, 0.3, 0.32)), Vector3(-0.36, 0.12, z), Vector3(0, 0, 90))
		part(body, cyl_mesh(0.09, 0.09, 0.26, 12), mat(Color(0.3, 0.3, 0.32)), Vector3(0.36, 0.12, z), Vector3(0, 0, 90))
	part(body, box_mesh(Vector3(0.56, 0.2, 0.95)), m, Vector3(0, 0.3, 0))
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 0.42, 0.05)
	body.add_child(turret)
	part(turret, cyl_mesh(0.22, 0.25, 0.16, 20), md, Vector3(0, 0.04, 0))
	part(turret, cyl_mesh(0.05, 0.05, 0.55, 12), md, Vector3(0, 0.06, -0.38), Vector3(90, 0, 0))
	part(turret, sphere_mesh(0.07, 0.07), mat(UI.YELLOW, 0.3), Vector3(0.1, 0.12, 0.08))
	return root


static func turret(color: Color) -> Node3D:
	var root := Node3D.new()
	var m := mat(color, 0.3)
	var md := mat(color.darkened(0.35), 0.35)
	part(root, cyl_mesh(0.36, 0.42, 0.22, 20), md, Vector3(0, 0.11, 0))
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.22, 0)
	root.add_child(body)
	part(body, sphere_mesh(0.28, 0.28), m, Vector3(0, 0.0, 0))
	part(body, box_mesh(Vector3(0.1, 0.1, 0.5)), md, Vector3(-0.07, 0.12, -0.32))
	part(body, box_mesh(Vector3(0.1, 0.1, 0.5)), md, Vector3(0.07, 0.12, -0.32))
	part(body, sphere_mesh(0.06), mat(UI.RED, 0.2, 1.5), Vector3(0, 0.24, 0))
	return root


## A toy castle that keeps sending out enemy troops.
static func fort(color: Color, wall: Color) -> Node3D:
	var root := Node3D.new()
	var mw := mat(wall, 0.45)
	var mr := mat(color, 0.32)
	part(root, box_mesh(Vector3(0.86, 0.55, 0.86)), mw, Vector3(0, 0.275, 0))
	for x in [-0.4, 0.4]:
		for z in [-0.4, 0.4]:
			part(root, cyl_mesh(0.16, 0.16, 0.8, 14), mw, Vector3(x, 0.4, z))
			part(root, cyl_mesh(0.0, 0.2, 0.28, 14), mr, Vector3(x, 0.94, z))
	# door and battlements
	part(root, box_mesh(Vector3(0.26, 0.32, 0.04)), mat(Color(0.15, 0.1, 0.08)), Vector3(0, 0.16, 0.44))
	for i in 3:
		part(root, box_mesh(Vector3(0.14, 0.12, 0.86)), mw, Vector3(-0.25 + i * 0.25, 0.6, 0))
	# flag
	part(root, cyl_mesh(0.015, 0.015, 0.7), mat(Color(0.9, 0.9, 0.9)), Vector3(0, 0.9, 0))
	var flag := part(root, box_mesh(Vector3(0.3, 0.18, 0.02)), mr, Vector3(0.16, 1.15, 0))
	flag.name = "Flag"
	return root


# ------------------------------------------------------------------ scenery

static func block(theme: String, c: Color, seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tint := c.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.18)
	match theme:
		"table", "attic":
			# stacked books / storage boxes
			var h := 0.0
			for i in rng.randi_range(2, 3):
				var bh := rng.randf_range(0.18, 0.3)
				var col := Color.from_hsv(rng.randf(), 0.55, 0.8) if theme == "table" else tint
				var b := part(root, box_mesh(Vector3(0.96, bh, 0.96)), mat(col, 0.5), Vector3(0, h + bh / 2.0, 0), Vector3(0, rng.randf_range(-6, 6), 0))
				b.scale = Vector3(rng.randf_range(0.86, 1.0), 1, rng.randf_range(0.86, 1.0))
				h += bh
		"playroom", "carpet", "tiles":
			# alphabet blocks
			var col2 := Color.from_hsv(rng.randf(), 0.6, 0.92)
			part(root, box_mesh(Vector3(0.94, 0.94, 0.94)), mat(col2, 0.35), Vector3(0, 0.47, 0))
			part(root, box_mesh(Vector3(0.5, 0.5, 0.96)), mat(col2.lightened(0.45), 0.35), Vector3(0, 0.47, 0))
			part(root, box_mesh(Vector3(0.96, 0.5, 0.5)), mat(col2.lightened(0.45), 0.35), Vector3(0, 0.47, 0))
		"sand":
			# upturned sand bucket
			part(root, cyl_mesh(0.38, 0.47, 0.7, 20), mat(tint, 0.3), Vector3(0, 0.35, 0))
			part(root, cyl_mesh(0.48, 0.48, 0.05, 20), mat(tint.darkened(0.2), 0.3), Vector3(0, 0.03, 0))
		"garage":
			# toolbox / paint tins
			part(root, box_mesh(Vector3(0.95, 0.5, 0.8)), mat(tint, 0.3), Vector3(0, 0.25, 0))
			part(root, box_mesh(Vector3(0.6, 0.1, 0.1)), mat(Color(0.2, 0.2, 0.2)), Vector3(0, 0.55, 0))
		"bath":
			part(root, box_mesh(Vector3(0.96, 0.6, 0.96)), mat(Color(0.97, 0.98, 1.0), 0.15), Vector3(0, 0.3, 0))
		_:
			# rocks / stones
			var r := part(root, sphere_mesh(0.5), mat(tint, 0.8), Vector3(0, 0.2, 0))
			r.scale = Vector3(1.0, 0.6, 0.9)
	return root


static func plant(theme: String, seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match theme:
		"table", "tiles":
			# mug
			var col := Color.from_hsv(rng.randf(), 0.5, 0.9)
			part(root, cyl_mesh(0.34, 0.32, 0.72, 20), mat(col, 0.2), Vector3(0, 0.36, 0))
			part(root, cyl_mesh(0.3, 0.3, 0.02, 20), mat(Color(0.35, 0.2, 0.1), 0.1), Vector3(0, 0.71, 0))
			var h := part(root, cyl_mesh(0.12, 0.12, 0.06, 12), mat(col, 0.2), Vector3(0.38, 0.4, 0), Vector3(90, 0, 0))
			h.scale = Vector3(1, 1, 1.6)
		"carpet", "playroom", "attic", "garage", "bath":
			# toy rocket / skittle
			var col2 := Color.from_hsv(rng.randf(), 0.6, 0.95)
			part(root, cyl_mesh(0.2, 0.3, 0.6, 16), mat(col2, 0.25), Vector3(0, 0.3, 0))
			part(root, sphere_mesh(0.22), mat(col2, 0.25), Vector3(0, 0.72, 0))
			part(root, cyl_mesh(0.23, 0.23, 0.08, 16), mat(Color.WHITE, 0.25), Vector3(0, 0.52, 0))
		_:
			# shrub in the garden
			var g := Color(0.22, 0.55, 0.22).lerp(Color(0.35, 0.65, 0.25), rng.randf())
			part(root, cyl_mesh(0.06, 0.08, 0.4), mat(Color(0.45, 0.3, 0.18), 0.8), Vector3(0, 0.2, 0))
			part(root, sphere_mesh(0.42), mat(g, 0.7), Vector3(0, 0.62, 0))
			part(root, sphere_mesh(0.3), mat(g.lightened(0.1), 0.7), Vector3(0.18, 0.85, 0.08))
			if rng.randf() < 0.5:
				part(root, sphere_mesh(0.07), mat(Color.from_hsv(rng.randf(), 0.6, 1.0), 0.4), Vector3(-0.25, 0.8, -0.25))
	return root


static func crate(seed: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wood := Color(0.78, 0.58, 0.34).darkened(rng.randf() * 0.12)
	part(root, box_mesh(Vector3(0.8, 0.8, 0.8)), mat(wood, 0.7), Vector3(0, 0.4, 0), Vector3(0, rng.randf_range(-10, 10), 0))
	part(root, box_mesh(Vector3(0.84, 0.12, 0.84)), mat(wood.darkened(0.25), 0.7), Vector3(0, 0.12, 0))
	part(root, box_mesh(Vector3(0.84, 0.12, 0.84)), mat(wood.darkened(0.25), 0.7), Vector3(0, 0.68, 0))
	return root


static func pickup(kind: String) -> Node3D:
	var root := Node3D.new()
	var col := UI.YELLOW if kind == "g" else UI.ORANGE
	var spin := Node3D.new()
	spin.name = "Body"
	root.add_child(spin)
	part(spin, box_mesh(Vector3(0.42, 0.3, 0.42)), mat(Color(0.25, 0.35, 0.22), 0.5), Vector3(0, 0.25, 0))
	part(spin, box_mesh(Vector3(0.44, 0.08, 0.44)), mat(col, 0.3, 0.6), Vector3(0, 0.3, 0))
	if kind == "g":
		part(spin, sphere_mesh(0.09), mat(Color(0.2, 0.3, 0.18), 0.4), Vector3(0, 0.48, 0))
	else:
		part(spin, cyl_mesh(0.04, 0.04, 0.32), mat(UI.ORANGE, 0.3), Vector3(0, 0.48, 0), Vector3(0, 0, 90))
	return root


static func extraction_flag() -> Node3D:
	var root := Node3D.new()
	part(root, cyl_mesh(0.025, 0.025, 1.4), mat(Color(0.9, 0.9, 0.9)), Vector3(0, 0.7, 0))
	var f := part(root, box_mesh(Vector3(0.5, 0.3, 0.02)), mat(UI.GREEN, 0.3, 0.4), Vector3(0.26, 1.25, 0))
	f.name = "Flag"
	return root
