extends SceneTree

## 一次性工具：把 sound/落子音效.mp3 加工成一个「有身体」的落子声。
## 跑出来的 sound/落子音效.wav 就是游戏现在用的那版。
##   "C:/Godot_v4.7.2-stable_win64_console.exe" --path "C:/godot/ai-tset" --script res://tools/make_place_sound.gd
## 跑完记得让编辑器重新导入（或者在项目目录跑一次 --headless --import），
## 否则新的 wav 没有 .import，游戏里 load() 认不出来。
##
## 思路：**保留原始录音那一下撞击**（真实的脆响，这是最有价值的部分），
## 后面接一段合成的木板共鸣。
##
## 为什么必须合成、不能靠放大原文件：原文件 190 毫秒的尾巴全在 -30dB 以下，
## 放大只会把底噪一起放大——"身体"本来就不存在，只能补上去。

const SRC := "res://sound/落子音效.mp3"
const DST := "res://sound/落子音效.wav"

## 共鸣相对撞击的响度。
## 不是随便给的：模式增益之和是 1.79，撞击原始峰值 1.19，
## 想让共鸣**起点**大约只有撞击的三分之一（听起来才是"敲"而不是"嗡"），
## 就得 0.32 左右。给大了会变成一声闷响拖着长尾巴。
const TAIL_GAIN := 0.32
## 归一化目标峰值（留一点余量，别削波）。
const PEAK_TARGET := 0.94
## 判定"有声"的门槛，用来裁掉前后的静音。
const TRIM_THRESHOLD := 0.015
## 共鸣总长、以及它相对撞击延后多久起（让撞击先出来，听起来才是"敲"而不是"嗡"）。
const TAIL_MS := 300.0
const TAIL_START_MS := 3.0

## 木板共鸣的几个模式：{ 频率, 失谐, 增益, 衰减时间常数(秒) }。
## 每个模式用两个稍微错开的频率——单频听起来像电子音，
## 两个频率之间的拍频才有木头那种"糙"的质感。
## 衰减常数决定"尾巴有多长"：最长那个约 0.18 秒。
const MODES: Array = [
	{"hz": 186.0, "detune": 3.0, "gain": 0.62, "decay": 0.180},
	{"hz": 442.0, "detune": 6.0, "gain": 0.50, "decay": 0.135},
	{"hz": 795.0, "detune": 9.0, "gain": 0.34, "decay": 0.095},
	{"hz": 1240.0, "detune": 14.0, "gain": 0.22, "decay": 0.065},
	{"hz": 1860.0, "detune": 20.0, "gain": 0.11, "decay": 0.042},
]

var _cap: AudioEffectCapture = null


func _initialize() -> void:
	_run()


func _run() -> void:
	var main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 6:
		await process_frame

	# 录干声：把播放器接到一条干净的总线上，别经过 Sfx 那条（上面挂着延时）
	var voice: AudioStreamPlayer = main.sfx_players[0]
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, "Rec")
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 5.0
	AudioServer.add_bus_effect(bus_index, _cap)
	voice.bus = "Rec"

	_cap.clear_buffer()
	voice.play()
	await create_timer(1.0).timeout
	var raw := _cap.get_buffer(_cap.get_frames_available())
	var rate := AudioServer.get_mix_rate()
	print("原始录音：", raw.size(), " 帧，混音率 ", rate)

	# 裁出真正有声的那一段
	var first := -1
	var last := -1
	for i: int in raw.size():
		if absf(raw[i].x) > TRIM_THRESHOLD:
			if first < 0:
				first = i
			last = i
	if first < 0:
		print("！录不到声音，中止")
		quit()
		return
	var impact := PackedFloat32Array()
	for i: int in range(first, last + 1):
		impact.append(raw[i].x)
	print("撞击段：", impact.size(), " 帧（",
		"%.1f" % (float(impact.size()) / rate * 1000.0), " 毫秒）")

	# 拼出成品：撞击 + 延后一点起的共鸣
	var tail_frames := int(rate * TAIL_MS / 1000.0)
	var start_frames := int(rate * TAIL_START_MS / 1000.0)
	var total := maxi(impact.size(), start_frames + tail_frames)
	var mixed := PackedFloat32Array()
	mixed.resize(total)
	for i: int in impact.size():
		mixed[i] += impact[i]
	for i: int in tail_frames:
		var t := float(i) / rate
		var value := 0.0
		for mode: Dictionary in MODES:
			var hz: float = mode["hz"]
			var detune: float = mode["detune"]
			var gain: float = mode["gain"]
			var decay: float = mode["decay"]
			# 起音用一小段斜升，免得共鸣开头"啪"一下
			var attack := minf(1.0, t / 0.002)
			var env := exp(-t / decay) * attack
			value += gain * env * (sin(TAU * hz * t) + sin(TAU * (hz + detune) * t)) * 0.5
		mixed[start_frames + i] += value * TAIL_GAIN

	# 归一化到 PEAK_TARGET
	var peak := 0.0
	var impact_peak := 0.0
	for value: float in impact:
		impact_peak = maxf(impact_peak, absf(value))
	var tail_onset := 0.0
	for i: int in mini(tail_frames, int(rate * 0.02)):
		tail_onset = maxf(tail_onset, absf(mixed[start_frames + i] - (
			impact[start_frames + i] if start_frames + i < impact.size() else 0.0)))
	for value: float in mixed:
		peak = maxf(peak, absf(value))
	print("撞击峰值 = ", "%.3f" % impact_peak,
		"   共鸣起点峰值 = ", "%.3f" % tail_onset,
		"   比例 = ", "%.2f" % (tail_onset / maxf(impact_peak, 0.0001)),
		"（想要 0.3 上下）")
	print("归一化前峰值 = ", "%.3f" % peak, "   缩放 = ", "%.3f" % (PEAK_TARGET / maxf(peak, 0.0001)))
	var scale := PEAK_TARGET / maxf(peak, 0.0001)

	var data := PackedByteArray()
	var sum_sq := 0.0
	var above_20 := 0
	for value: float in mixed:
		var v := value * scale
		sum_sq += v * v
		if absf(v) > 0.1:
			above_20 += 1
		var sample := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.append(sample & 0xFF)
		data.append((sample >> 8) & 0xFF)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(rate)
	wav.stereo = false
	wav.data = data
	var err := wav.save_to_wav(DST)
	var rms := sqrt(sum_sq / maxf(1.0, float(mixed.size())))
	print("写成 ", DST, "：err=", err)
	print("  时长 = ", "%.0f" % (float(mixed.size()) / rate * 1000.0), " 毫秒")
	print("  峰值 = ", "%.3f" % (PEAK_TARGET),
		"   有效值 = ", "%.4f" % rms, "  （", "%.1f" % linear_to_db(rms), " dBFS）")
	print("  超过 -20dB 的时长 = ", "%.1f" % (float(above_20) / rate * 1000.0), " 毫秒")
	quit()
