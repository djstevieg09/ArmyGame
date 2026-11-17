class_name Fx
## Visual effects: explosions, muzzle sparks, debris, tap markers.

static func explosion(parent: Node3D, pos: Vector3, radius: float, debris_color := Color(0.4, 0.4, 0.4)) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	# fireball
	var ball := Models.part(root, Models.sphere_mesh(0.5), Models.mat(Color(1.0, 0.65, 0.2), 0.5, 3.0), Vector3(0, 0.3, 0), Vector3.ZERO, false)
	ball.scale = Vector3.ONE * 0.2
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 1.4, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
	# shock ring on the ground
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	ring.material_override = Models.unshaded(Color(1, 0.9, 0.6), 0.7)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var tw2 := ring.create_tween()
	tw2.tween_property(ring, "scale", Vector3(radius * 2.2, 1, radius * 2.2), 0.35).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(ring, "transparency", 1.0, 0.35)
	# light flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 6.0
	light.omni_range = radius * 3.0
	light.position.y = 0.8
	root.add_child(light)
	var tw3 := light.create_tween()
	tw3.tween_property(light, "light_energy", 0.0, 0.4)
	# smoke puffs and debris
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.one_shot = true
	smoke.explosiveness = 0.95
	smoke.lifetime = 1.1
	smoke.mesh = Models.sphere_mesh(0.18)
	smoke.material_override = Models.mat(Color(0.55, 0.55, 0.58), 0.9, 0.0, 0.8)
	smoke.direction = Vector3.UP
	smoke.spread = 70.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.5
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 2.0
	smoke.damping_max = 3.0
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	smoke.scale_amount_curve = curve
	smoke.position.y = 0.3
	root.add_child(smoke)
	smoke.emitting = true
	var bits := CPUParticles3D.new()
	bits.amount = 18
	bits.one_shot = true
	bits.explosiveness = 1.0
	bits.lifetime = 0.9
	bits.mesh = Models.box_mesh(Vector3(0.08, 0.08, 0.08))
	bits.material_override = Models.mat(debris_color, 0.5)
	bits.direction = Vector3.UP
	bits.spread = 60.0
	bits.initial_velocity_min = 3.0
	bits.initial_velocity_max = 6.0
	bits.gravity = Vector3(0, -14, 0)
	bits.angular_velocity_min = -400
	bits.angular_velocity_max = 400
	bits.position.y = 0.3
	root.add_child(bits)
	bits.emitting = true
	# scorch mark
	var scorch := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 1.3, radius * 1.3)
	q.orientation = PlaneMesh.FACE_Y
	scorch.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.06, 0.04, 0.03, 0.45)
	sm.albedo_texture = Models.soft_circle()
	scorch.material_override = sm
	scorch.position = pos + Vector3(0, 0.012, 0)
	scorch.rotation.y = randf() * TAU
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(scorch)
	var tw4 := scorch.create_tween()
	tw4.tween_interval(6.0)
	tw4.tween_property(scorch, "transparency", 1.0, 2.0)
	tw4.tween_callback(scorch.queue_free)
	var t := parent.get_tree().create_timer(1.6)
	t.timeout.connect(root.queue_free)


static func spark(parent: Node3D, pos: Vector3, color := Color(1, 0.9, 0.5)) -> void:
	var p := CPUParticles3D.new()
	p.amount = 6
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.25
	p.mesh = Models.box_mesh(Vector3(0.04, 0.04, 0.04))
	p.material_override = Models.mat(color, 0.4, 2.0)
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6, 0)
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(0.5)
	t.timeout.connect(p.queue_free)


static func tap_marker(parent: Node3D, pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.38
	ring.mesh = tm
	ring.material_override = Models.unshaded(color, 0.9)
	ring.position = pos + Vector3(0, 0.04, 0)
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
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.outline_size = 10
	l.font_size = 48
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(0, 1.0, 0)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(l.queue_free)
