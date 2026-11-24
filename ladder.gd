extends StaticBody3D
## Tangga yang dipanjat lewat tombol interact.
## Alur: pemain terkunci -> semua UI disembunyikan -> kamera menatap ke atas & naik
## -> layar menggelap menjelang puncak -> pindah ke puncak -> layar terang lagi, UI balik.
##
## Pasang di StaticBody3D (ada CollisionShape3D-nya) yang menutupi tangga.
signal climb_finished   # dipanggil saat pemain sudah mendarat di room & kontrol kembali

## Player.check_interaction() otomatis memanggil interact() dan membaca interact_text.

@export var interact_text: String = "Naik"

## Titik mulai naik (kaki tangga). Panah biru (-Z) harus menghadap tangga. Kosong = mulai dari posisi pemain.
@export var bottom_marker: Marker3D
## Titik puncak tangga: kamera naik sampai sini (layar sudah gelap pas hampir sampai).
@export var top_marker: Marker3D
## TUJUAN: pemain dipindah ke sini saat layar hitam penuh (taruh di atas lantai room).
## Arah -Z (panah biru) Marker3D ini = arah pandang pemain setelah sampai.
@export var room_marker: Marker3D

@export_group("Cutscene")
@export var climb_time: float = 4.0          # detik naik
@export var look_up_deg: float = 18.0        # kamera mendongak (makin kecil makin lurus)
@export var back_off: float = 0.6            # mundur dari tangga (meter) supaya kamera tidak nempel
@export var fade_out_at: float = 0.7         # 0..1, kapan layar mulai gelap (hitam penuh di +0.22)
@export var hold_black: float = 0.25         # detik layar hitam penuh
@export var fade_in_time: float = 0.6
@export var ui_out_time: float = 0.35        # lama HUD geser keluar layar
@export var ui_in_time: float = 0.5          # lama HUD masuk lagi
@export var rung_sway: float = 0.03          # goyangan kamera tiap pijakan (0 = mati)
@export var rungs_per_sec: float = 2.2

var _busy := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _ui_state: Array = []     # [{layer, offset, items: [[node, warna_asli]]}]

var _player: CharacterBody3D
var _head: Node3D
var _cam: Camera3D
var _start: Vector3
var _mount: Vector3
var _top: Vector3
var _end: Vector3
var _yaw0 := 0.0
var _yaw1 := 0.0
var _pitch0 := 0.0
var _pitch_up := 0.0
var _cam0 := Vector3.ZERO


func interact() -> void:
	if _busy:
		return
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p == null or top_marker == null or room_marker == null:
		push_warning("LadderClimb: player (group 'player'), top_marker, atau room_marker belum diisi")
		return
	_begin(p)


func _begin(p: CharacterBody3D) -> void:
	_busy = true
	_player = p
	_head = p.get_node("head")
	_cam = p.get_node("head/Camera3D")
	_ensure_fade()

	# --- kunci pemain ---
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	var prompt = _player.get("interaction_prompt")
	if is_instance_valid(prompt) and prompt.has_method("set_active"):
		prompt.set_active(false, "")

	_hide_ui()

	# --- hitung jalur ---
	_start = _player.global_position
	_mount = bottom_marker.global_position if bottom_marker else _start
	_top = top_marker.global_position
	# mundur menjauhi tangga (berlawanan arah hadap bottom marker)
	if bottom_marker:
		var back: Vector3 = bottom_marker.global_transform.basis.z
		back.y = 0.0
		back = back.normalized() * back_off
		_mount += back
		_top += back
	_end = room_marker.global_position + Vector3.UP * 0.02
	_cam0 = _player.get("camera_start_position")

	# Arah hadap saat naik = arah -Z (panah biru) marker bottom. Putar marker-nya kalau masih kebalik.
	_yaw0 = _head.rotation.y
	_yaw1 = bottom_marker.global_rotation.y if bottom_marker else _yaw0
	_pitch0 = _cam.rotation.x
	_pitch_up = deg_to_rad(look_up_deg)

	var tw := create_tween()
	tw.tween_method(_mount_step, 0.0, 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(_climb_step, 0.0, 1.0, climb_time)
	tw.tween_callback(_arrive)
	tw.tween_interval(hold_black)
	tw.tween_callback(_restore_ui)
	tw.tween_property(_fade_rect, "modulate:a", 0.0, fade_in_time)
	tw.tween_callback(_finish)


# Geser ke kaki tangga, hadap tangga, mulai mendongak.
func _mount_step(k: float) -> void:
	_player.global_position = _start.lerp(_mount, k)
	_head.rotation.y = lerp_angle(_yaw0, _yaw1, k)
	_cam.rotation.x = lerpf(_pitch0, _pitch_up, k)


# Naik dari bawah ke puncak. t = 0..1. Layar mulai gelap di fade_out_at.
func _climb_step(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	var pos := _mount
	pos.y = lerpf(_mount.y, _top.y, e)
	pos.x = lerpf(_mount.x, _top.x, e)
	pos.z = lerpf(_mount.z, _top.z, e)
	_player.global_position = pos

	var s := t * climb_time * rungs_per_sec
	_cam.position = _cam0 + Vector3(sin(s * PI) * rung_sway, absf(sin(s * PI)) * rung_sway * 0.7, 0.0)

	_fade_rect.modulate.a = smoothstep(fade_out_at, fade_out_at + 0.22, t)


# Dipanggil saat layar hitam penuh.
func _arrive() -> void:
	_player.global_position = _end
	_player.velocity = Vector3.ZERO
	_head.rotation.y = room_marker.global_rotation.y
	_cam.rotation.x = 0.0
	_cam.position = _cam0


# HUD geser turun keluar layar (gaya tangan kosong di intro: BACK ease-in), crosshair menciut.
func _hide_ui() -> void:
	_ui_state.clear()
	var off := get_viewport().get_visible_rect().size.y + 40.0
	var tw := create_tween().set_parallel(true)
	for n in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl == _fade_layer or not cl.visible:
			continue
		var st := {"layer": cl, "offset": cl.offset, "items": []}
		if "crosshair" in String(cl.name).to_lower():
			for c in cl.get_children():
				if c is Control:
					c.pivot_offset = c.size / 2.0
					st["items"].append([c, c.scale])
					tw.tween_property(c, "scale", Vector2.ZERO, 0.25) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(cl, "offset", cl.offset + Vector2(0.0, off), ui_out_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_ui_state.append(st)
	tw.chain().tween_callback(_ui_hidden)


func _ui_hidden() -> void:
	for st in _ui_state:
		var cl: CanvasLayer = st["layer"]
		if is_instance_valid(cl):
			cl.visible = false


# HUD masuk lagi dari bawah (agak kebablasan lalu pas), crosshair "nge-lock" dari kecil.
func _restore_ui() -> void:
	var off := get_viewport().get_visible_rect().size.y + 40.0
	var tw := create_tween().set_parallel(true)
	for st in _ui_state:
		var cl: CanvasLayer = st["layer"]
		if not is_instance_valid(cl):
			continue
		cl.visible = true
		if st["items"].size() > 0:
			for it in st["items"]:
				var c: Control = it[0]
				if is_instance_valid(c):
					c.scale = Vector2.ZERO
					tw.tween_property(c, "scale", it[1], 0.3).set_delay(0.25) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			cl.offset = st["offset"] + Vector2(0.0, off)
			tw.tween_property(cl, "offset", st["offset"], ui_in_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _ui_state.clear())


func _finish() -> void:
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	_player.set_process_unhandled_input(true)
	_busy = false
	climb_finished.emit()


func _ensure_fade() -> void:
	if _fade_layer:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 128
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
