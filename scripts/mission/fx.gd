class_name Fx
## Combat effects: fireballs, smoke, debris, muzzle flashes, impacts, decals.

static var _cache := {}


static func _sprite_mat(path: String, additive := false, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [path, additive, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Models.tex(path)
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	_cache[key] = m
	return m


static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / max(1, cols.size() - 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _particles(parent: Node3D, pos: Vector3, amount: int, lifetime: float, mat: Material, size: float, pm: ParticleProcessMaterial, one_shot := true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.process_material = pm
	p.draw_pass_1 = _quad(size)
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 10, 12))
	parent.add_child(p)
	p.emitting = true
	if one_shot:
		var t := parent.get_tree().create_timer(lifetime + 0.6)
		t.timeout.connect(p.queue_free)
	return p


static func explosion(parent: Node3D, pos: Vector3, radius: float, debris_color := Color(0.4, 0.38, 0.33)) -> void:
	var tree := parent.get_tree()
	# fireball
	var fpm := ParticleProcessMaterial.new()
	fpm.direction = Vector3.UP
	fpm.spread = 80.0
	fpm.initial_velocity_min = 1.0 * radius
	fpm.initial_velocity_max = 2.5 * radius
	fpm.gravity = Vector3(0, 1.5, 0)
	fpm.damping_min = 3.0
	fpm.damping_max = 5.0
	fpm.scale_min = 0.6 * radius
	fpm.scale_max = 1.3 * radius
	fpm.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.25, 1.0), Vector2(1, 0.7)])
	fpm.color_ramp = _ramp([Color(1.0, 0.95, 0.7, 1), Color(1.0, 0.55, 0.15, 1), Color(0.5, 0.15, 0.05, 0.7), Color(0.1, 0.08, 0.06, 0)])
	fpm.angle_min = -180
	fpm.angle_max = 180
	_particles(parent, pos + Vector3(0, 0.2, 0), 20, 0.7, _sprite_mat("res://assets/fx/smoke.png", true), 1.0, fpm)
	# smoke plume
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 35.0
	spm.initial_velocity_min = 0.8
	spm.initial_velocity_max = 2.0
	spm.gravity = Vector3(0.25, 0.9, 0)
	spm.damping_min = 1.0
	spm.damping_max = 2.0
	spm.scale_min = 0.8 * radius
	spm.scale_max = 1.6 * radius
	spm.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	spm.color_ramp = _ramp([Color(0.25, 0.23, 0.21, 0.0), Color(0.22, 0.2, 0.18, 0.85), Color(0.35, 0.33, 0.31, 0.5), Color(0.5, 0.5, 0.5, 0)])
	spm.angle_min = -180
	spm.angle_max = 180
	spm.angular_velocity_min = -30
	spm.angular_velocity_max = 30
	_particles(parent, pos + Vector3(0, 0.3, 0), 16, 3.2, _sprite_mat("res://assets/fx/smoke.png"), 1.0, spm)
	# debris and dirt
	var dpm := ParticleProcessMaterial.new()
	dpm.direction = Vector3.UP
	dpm.spread = 55.0
	dpm.initial_velocity_min = 3.5
	dpm.initial_velocity_max = 7.0
	dpm.gravity = Vector3(0, -16, 0)
	dpm.scale_min = 0.5
	dpm.scale_max = 1.4
	dpm.angular_velocity_min = -600
	dpm.angular_velocity_max = 600
	var deb := GPUParticles3D.new()
	deb.amount = 26
	deb.lifetime = 1.2
	deb.one_shot = true
	deb.explosiveness = 1.0
	deb.process_material = dpm
	deb.draw_pass_1 = Models.box_mesh(Vector3(0.06, 0.05, 0.08))
	deb.material_override = Models.mat(debris_color, 0.9)
	deb.position = pos + Vector3(0, 0.2, 0)
	deb.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 8, 12))
	parent.add_child(deb)
	deb.emitting = true
	tree.create_timer(1.8).timeout.connect(deb.queue_free)
	# flash of light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 8.0
	light.omni_range = radius * 4.0
	light.position = pos + Vector3(0, 1.0, 0)
	parent.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)
	scorch(parent, pos, radius * 1.4)


static func scorch(parent: Node3D, pos: Vector3, size: float) -> void:
	var d := Decal.new()
	d.texture_albedo = Models.tex("res://assets/fx/scorch.png")
	d.size = Vector3(size, 1.0, size)
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.rotation.y = randf() * TAU
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	parent.add_child(d)
	var tw := d.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(d.queue_free)


## A continuous column of coloured smoke (landing zones, burning wrecks).
static func smoke_column(color: Color, rate := 1.0) -> GPUParticles3D:
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 12.0
	spm.initial_velocity_min = 0.6
	spm.initial_velocity_max = 1.2
	spm.gravity = Vector3(0.35, 0.4, 0.1)
	spm.scale_min = 0.5
	spm.scale_max = 0.9
	spm.scale_curve = _curve([Vector2(0, 0.3), Vector2(1, 2.2)])
	var c0 := Color(color.r, color.g, color.b, 0.0)
	var c1 := color
	var c2 := Color(color.r, color.g, color.b, 0.0)
	spm.color_ramp = _ramp([c0, c1, c1.lerp(c2, 0.5), c2])
	spm.angle_min = -180
	spm.angle_max = 180
	spm.angular_velocity_min = -20
	spm.angular_velocity_max = 20
	var p := GPUParticles3D.new()
	p.amount = int(18 * rate)
	p.lifetime = 4.0
	p.process_material = spm
	p.draw_pass_1 = _quad(1.0)
	p.material_override = _sprite_mat("res://assets/fx/smoke.png")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	p.position.y = 0.2
	p.emitting = true
	return p


static func fire(parent: Node3D, pos: Vector3, size := 1.0) -> void:
	var fpm := ParticleProcessMaterial.new()
	fpm.direction = Vector3.UP
	fpm.spread = 15.0
	fpm.initial_velocity_min = 0.5
	fpm.initial_velocity_max = 1.2
	fpm.gravity = Vector3(0, 1.0, 0)
	fpm.scale_min = 0.3 * size
	fpm.scale_max = 0.6 * size
	fpm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.1)])
	fpm.color_ramp = _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.4, 0.1, 0.02, 0)])
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fpm.emission_sphere_radius = 0.2 * size
	var p := _particles(parent, pos, 16, 0.8, _sprite_mat("res://assets/fx/smoke.png", true), 1.0, fpm, false)
	p.name = "Fire"
	var smoke := smoke_column(Color(0.12, 0.11, 0.1, 0.75), 0.8)
	smoke.position = pos + Vector3(0, 0.4, 0)
	parent.add_child(smoke)


static func muzzle_flash(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.38, 0.38)
	q.mesh = qm
	var m: StandardMaterial3D
	if _cache.has("flash"):
		m = _cache["flash"]
	else:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = Models.tex("res://assets/fx/flash.png")
		m.albedo_color = Color(2.0, 1.6, 1.0)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_cache["flash"] = m
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = pos + dir * 0.3
	q.rotation.z = randf() * TAU
	parent.add_child(q)
	var tw := q.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(q.queue_free)


## Gore (only when the player turns it on): a spray of blood droplets.
static func blood_spray(parent: Node3D, pos: Vector3, dir: Vector3, amount := 14) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = (dir.normalized() + Vector3(0, 0.6, 0)).normalized()
	pm.spread = 30.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.12
	pm.color = Color(0.55, 0.03, 0.03)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	var mat := _sprite_mat("res://assets/fx/soft.png", false, Color(0.6, 0.02, 0.02))
	_particles(parent, pos + Vector3(0, 0.5, 0), amount, 0.6, mat, 1.0, pm)


## Gore: a blood pool decal on the ground that fades out after a while.
static func blood_pool(parent: Node3D, pos: Vector3, size := 1.0) -> void:
	var d := Decal.new()
	d.texture_albedo = Models.tex("res://assets/fx/blood.png")
	d.size = Vector3(size, 1.0, size)
	d.position = Vector3(pos.x, 0.0, pos.z)
	d.rotation.y = randf() * TAU
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.scale = Vector3(0.2, 1, 0.2)
	parent.add_child(d)
	var tw := d.create_tween()
	tw.tween_property(d, "scale", Vector3.ONE, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(18.0)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(d.queue_free)


## Gore: chunks thrown by an explosion.
static func gibs(parent: Node3D, pos: Vector3, tint: Color) -> void:
	var meat := Models.mat(Color(0.45, 0.04, 0.04), 0.35)
	var cloth := Models.mat(tint.darkened(0.3), 0.8)
	for i in 7:
		var g := MeshInstance3D.new()
		g.mesh = Models.box_mesh(Vector3.ONE * randf_range(0.06, 0.13))
		g.material_override = meat if i % 2 == 0 else cloth
		g.position = pos + Vector3(0, 0.4, 0)
		parent.add_child(g)
		var v := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.8, 2.2)
		var land := g.position + v + Vector3(0, -0.35, 0)
		land.y = 0.04
		var peak := g.position.lerp(land, 0.5) + Vector3(0, randf_range(0.6, 1.4), 0)
		var tw := g.create_tween()
		var t := randf_range(0.45, 0.7)
		tw.tween_property(g, "position", peak, t * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(g, "rotation", Vector3(randf() * 8, randf() * 8, randf() * 8), t)
		tw.tween_property(g, "position", land, t * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(10.0)
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 1.0)
		tw.tween_callback(g.queue_free)
	blood_spray(parent, pos, Vector3.UP, 30)


static func spark(parent: Node3D, pos: Vector3, color := Color(1, 0.85, 0.5)) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.35
	pm.color_ramp = _ramp([Color(0.55, 0.5, 0.42, 0.8), Color(0.55, 0.5, 0.42, 0.0)])
	_particles(parent, Vector3(pos.x, maxf(0.05, pos.y * 0.3), pos.z), 5, 0.5, _sprite_mat("res://assets/fx/smoke.png"), 1.0, pm)
	if color.r > 0.9 and color.g > 0.8:
		return


static func tap_marker(parent: Node3D, pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.36
	ring.mesh = tm
	ring.material_override = Models.unshaded(color, 0.9)
	ring.position = pos + Vector3(0, 0.05, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(0.3, 1, 0.3), 0.35).from(Vector3(1.4, 1, 1.4)).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "transparency", 1.0, 0.5)
	tw.tween_callback(ring.queue_free)


static func float_text(parent: Node3D, pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.outline_size = 12
	l.font_size = 52
	l.pixel_size = 0.006
	var f = load("res://assets/Oswald.ttf")
	if f:
		l.font = f
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(0, 1.4, 0)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(l.queue_free)
