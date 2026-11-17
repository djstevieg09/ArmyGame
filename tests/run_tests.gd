extends Node
## Automated level tests. Run with:
##   godot --headless res://tests/test_runner.tscn
## For every mission it checks the map, checks that every objective is
## reachable, then lets the autoplay bot play it (once invulnerable to prove
## it can be finished, once for real to gauge difficulty).

const DT := 1.0 / 30.0
const MAX_TIME := 600.0

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			only = int(a.substr(8)) - 1
	print("== Fireteam Fury level tests ==")
	for i in Levels.count():
		if only >= 0 and i != only:
			continue
		await _test_level(i)
	print("== %s: %d failure(s) ==" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	print("  FAIL: " + msg)


func _roster(n: int) -> Array:
	var r: Array = []
	for k in n:
		r.append({"name": "Test%d" % k, "rank": 0})
	return r


func _test_level(i: int) -> void:
	var d: Dictionary = Levels.get_level(i)
	print("Level %d: %s" % [i + 1, d["name"]])
	var rows: Array = d["map"]
	for z in rows.size():
		if rows[z].length() != rows[0].length():
			_fail("row %d has length %d, expected %d" % [z, rows[z].length(), rows[0].length()])
			return
	var m := Mission.new()
	m.setup(i, _roster(d["squad"]), {"god": true, "autoplay": true})
	get_tree().root.add_child(m)
	await get_tree().process_frame
	# reachability
	var start := m.nearest_walkable(m.spawn_cell)
	var targets: Array = []
	for e in m.enemies:
		targets.append(["enemy " + e.kind, m.cell_of(e.position)])
	for h in m.hostages:
		targets.append(["hostage", m.cell_of(h.position)])
	for p in m.pickups:
		targets.append(["pickup", p["cell"]])
	for c in m.extraction:
		targets.append(["extraction", c])
	for f in m.forts:
		targets.append(["fort", f["cell"]])
	if m.tank:
		targets.append(["tank", m.cell_of(m.tank.position)])
	for t in targets:
		var c: Vector2i = m.nearest_walkable(t[1])
		if m.astar.get_id_path(start, c).is_empty() and c != start:
			_fail("%s at %s is unreachable" % [t[0], t[1]])
	if "rescue" in d["objectives"] and (m.hostages.is_empty() or m.extraction.is_empty()):
		_fail("rescue mission needs hostages and an extraction zone")
	if "extract" in d["objectives"] and m.extraction.is_empty():
		_fail("extract mission needs an extraction zone")
	var res := _simulate(m)
	print("  bot (invulnerable): %s in %.0fs" % ["WON" if res == "won" else res.to_upper(), m.time])
	if res != "won":
		for o in m.objective_status():
			print("    - %s: %s" % [o["text"], "done" if o["done"] else "NOT DONE"])
		for h in m.hostages:
			print("    hostage at %s rescued=%s follow=%s path=%d" % [m.cell_of(h.position), h.rescued, h.follow != null, h.path.size()])
		for s in m.alive_squad():
			print("    soldier at %s path=%d" % [m.cell_of(s.position), s.path.size()])
		_fail("bot could not finish the level")
	m.queue_free()
	await get_tree().process_frame
	# real run for difficulty info
	var m2 := Mission.new()
	m2.setup(i, _roster(d["squad"]), {"autoplay": true, "seed": 7 + i})
	get_tree().root.add_child(m2)
	await get_tree().process_frame
	var res2 := _simulate(m2)
	print("  bot (normal): %s in %.0fs, losses %d, stars %d" % [res2.to_upper(), m2.time, m2.losses, m2.star_count() if res2 == "won" else 0])
	m2.queue_free()
	await get_tree().process_frame


func _simulate(m: Mission) -> String:
	var t := 0.0
	while t < MAX_TIME and m.state == "play":
		m.step(DT)
		t += DT
	return m.state if m.state != "play" else "timeout"
