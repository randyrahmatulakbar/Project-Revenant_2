extends Node3D
## Scene ending (arah jalan: +Z). Belum diuji di Godot.
## Mulai di dasar tangga di belakang gerbang -> naik -> gerbang terbuka -> aula (pencahayaan normal)
## -> lorong depan: ujung lorong sangat terang -> begitu dilewati, mata "menyesuaikan" (eksposur turun
## perlahan dari terlalu terang ke normal) -> dunia luar pabrik -> jalan terus = ending.

@export var font: FontFile
@export_file("*.tscn") var menu_scene: String = "res://menu_world.tscn"

@export_group("Gerbang")
@export var gate_open_z := -37.0           # pemain lewat z ini (naik tangga) = gerbang mulai terbuka
@export var gate_slide := 3.1
@export var gate_time := 2.6

@export_group("Silau saat keluar")
@export var approach_start_z := 2.0        # mulai sedikit memutih di lorong depan
@export var approach_white := 0.25         # putih maksimum sebelum keluar (0..1), kecil = interior tetap terlihat
@export var exit_z := 22.2                 # melewati ini = keluar dari bangunan
@export var glare_exposure := 3.2          # kecerahan sesaat setelah keluar (1 = normal)
@export var adapt_time := 3.4              # lama mata menyesuaikan
@export var flash_white := 0.5             # putih sesaat setelah keluar (0 = tanpa)
@export var engine_auto_exposure := false  # auto exposure engine membuat interior terlalu terang kalau kembali masuk; biarkan mati
@export var hide_on_exit: Array[NodePath] = [^"EndLight", ^"end"]   # panel & sinar ujung lorong, disembunyikan saat keluar

@export_group("Ending")
@export var end_z := 75.0                  # jalan sampai sini di luar = ending
@export var intro_fade := 1.6
@export var whiteout_time := 2.4
@export var hold_time := 3.0              # lama judul "THE END" tampil sebelum credits mulai
@export var credits_speed := 55.0         # kecepatan credits naik (piksel/detik)
@export var end_title := "T H E   E N D"
@export var end_sub := "TERIMA KASIH SUDAH BERMAIN"

# Salinan ENTRIES dari menu_controller.gd. Kalau credits di menu diubah, ubah di sini juga.
const ENTRIES := [
	{"title": "PROJECT REVENANT"},

	{"section": "DIREKSI & DESAIN"},
	{"role": "Game Designer", "name": "Randy Rahmatul Akbar"},

	{"section": "PEMROGRAMAN"},
	{"role": "Gameplay & Systems Programmer", "name": "Randy Rahmatul Akbar"},

	{"section": "LEVEL & LINGKUNGAN"},
	{"role": "Level Designers & Map Artists", "name": "M. Reno Alfian & Laura Aprilianza"},

	{"section": "ARTISTIK, VISUAL & AUDIO"},
	{"role": "UI/UX, 2D Artist & Audio Designer", "name": "Raevan Fadhillah"},

	{"section": "NARRATIVE & STORY"},
	{"role": "Storywriters & Narrative Designers", "name": "Laura Aprilianza & Raevan Fadhillah"},

	{"section": "KONTRIBUSI ASET PIHAK KETIGA"},
	{"sub": "Aset 3D & Lingkungan"},
	{"item": "Kenney.nl (Free 3D Assets & Game Assets)"},
	{"item": "Itch.io Creators (Community Assets)"},
	{"item": "Sketchfab.com Creators (Community Models)"},
	{"item": "Sniffer (REANIMAL) - Drawn out Rips"},
	{"item": "PSX Style Modular Vents - valse kamerplant"},
	{"item": "Grimhound Rig - DM-913"},
	{"item": "Retro Low Poly Monster (PSX) - tiredguygames"},
	{"item": "Silent Hill 1 Monsters - Air Screamer - vinrax"},
	{"item": "PSX Hands Monster (PS2 Style) - petya-petyavich"},
	{"item": "Silent Hill 1 Monsters - Groaner - vinrax"},
	{"item": "Monster PS1 Style - DAELHERI"},
	{"sub": "Audio & Sound Effects"},
	{"item": "YouTube Audio Library"},
	{"item": "Freesound.org & Itch.io Audio Assets"},
	{"item": "UI click sound - Universfield"},
	{"sub": "Font"},
	{"item": "Rajdhani - Indian Type Foundry"},

	{"section": "TERIMA KASIH KHUSUS"},
	{"item": "Guru Pembimbing - Pak Maul & Bu Annisa"},
	{"item": "SMKN 21 Jakarta"},
	{"item": "Komunitas Godot Engine Indonesia"},
]

var _player: CharacterBody3D
var _gate_open := false
var _exited := false
var _ending := false
var _env: Environment
var _attrs: CameraAttributes
var _black: ColorRect
var _white: ColorRect
var _title: Label
var _sub: Label
var _credits_root: Control
var _credits: VBoxContainer


func _ready() -> void:
	_build_overlay()
	create_tween().tween_property(_black, "color:a", 0.0, intro_fade)
	await get_tree().process_frame
	_setup_exposure()


func _setup_exposure() -> void:
	var we := get_node_or_null("Env") as WorldEnvironment
	if we:
		_env = we.environment
		_attrs = we.camera_attributes
	var cam := get_viewport().get_camera_3d()
	if cam:
		if cam.attributes != null:
			_attrs = cam.attributes            # kamera pemain punya atribut sendiri: pakai itu
		elif _attrs != null:
			cam.attributes = _attrs
	if _attrs:
		_attrs.auto_exposure_enabled = false   # interior = pencahayaan normal; baru menyala setelah keluar
		_attrs.exposure_multiplier = 1.0
	else:
		push_warning("EndingController: CameraAttributes tidak ketemu, efek eksposur dilewati")


func _process(_delta: float) -> void:
	if _ending:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if _player == null:
			return
	var z := _player.global_position.z
	if not _gate_open and z > gate_open_z:
		_open_gate()
	if not _gate_open:
		return
	if not _exited:
		_white.color.a = clampf(inverse_lerp(approach_start_z, exit_z, z), 0.0, 1.0) * approach_white
		if z > exit_z:
			_end()
	elif z < exit_z - 0.8:
		_reenter_building()                     # balik ke dalam: kembalikan keadaan interior (normal, bukan terlalu terang)
	elif z > end_z:
		_end()


func _open_gate() -> void:
	_gate_open = true
	get_tree().call_group("sfx", "play", "door")
	var l := get_node_or_null("Door/DoorL") as Node3D
	var r := get_node_or_null("Door/DoorR") as Node3D
	var tw := create_tween().set_parallel(true)
	if l:
		tw.tween_property(l, "position:x", l.position.x - gate_slide, gate_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	if r:
		tw.tween_property(r, "position:x", r.position.x + gate_slide, gate_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# Keluar dari lorong: terlalu terang sesaat, lalu mata menyesuaikan.
func _exit_building() -> void:
	_exited = true
	for p in hide_on_exit:
		var n := get_node_or_null(p) as Node3D
		if n:
			n.visible = false
	if _env:
		_env.fog_enabled = false               # kabut gelap hanya untuk interior
	_white.color.a = flash_white
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_white, "color:a", 0.0, adapt_time * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _attrs:
		_attrs.exposure_multiplier = glare_exposure
		tw.tween_property(_attrs, "exposure_multiplier", 1.0, adapt_time) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		if engine_auto_exposure:
			_attrs.auto_exposure_enabled = true


# Pemain kembali masuk ke lorong dari luar: interior kembali normal dan efek keluar bisa terulang.
func _reenter_building() -> void:
	_exited = false
	for p in hide_on_exit:
		var n := get_node_or_null(p) as Node3D
		if n:
			n.visible = true
	if _env:
		_env.fog_enabled = true
	if _attrs:
		_attrs.auto_exposure_enabled = false
		_attrs.exposure_multiplier = 1.0


func _end() -> void:
	_ending = true
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 1.0, whiteout_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_title, "modulate:a", 1.0, 1.4)
	tw.tween_property(_sub, "modulate:a", 0.85, 1.0)
	tw.tween_interval(hold_time)
	tw.tween_property(_title, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(_sub, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_roll_credits)


# Credits naik dari bawah layar sampai habis di atas, lalu fade hitam -> menu.
func _roll_credits() -> void:
	_credits_root.visible = true
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	var w := minf(vs.x * 0.8, 900.0)
	_credits.size = Vector2(w, _credits.get_combined_minimum_size().y)
	_credits.position = Vector2((vs.x - w) * 0.5, vs.y)
	var dist := vs.y + _credits.size.y
	var tw := create_tween()
	tw.tween_property(_credits, "position:y", -_credits.size.y, dist / maxf(credits_speed, 1.0))
	tw.tween_interval(1.0)
	tw.tween_property(_black, "color:a", 1.0, 1.2)
	tw.tween_callback(_go_menu)


func _go_menu() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu_scene != "" and ResourceLoader.exists(menu_scene):
		get_tree().change_scene_to_file(menu_scene)
	else:
		push_warning("EndingController: menu_scene '%s' tidak ketemu" % menu_scene)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)

	_white = ColorRect.new()
	_white.color = Color(1.0, 0.97, 0.88, 0.0)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_white)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(box)
	_title = _label(end_title, 64, Color(0.16, 0.12, 0.08))
	_sub = _label(end_sub, 22, Color(0.3, 0.24, 0.18))
	box.add_child(_title)
	box.add_child(_sub)

	_credits_root = Control.new()
	_credits_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_root.clip_contents = true
	_credits_root.visible = false
	layer.add_child(_credits_root)
	_credits = _make_credits()
	_credits_root.add_child(_credits)

	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_black)


func _make_credits() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var ink := Color(0.16, 0.12, 0.08)
	var dim := Color(0.3, 0.24, 0.18)
	var red := Color(0.6, 0.15, 0.12)
	for e in ENTRIES:
		if e.has("title"):
			col.add_child(_cr_label(e.title, 56, ink))
		elif e.has("section"):
			col.add_child(_cr_gap(48))
			col.add_child(_cr_label(e.section, 20, red))
		elif e.has("role"):
			col.add_child(_cr_label(e.role, 16, dim))
			col.add_child(_cr_label(e.name, 24, ink))
		elif e.has("sub"):
			col.add_child(_cr_gap(10))
			col.add_child(_cr_label(e.sub, 18, ink))
		elif e.has("item"):
			col.add_child(_cr_label(str(e.item), 16, dim))
	return col


func _cr_label(text: String, size: int, c: Color) -> Label:
	var l := _label(text, size, c)
	l.modulate.a = 1.0
	return l


func _cr_gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.modulate.a = 0.0
	return l
