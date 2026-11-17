extends Node
## Gunfire and explosions are real recordings (CC0, Free Firearm Sound
## Library); UI chirps and the music loop are synthesised at start-up.

const RATE := 22050

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
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
	_streams["rescue"] = _make_chirp([784.0, 988.0, 1175.0], 0.08)
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.stream = _make_music()
	_music.volume_db = -12.0
	add_child(_music)
	if Game.music_on and DisplayServer.get_name() != "headless":
		_music.play()


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


func set_music(on: bool) -> void:
	Game.music_on = on
	Game.save_game()
	if on and not _music.playing:
		_music.play()
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


## A short original marching-band loop: snare pattern, bass line and a toy
## glockenspiel melody in C major, 112 bpm, 8 bars.
func _make_music() -> AudioStreamWAV:
	var bpm := 112.0
	var beat := 60.0 / bpm
	var bars := 8
	var total := int(RATE * beat * 4.0 * bars)
	var out := PackedFloat32Array()
	out.resize(total)
	var notes := {"C4": 261.6, "D4": 293.7, "E4": 329.6, "F4": 349.2, "G4": 392.0, "A4": 440.0, "B4": 493.9, "C5": 523.3, "D5": 587.3, "E5": 659.3, "G5": 784.0, "C3": 130.8, "F3": 174.6, "G3": 196.0, "A3": 220.0}
	# melody: [note, start_beat, length_beats]
	var melody := [
		["E5", 0, 1], ["C5", 1, 0.5], ["D5", 1.5, 0.5], ["E5", 2, 1], ["G5", 3, 1],
		["D5", 4, 1], ["B4", 5, 0.5], ["C5", 5.5, 0.5], ["D5", 6, 2],
		["C5", 8, 1], ["A4", 9, 0.5], ["B4", 9.5, 0.5], ["C5", 10, 1], ["E5", 11, 1],
		["D5", 12, 1.5], ["C5", 13.5, 0.5], ["G4", 14, 2],
		["E5", 16, 1], ["E5", 17, 0.5], ["D5", 17.5, 0.5], ["C5", 18, 1], ["G4", 19, 1],
		["A4", 20, 1], ["C5", 21, 1], ["D5", 22, 2],
		["E5", 24, 0.5], ["D5", 24.5, 0.5], ["C5", 25, 1], ["B4", 26, 1], ["D5", 27, 1],
		["C5", 28, 3], ["G4", 31, 1],
	]
	var bass_roots := ["C3", "G3", "A3", "G3", "F3", "C3", "G3", "C3"]
	for i in total:
		out[i] = 0.0
	# bass: root on beats 1 and 3, fifth on 2 and 4 (oom-pah)
	for bar in bars:
		var root: float = notes[bass_roots[bar]]
		for b in 4:
			var f := root if b % 2 == 0 else root * 1.5
			_add_tone(out, f, (bar * 4 + b) * beat, beat * 0.45, 0.22, "tri")
	for m in melody:
		_add_tone(out, notes[m[0]], float(m[1]) * beat, float(m[2]) * beat * 0.92, 0.16, "bell")
	# snare: tight rolls on the off-beats
	for step in bars * 8:
		var accent := 1.0 if step % 2 == 1 else 0.45
		_add_snare(out, step * beat * 0.5, 0.08 * accent)
	return _to_stream(out, true)


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
