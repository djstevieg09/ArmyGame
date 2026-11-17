extends Node
## Gunfire and explosions are real recordings (CC0, Free Firearm Sound
## Library); UI chirps and the music loop are synthesised at start-up.

const RATE := 22050

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_track := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234
	_streams["shot"] = _wav("rifle", _make_shot())
	_streams["enemy_shot"] = _wav("enemy_rifle", _make_shot(0.7))
	_streams["sniper"] = _wav("sniper", _make_shot(0.5))
	_streams["boom"] = _wav("explosion", _make_boom())
	_streams["pickup"] = _make_chirp([880.0, 1320.0], 0.07)
	_streams["click"] = _make_chirp([660.0], 0.04)
	_streams["win"] = _make_chirp([523.0, 659.0, 784.0, 1046.0], 0.12)
	_streams["lose"] = _make_chirp([392.0, 330.0, 262.0], 0.18)
	_streams["hurt"] = _make_chirp([220.0, 160.0], 0.06)
	_streams["throw"] = _make_whoosh()
	_streams["yelp"] = _make_yelp()
	_streams["rescue"] = _make_chirp([784.0, 988.0, 1175.0], 0.08)
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_streams["win"] = _ogg("win", _streams["win"])
	_streams["lose"] = _ogg("lose", _streams["lose"])
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)
	music("theme")


func _wav(file: String, fallback: AudioStream) -> AudioStream:
	var path := "res://assets/sfx/%s.wav" % file
	if ResourceLoader.exists(path):
		return load(path)
	return fallback


func play(name: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	if not Game.sfx_on or not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


## Switch the soundtrack: "theme" (menus) or "mission". Loops forever.
func music(track: String) -> void:
	if _music_track == track and _music.playing:
		return
	_music_track = track
	var st := _ogg(track, null)
	if st == null:
		return
	st.loop = true
	_music.stream = st
	if Game.music_on and DisplayServer.get_name() != "headless":
		_music.volume_db = -30.0
		_music.play()
		create_tween().tween_property(_music, "volume_db", -6.0, 0.8)


## Duck the music under a jingle, then bring it back.
func jingle(name: String) -> void:
	play(name, 0.0, 0.0)
	if _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -28.0, 0.2)
		tw.tween_interval(3.6)
		tw.tween_property(_music, "volume_db", -6.0, 1.2)


func _ogg(file: String, fallback: AudioStream) -> AudioStream:
	var path := "res://assets/music/%s.ogg" % file
	if ResourceLoader.exists(path):
		return load(path)
	return fallback


func set_music(on: bool) -> void:
	Game.music_on = on
	Game.save_game()
	if on and not _music.playing:
		var t := _music_track
		_music_track = ""
		music(t)
	elif not on:
		_music.stop()


# ------------------------------------------------------------ synthesis

func _to_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


func _make_shot(pitch := 1.0) -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 40.0)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35 * pitch
		var thump := sin(TAU * 140.0 * pitch * t) * exp(-t * 30.0)
		out[i] = (lp * 0.8 + thump * 0.5) * env
	return _to_stream(out)


func _make_boom() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 5.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var sub := sin(TAU * (60.0 - t * 30.0) * t) * exp(-t * 6.0)
		out[i] = (lp * 2.2 + sub * 0.8) * env
	return _to_stream(out)


func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / 0.25)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.05 + t * 0.6)
		out[i] = lp * env * 0.6
	return _to_stream(out)


## A short cartoon "yowch!": a buzzy voice-like tone with a quick pitch drop.
func _make_yelp() -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 520.0 * exp(-t * 4.5) + 170.0 + sin(t * 70.0) * 18.0
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		# two crude formants ("ow") from sine products
		var v := saw * 0.5 + sin(TAU * ph * 3.0) * 0.25 + sin(TAU * ph * 5.0) * 0.12
		var env := minf(1.0, t * 60.0) * clampf((0.32 - t) * 8.0, 0.0, 1.0)
		out[i] = v * env * 0.45
	return _to_stream(out)


func _make_chirp(freqs: Array, note_len: float) -> AudioStreamWAV:
	var per := int(RATE * note_len)
	var out := PackedFloat32Array()
	out.resize(per * freqs.size())
	for k in freqs.size():
		var f: float = freqs[k]
		for i in per:
			var t := float(i) / RATE
			var env := minf(1.0, t * 200.0) * exp(-t * 18.0 / note_len * 0.1)
			var sq := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
			out[k * per + i] = (sin(TAU * f * t) * 0.6 + sq * 0.15) * env * 0.5
	return _to_stream(out)


func _add_tone(out: PackedFloat32Array, f: float, start: float, length: float, amp: float, kind: String) -> void:
	var s0 := int(start * RATE)
	var n := int(length * RATE)
	for i in n:
		var idx := s0 + i
		if idx >= out.size():
			break
		var t := float(i) / RATE
		var env := minf(1.0, t * 300.0) * minf(1.0, (length - t) * 30.0)
		var v := 0.0
		if kind == "tri":
			v = 2.0 * absf(2.0 * fmod(f * t, 1.0) - 1.0) - 1.0
		else:
			env *= exp(-t * 3.0)
			v = sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t) + 0.1 * sin(TAU * f * 3.0 * t)
		out[idx] += v * env * amp


func _add_snare(out: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var n := int(0.08 * RATE)
	for i in n:
		var idx := s0 + i
		if idx >= out.size():
			break
		var t := float(i) / RATE
		out[idx] += _rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * amp
