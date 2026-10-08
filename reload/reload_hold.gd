# reload_hold.gd  (Godot 4.x)
# Pasang di Node2D "ReloadHold" dengan anak-anak INI, URUTAN INI (urutan = urutan gambar):
#   ReloadHold (Node2D)  <- script ini
#   |- Gun    (Sprite2D)
#   |- Slots  (Node2D)   <- script membuat 6 Sprite2D di sini
#   |- Shells (Node2D)   <- selongsong jatuh
#   |- Hand   (Sprite2D)
# Isi 4 export di Inspector: gun_sheet, hand_sheet, slots_atlas, shell_texture.
# Panggil start_with_ammo(peluru_sekarang, peluru_cadangan) saat reload tahan dimulai,
# release() saat tombol dilepas. Dengarkan sinyal round_loaded dan reload_finished.
# Belum saya uji di Godot, jadi cek dulu dan kabari kalau ada error.

extends Node2D

signal reload_finished(bullets: int)
signal round_loaded(total_bullets: int)  # tiap peluru masuk ke silinder

const EMPTY := 0
const SHELL := 1
const BULLET := 2
const CAPACITY := 6  # jumlah lubang silinder (sesuai gambar)

@export_file("*.json") var data_path := "res://reload/reload_hold_data.json"
@export var gun_sheet: Texture2D
@export var hand_sheet: Texture2D
@export var slots_atlas: Texture2D
@export var shell_texture: Texture2D

@onready var gun: Sprite2D = $Gun
@onready var hand: Sprite2D = $Hand
@onready var slots_root: Node2D = $Slots
@onready var shells_root: Node2D = $Shells

# Isi silinder = DATA, bukan gambar. Ubah dari game-mu (jumlah peluru saat ini).
# Contoh: 2 peluru + 4 selongsong bekas tembak.
var cylinder: Array = [BULLET, BULLET, SHELL, SHELL, SHELL, SHELL]
var insert_budget := 99  # sisa peluru cadangan yang boleh dimasukkan

var data: Dictionary
var holding := false
var clip := ""
var clip_time := 0.0
var last_local := -1
var spin := 0.0
var spin_from := 0.0
var spin_to := 0.0
var cur_slot := 0
var slot_nodes: Array = []
var shells: Array = []
var tex_cache := {}


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	print("RH json total_frames=", data.get("total_frames"))
	gun.texture = gun_sheet
	hand.texture = hand_sheet
	for s in [gun, hand]:
		gun.modulate = Color.WHITE
		gun.self_modulate = Color.WHITE
		gun.show_behind_parent = false
		gun.z_index = 0
		gun.material = null
		s.centered = false
		s.hframes = int(data.grid.columns)
		s.vframes = int(data.grid.rows)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in 6:
		var sp := Sprite2D.new()
		sp.centered = true
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slots_root.add_child(sp)
		slot_nodes.append(sp)
	# Frame sekarang 240x180 (60 px ekstra di kiri untuk tangan). Geser semua layer -60 px
	# supaya gun sejajar dengan sprite idle 180x180. Taruh node ReloadHold di posisi
	# pojok kiri-atas sprite idle-mu.
	var pad := float(data.get("canvas_pad_left", 0))
	for n in [gun, hand, slots_root, shells_root]:
		n.position.x = -pad
	set_process(false)
	visible = false


func is_active() -> bool:
	return clip != ""


# Cara utama memulai dari game: kirim isi magazine sekarang + cadangan.
# Silinder diisi otomatis: slot 0..bullets-1 = peluru, sisanya = selongsong bekas tembak.
func start_with_ammo(bullets: int, reserve: int) -> void:
	if clip != "":
		return
	bullets = clampi(bullets, 0, CAPACITY)
	if bullets >= CAPACITY or reserve <= 0:
		return
	cylinder = []
	for i in CAPACITY:
		cylinder.append(BULLET if i < bullets else SHELL)
	insert_budget = reserve
	start_hold()


func start_hold() -> void:
	if clip != "":
		return
	if _first_non_bullet() == -1:
		return  # silinder sudah penuh
	holding = true
	visible = true
	cur_slot = _first_non_bullet()
	spin = 180.0 - 60.0 * cur_slot  # slot kosong pertama menghadap tangan
	spin_from = spin
	spin_to = spin
	print("RH start | gun_sheet=", gun_sheet, " | hand_sheet=", hand_sheet, " | pos=", global_position, " | scale=", scale, " | z=", z_index)
	_begin_clip("open")


func release() -> void:
	holding = false  # dicek di akhir tiap siklus


func _first_non_bullet() -> int:
	for i in 6:
		if cylinder[i] != BULLET:
			return i
	return -1


func _next_empty(from: int) -> int:
	for d in range(1, 7):
		var idx := (from + d) % 6
		if cylinder[idx] == EMPTY:
			return idx
	return -1


func _begin_clip(clip_name: String) -> void:
	clip = clip_name
	clip_time = 0.0
	last_local = -1
	set_process(true)


func _process(delta: float) -> void:
	var c: Dictionary = data.clips[clip]
	var count := int(c.count)
	clip_time += delta * float(data.fps)
	while last_local < int(clip_time) and last_local < count - 1:
		last_local += 1
		_on_frame(last_local)
	_step_shells(delta)
	if clip_time >= float(count):
		_on_clip_end()
		return
	_apply_view(int(clip_time))


func _fd(local: int) -> Dictionary:
	return data.frames[int(data.clips[clip].start) + local]


func _slot_pos(fd: Dictionary, i: int) -> Vector2:
	var t := deg_to_rad(spin + 60.0 * i)
	var v := Vector2(0.6 * float(fd.a) * cos(t), 0.6 * float(fd.b) * sin(t))
	return Vector2(float(fd.cx), float(fd.cy)) + v.rotated(deg_to_rad(float(fd.rot)))


func _slot_tex(state: int, variant: int) -> Texture2D:
	var key := state * 10 + variant
	if not tex_cache.has(key):
		var t := AtlasTexture.new()
		t.atlas = slots_atlas
		t.region = Rect2(variant * 12, state * 12, 12, 12)
		tex_cache[key] = t
	return tex_cache[key]


func _on_frame(local: int) -> void:
	var ev: Dictionary = data.clips[clip].get("events", {})
	if clip == "open" and local == int(ev.get("eject", -1)):
		_eject_shells()
	elif clip == "insert" and local == int(ev.get("commit", -1)):
		_commit_round()


func _eject_shells() -> void:
	var fd := _fd(last_local)
	var params: Array = data.shell.slots
	for k in 6:
		if cylinder[k] != SHELL:
			continue
		var sp := Sprite2D.new()
		sp.texture = shell_texture
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.visible = false
		shells_root.add_child(sp)
		var p := _slot_pos(fd, k)
		sp.position = p
		shells.append({
			"node": sp, "x0": p.x, "y0": p.y,
			"age": -float(k) * float(data.shell.stagger_frames_per_slot),
			"p": params[k],
		})
		cylinder[k] = EMPTY


func _commit_round() -> void:
	cylinder[cur_slot] = BULLET
	insert_budget -= 1
	emit_signal("round_loaded", cylinder.count(BULLET))
	spin_from = spin
	spin_to = spin
	var nxt := _next_empty(cur_slot)
	if nxt != -1 and insert_budget > 0:
		var n := (nxt - cur_slot + 6) % 6
		spin_to = spin_from - 60.0 * n
		cur_slot = nxt


func _apply_view(local: int) -> void:
	if local == 0 and clip == "open":
		print("GUN dbg | frame=", gun.frame, " rect=", gun.get_rect(), " modulate=", gun.modulate, " self_modulate=", gun.self_modulate, " z=", gun.z_index, " behind=", gun.show_behind_parent, " material=", gun.material, " tex=", gun.texture.resource_path)
	var c: Dictionary = data.clips[clip]
	var idx := int(c.start) + local
	gun.frame = idx
	hand.frame = idx
	var fd: Dictionary = data.frames[idx]
	if clip == "insert" and spin_to != spin_from:
		var t0 := float(c.spin_tween[0])
		var t1 := float(c.spin_tween[1])
		var u := clampf((clip_time - t0) / (t1 - t0), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		spin = lerpf(spin_from, spin_to, u)
	slots_root.visible = bool(fd.slots)
	if bool(fd.slots):
		for i in 6:
			var sp: Sprite2D = slot_nodes[i]
			sp.texture = _slot_tex(int(cylinder[i]), int(fd.variant))
			sp.position = _slot_pos(fd, i)


func _step_shells(delta: float) -> void:
	var df := delta * float(data.fps)
	var g := float(data.shell.gravity_px_per_frame2)
	var life := float(data.shell.lifetime_frames)
	for s in shells.duplicate():
		s.age += df
		var a: float = s.age
		var sp: Sprite2D = s.node
		if a < 0.0:
			continue
		if a > life:
			sp.queue_free()
			shells.erase(s)
			continue
		sp.visible = true
		var p: Dictionary = s.p
		sp.position = Vector2(
			float(s.x0) + float(p.vx) * a,
			float(s.y0) + float(p.vy) * a + 0.5 * g * a * a)
		sp.rotation_degrees = float(p.start_angle) + float(p.spin_deg_per_frame) * a


func _on_clip_end() -> void:
	if clip == "insert":
		spin = spin_to
	if clip == "open" or clip == "insert":
		if holding and cylinder.has(EMPTY) and insert_budget > 0:
			_begin_clip("insert")
			spin_from = spin
			spin_to = spin
		else:
			_begin_clip("close")
	else:  # close selesai (frame terakhir = idle frame 0)
		clip = ""
		holding = false
		set_process(false)
		visible = false  # tampilkan lagi sprite idle gun-mu di sini
		emit_signal("reload_finished", cylinder.count(BULLET))
