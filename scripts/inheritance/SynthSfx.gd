class_name SynthSfx
## Generated sounds so the hazards work without any audio files.

static func _wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var pcm := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

static func crash_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 2.2)
		var punch := exp(-t * 18.0)
		ph += TAU * lerpf(95.0, 28.0, clampf(t / 0.8, 0.0, 1.0)) / rate
		var boom := sin(ph) * punch * 0.9
		var raw := randf_range(-1.0, 1.0)
		lp += 0.14 * (raw - lp)
		var crunch := sin(t * 420.0 + raw * 3.5) * exp(-t * 6.5) * 0.35
		s[i] = lp * 1.3 * env + boom + crunch
	return _wav(s, rate)

## Seamless low howl with slow gusts. Loop it.
static func wind_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 6
	var s := PackedFloat32Array()
	s.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var raw := randf_range(-1.0, 1.0)
		lp1 += 0.05 * (raw - lp1)
		lp2 += 0.35 * (raw - lp2)
		var gust := 0.55 + 0.45 * sin(t * TAU / 6.0) * sin(t * TAU / 3.0 + 1.0)
		s[i] = (lp1 * 2.6 + (lp2 - lp1) * 0.5) * gust * 0.8
	var fade := int(rate * 0.25)
	for i in fade:
		var k := float(i) / fade
		s[n - fade + i] = lerpf(s[n - fade + i], s[i], k)
	return _wav(s, rate, true)

## Rising roar, then a heavy hit.
static func flare_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 3.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var raw := randf_range(-1.0, 1.0)
		lp += lerpf(0.04, 0.5, clampf(t / 0.9, 0.0, 1.0)) * (raw - lp)
		var rise := smoothstep(0.0, 0.9, t) * (1.0 if t < 0.9 else exp(-(t - 0.9) * 1.4))
		ph += TAU * lerpf(70.0, 32.0, clampf((t - 0.9) / 1.0, 0.0, 1.0)) / rate
		var hit := sin(ph) * (exp(-(t - 0.9) * 3.0) if t >= 0.9 else 0.0)
		s[i] = lp * rise * 1.2 + hit * 0.85
	return _wav(s, rate)

static func beep_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		s[i] = sin(t * TAU * 880.0) * exp(-t * 14.0) * 0.6
	return _wav(s, rate)
