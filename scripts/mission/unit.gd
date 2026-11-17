class_name Unit
extends Node3D
## One actor on the battlefield: a squad soldier, an enemy, a hostage or a tank.
## The Mission drives every unit through `step()`, so the simulation is
## deterministic and can run headless in tests.

enum Team { PLAYER, ENEMY, HOSTAGE }

var m  # Mission (untyped to avoid a cyclic class reference)
var team := Team.PLAYER
var kind := "soldier"  # soldier, rifle, sniper, turret, hostage, tank
var display_name := ""
var roster_idx := -1
var rank := 0
var hp := 3.0
var max_hp := 3.0
var speed := 3.0
var fire_range := 7.0
var fire_rate := 0.5
var spread := 0.08
var damage := 1.0
var fire_cd := 0.0
var alive := true
var path: PackedVector3Array = PackedVector3Array()
var focus: Unit = null
var target: Unit = null
var retarget_cd := 0.0
var react_cd := 0.0
var saw_player := false
var home := Vector3.ZERO
var alert_pos := Vector3.INF
var repath_cd := 0.0
var follow: Unit = null  # hostage follows this soldier
var rescued := false
var boarded := false  # soldier riding the tank
var occupied := false  # tank has crew
var fort_id := -1  # enemy spawned by this fort
var dead_time := 0.0
var flash := 0.0
var model: Node3D
var body: Node3D
var hop := 0.0
var face_dir := Vector3.FORWARD
var hp_bar: MeshInstance3D
var _hp_bar_fill: MeshInstance3D
var _ring: MeshInstance3D


func setup(mission, t: int, k: String, color: Color) -> void:
	m = mission
	team = t
	kind = k
	match kind:
		"soldier":
			hp = 3.0; speed = 3.1; fire_range = 6.8; fire_rate = 0.45; spread = 0.07; damage = 1.0
			model = Models.soldier(0, "soldier", color)
		"rifle":
			hp = 3.0; speed = 2.2; fire_range = 7.0; fire_rate = 1.1; spread = 0.12; damage = 1.0
			model = Models.soldier(1, "rifle")
		"sniper":
			hp = 2.0; speed = 1.8; fire_range = 10.5; fire_rate = 2.4; spread = 0.035; damage = 2.0
			model = Models.soldier(1, "sniper", Color(0.5, 0.46, 0.38))
		"turret":
			hp = 10.0; speed = 0.0; fire_range = 8.0; fire_rate = 0.85; spread = 0.1; damage = 1.0
			model = Models.turret(1)
		"hostage":
			hp = 999.0; speed = 2.9; fire_range = 0.0
			model = Models.soldier(2)
		"tank":
			hp = 24.0; speed = 2.7; fire_range = 8.0; fire_rate = 1.1; spread = 0.03; damage = 6.0
			model = Models.tank(0)
	max_hp = hp
	add_child(model)
	body = model.get_node_or_null("Body")
	if team == Team.PLAYER and kind == "soldier":
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.24
		tm.outer_radius = 0.3
		_ring.mesh = tm
		_ring.material_override = Models.unshaded(Color(1, 1, 1), 0.55)
		_ring.position.y = 0.03
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	if kind in ["turret", "tank"]:
		_make_hp_bar()


func apply_rank(r: int) -> void:
	rank = r
	fire_rate *= 1.0 - 0.05 * r
	spread *= 1.0 - 0.06 * r
	if r >= 3:
		hp += 1.0
		max_hp = hp


func _make_hp_bar() -> void:
	hp_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.09)
	hp_bar.mesh = q
	hp_bar.material_override = Models.unshaded(Color(0, 0, 0), 0.6)
	hp_bar.position = Vector3(0, 1.1, 0)
	hp_bar.rotation_degrees = Vector3(-60, 0, 0)
	hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hp_bar)
	_hp_bar_fill = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.76, 0.06)
	_hp_bar_fill.mesh = q2
	_hp_bar_fill.material_override = Models.unshaded(UI.GREEN if team == Team.PLAYER else UI.RED)
	_hp_bar_fill.position = Vector3(0, 0, 0.005)
	_hp_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_bar.add_child(_hp_bar_fill)
	hp_bar.visible = false


func xz() -> Vector2:
	return Vector2(position.x, position.z)


func is_targetable() -> bool:
	if not alive or boarded:
		return false
	if kind == "tank" and not occupied:
		return false
	return team != Team.HOSTAGE


func can_shoot() -> bool:
	return alive and not boarded and fire_range > 0.0 and (kind != "tank" or occupied)


func move_to(dest: Vector3) -> void:
	path = m.find_path(position, dest)


func stop() -> void:
	path = PackedVector3Array()


func step(dt: float) -> void:
	if not alive:
		dead_time += dt
		return
	if boarded:
		return
	flash = maxf(0.0, flash - dt)
	fire_cd -= dt
	retarget_cd -= dt
	repath_cd -= dt
	match team:
		Team.PLAYER:
			_player_step(dt)
		Team.ENEMY:
			_enemy_step(dt)
		Team.HOSTAGE:
			_hostage_step(dt)
	_animate(dt)


# ------------------------------------------------------------ behaviour

func _player_step(dt: float) -> void:
	if kind == "tank" and not occupied:
		return
	_follow_path(dt)
	_combat(dt, m.enemy_targets())


func _enemy_step(dt: float) -> void:
	var targets: Array = m.player_targets()
	if retarget_cd <= 0.0:
		retarget_cd = 0.25
		var t := _pick_target(targets, fire_range + 1.0)
		if t != null:
			if not saw_player:
				react_cd = 0.7  # short reaction delay keeps it fair
			saw_player = true
			alert_pos = t.position
			target = t
		else:
			target = null
	if kind == "rifle":
		if target == null and alert_pos != Vector3.INF and repath_cd <= 0.0:
			repath_cd = 1.5
			if alert_pos.distance_to(home) < 9.0:
				move_to(alert_pos)
			else:
				move_to(home)
		elif target != null and position.distance_to(target.position) < fire_range * 0.7:
			stop()
		_follow_path(dt)
	react_cd -= dt
	if react_cd <= 0.0:
		_shoot_at(target)


func _hostage_step(dt: float) -> void:
	if rescued:
		return
	if m.in_extraction(position) and follow != null:
		rescued = true
		follow = null
		stop()
		m.on_hostage_rescued(self)
		return
	if follow == null or not follow.alive or follow.boarded:
		follow = null
		var best: Unit = null
		var bd := 1.3
		for s in m.squad_and_tank():
			if s.alive and not s.boarded and (s.kind != "tank" or s.occupied):
				var d := position.distance_to(s.position)
				if d < bd:
					bd = d
					best = s
		if best != null:
			follow = best
			m.on_hostage_found(self)
	if follow != null and repath_cd <= 0.0:
		repath_cd = 0.4
		if m.in_extraction(follow.position) or (m.squad_in_extraction() and position.distance_to(m.nearest_extraction(position)) < 3.5):
			move_to(m.nearest_extraction(position))
		elif position.distance_to(follow.position) > 1.1:
			move_to(follow.position)
		else:
			stop()
	_follow_path(dt)


func _combat(_dt: float, targets: Array) -> void:
	if not can_shoot():
		return
	if focus != null and (not focus.alive or position.distance_to(focus.position) > fire_range * 1.6):
		focus = null
	if retarget_cd <= 0.0:
		retarget_cd = 0.2
		target = null
		if focus != null and position.distance_to(focus.position) <= fire_range and m.has_los(position, focus.position):
			target = focus
		else:
			target = _pick_target(targets, fire_range)
	_shoot_at(target)


func _pick_target(targets: Array, rng: float) -> Unit:
	var best: Unit = null
	var bd := rng
	for t in targets:
		if t == self or not t.is_targetable():
			continue
		var d := position.distance_to(t.position)
		if d < bd and m.has_los(position, t.position):
			bd = d
			best = t
	return best


func _shoot_at(t: Unit) -> void:
	if t == null or not t.alive or fire_cd > 0.0:
		return
	if position.distance_to(t.position) > fire_range:
		return
	fire_cd = fire_rate * m.rng.randf_range(0.85, 1.15)
	var dir := (t.position - position)
	dir.y = 0.0
	face_dir = dir.normalized()
	if kind == "tank":
		m.fire_shell(self, t.position)
	else:
		m.fire_bullet(self, t.position, spread, damage)


func _follow_path(dt: float) -> void:
	if path.is_empty() or speed <= 0.0:
		return
	var p := path[0]
	var to := p - position
	to.y = 0.0
	var d := to.length()
	var stepd := speed * dt
	if d <= stepd or d < 0.05:
		position = Vector3(p.x, 0.0, p.z)
		path.remove_at(0)
	else:
		var dir := to / d
		var np := position + dir * stepd
		np += m.separation(self) * dt
		if m.walkable_pos(np):
			position = np
		else:
			position += dir * stepd
		if target == null:
			face_dir = dir
	hop += dt * speed * 4.2


func _animate(dt: float) -> void:
	if face_dir.length_squared() > 0.001:
		var want := atan2(-face_dir.x, -face_dir.z)
		if kind == "tank":
			model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, dt * 5.0))
		else:
			model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, dt * 12.0))
	if body:
		if kind in ["soldier", "rifle", "sniper", "hostage"]:
			if alive:
				var moving := not path.is_empty()
				if moving:
					Models.soldier_play(model, "Run", speed / 3.0)
				else:
					Models.soldier_play(model, "Idle", 1.0)
		elif kind == "turret":
			if target != null:
				var d := target.position - position
				body.rotation.y = lerp_angle(body.rotation.y, atan2(-d.x, -d.z), minf(1.0, dt * 6.0))
		elif kind == "tank":
			body.position.y = sin(hop * 2.0) * 0.012
	if kind in ["turret", "tank"]:
		var s := 1.0 + flash * 0.4
		model.scale = Vector3(s, s, s)
	if hp_bar:
		hp_bar.visible = alive and hp < max_hp and (kind != "tank" or occupied)
		_hp_bar_fill.scale.x = clampf(hp / max_hp, 0.0, 1.0)
		_hp_bar_fill.position.x = -0.38 * (1.0 - _hp_bar_fill.scale.x)
	if _ring:
		_ring.visible = alive and not boarded


func hurt(amount: float, from_pos: Vector3, explosive := false) -> void:
	if not alive or team == Team.HOSTAGE or boarded:
		return
	if kind == "tank" and not occupied:
		return
	hp -= amount
	flash = 0.15
	if Game.gore and kind in ["soldier", "rifle", "sniper"]:
		Fx.blood_spray(m.world, position, position - from_pos, 10 if not explosive else 20)
	if team == Team.ENEMY and not saw_player:
		saw_player = true
		react_cd = 0.4
		alert_pos = from_pos
	if hp <= 0.0:
		die(from_pos, explosive)


func die(from_pos: Vector3, explosive := false) -> void:
	alive = false
	stop()
	if _ring:
		_ring.visible = false
	if hp_bar:
		hp_bar.visible = false
	var away := position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	m.on_unit_died(self)
	if kind in ["soldier", "rifle", "sniper"]:
		Models.soldier_stop(model)
		model.rotation.y = atan2(-away.x, -away.z) + PI
		Sfx.play("yelp", -4.0, 0.25)
		var tw := create_tween()
		if explosive:
			# Blown off their feet: a comic cartwheel through the air.
			var land := away * randf_range(1.2, 2.0)
			var spin := randf_range(1.5, 2.5) * TAU * (1 if randf() < 0.5 else -1)
			tw.tween_property(model, "position", land * 0.5 + Vector3(0, randf_range(1.4, 2.2), 0), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(body, "rotation:x", spin, 0.64)
			tw.tween_property(model, "position", land, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(func():
				body.rotation.x = -PI / 2.0
				body.position = Vector3(0, 0.12, 0.35)
				if Game.gore:
					Fx.blood_pool(m.world, position + land, 1.1))
			if Game.gore:
				Fx.gibs(m.world, position, Models.PLAYER_TINT if team == Team.PLAYER else Models.ENEMY_TINT)
		else:
			# No death clip in the rig: freeze the pose and tip the body over backwards.
			tw.tween_property(body, "rotation:x", -PI / 2.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(body, "position", Vector3(0, 0.12, 0.35), 0.45)
			if Game.gore:
				tw.tween_callback(func(): Fx.blood_pool(m.world, position + away * 0.35, 0.9))
		tw.tween_interval(6.0)
		tw.tween_property(model, "position:y", -0.6, 1.2)
	else:
		model.visible = false
