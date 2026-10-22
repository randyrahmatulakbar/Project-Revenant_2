extends Node
## STYLE METER "SIGNAL". Parry, wallhop, slide, dan kill beruntun menaikkan rank: D C B A S.
## Pasang: tambahkan Node biasa bernama StyleMeter di intro.tscn, pasang script ini. Selesai.
## (CanvasLayer untuk tampilannya dibuat sendiri oleh script.)
##
## Otomatis terbaca:
##   - kill  : sinyal `died` dari setiap musuh (CharacterBody3D). Bonus: di udara, saat slide, jarak dekat.
##   - parry : lewat group "sfx" (parry.gd memanggil sfx "parry" saat berhasil), tanpa ubah parry.gd.
##   - luka  : health_changed milik node Health di player -> poin dipotong, rank bisa turun.
##   - wallhop / slide: player-test.gd memanggil get_tree().call_group("style", "register", "wallhop").
## Event gerak yang diulang-ulang nilainya menurun, jadi harus variatif.

const RANKS := [["D", "COLD"], ["C", "STIRRING"], ["B", "HUNTING"], ["A", "RAVENOUS"], ["S", "REVENANT"]]
const THRESH := [0.0, 50.0, 130.0, 240.0, 380.0]
const MAX_POINTS := 470.0
const COLORS := [Color(0.62, 0.6, 0.57), Color(0.95, 0.92, 0.84), Color(1.0, 0.72, 0.27), Color(1.0, 0.5, 0.2), Color(1.0, 0.3, 0.25)]
# nama -> [poin, label, dikenai penurunan nilai kalau berulang]
const PICKUP_SIGNALS := ["picked_up", "collected", "taken", "pickup", "pickedup", "interacted", "obtained"]
const HEAL := {"kill": 3.0, "parry": 8.0, "point_blank": 4.0, "aerial_kill": 2.0, "slide_kill": 3.0}
const RANK_HEAL := [0.6, 0.9, 1.2, 1.6, 2.0]
const EVENTS := {
	"kill": [22.0, "KILL", false],
	"aerial_kill": [14.0, "AERIAL", false],
	"slide_kill": [16.0, "SLIDE KILL", false],
	"point_blank": [10.0, "POINT BLANK", false],
	"parry": [34.0, "PARRY", true],
	"wallhop": [13.0, "WALLHOP", true],
	"slide": [9.0, "SLIDE", true],
}

@export_group("KILL SWITCH")
## MASTER. Dimatikan = seluruh sistem rank (panel, poin, heal, hasil) tidak jalan sama sekali.
@export var enabled := true
## Butuh `enabled`. Health pulih dari parry / kill; makin tinggi rank makin besar.
@export var heal_enabled := true
## Butuh `enabled`. Kartu hasil muncul setelah semua wave selesai.
@export var results_enabled := true
@export_group("Heal")
@export var heal_scale := 1.0            # pengali besar heal (0.5 = setengah)
@export_group("Hasil")
@export var results_delay := 2.4         # jeda setelah wave terakhir (biar slow-mo selesai dulu)
@export var results_duration := 10.0     # detik kartu tampil sebelum memudar
@export_group("Pengaturan")
@export var font: Font
@export var spawner_node_name := "EnemySpawner"
@export var pickup_node_name := "PistolPickup"
@export var start_on_pickup := true      # false = langsung aktif sejak awal
@export var margin := 28.0
@export var sfx_dir := "res://sfx/"
@export var point_blank_range := 2.6
@export var damage_penalty := 45.0
@export var grace := 2.0                 # detik tanpa event sebelum poin mulai turun
@export_range(0.0, 1.0) var idle_alpha := 0.35   # panel tetap samar-samar kelihatan saat sepi (0 = hilang total)
@export var debug_key := true                # tekan F8 = tes: tambah event PARRY
@export var repeat_decay := 0.6          # pengali tiap pengulangan event gerak dalam 7 detik

var points := 0.0
var _score := 0.0
var _parries := 0
var _damage_hits := 0
var _best_chain := 0
var _play_time := 0.0
var _results_shown := false
var _card: Control
var _hidden_by_pause := false
var _card_age := 0.0
var _heal_warned := false
var _active := false                     # baru aktif setelah pistol diambil
var best_rank := 0
var kills := 0
var _rank := 0
var _idle := 99.0
var _combo := 0
var _combo_t := 99.0
var _recent := {}
var _player: Node
var _last_hp := -1.0
var _t_show := 0.0                       # 0..1 seberapa terlihat panel

var _layer: CanvasLayer
var _panel: Control
var _letter: Label
var _word: Label
var _tag: Label
var _bar_bg: ColorRect
var _bar: ColorRect
var _feed: VBoxContainer
var _font: Font
var _base_pos := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # supaya bisa menyembunyikan HUD saat game di-pause
	if not enabled:
		set_process(false)                # KILL SWITCH: tidak ada yang dibuat / disambung
		set_process_unhandled_input(false)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	add_to_group("style")
	add_to_group("sfx")                  # terima sfx "parry" tanpa mengubah parry.gd
	if font:
		_font = font
	elif ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_font = load("res://font/Rajdhani-Bold.ttf")
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Menlo", "DejaVu Sans Mono", "monospace"])
		_font = sf
	_build()
	await get_tree().process_frame
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	for c in root.find_children("*", "CharacterBody3D", true, false):
		if c.has_node("Health"):
			_player = c
		elif c.has_signal("died"):
			_hook_enemy(c)
	if _player:
		var h: Node = _player.get_node("Health")
		if h.has_signal("health_changed"):
			h.health_changed.connect(_on_health)
	get_tree().node_added.connect(_on_node_added)
	print("StyleMeter siap. player=", _player)
	if _player == null:
		push_warning("StyleMeter: player (CharacterBody3D dengan anak 'Health') tidak ketemu, bonus kill & luka tidak jalan")
	var sp := root.find_child(spawner_node_name, true, false)
	if sp and sp.has_signal("all_cleared"):
		sp.connect("all_cleared", _on_all_cleared)
	if sp and sp.has_signal("wave_started"):
		sp.connect("wave_started", func(_i, _c): start())      # cadangan kalau pickup tidak terdeteksi
	if not start_on_pickup:
		start()
		return
	var pickup := root.find_child(pickup_node_name, true, false)
	if pickup:
		for sname in PICKUP_SIGNALS:
			if pickup.has_signal(sname):
				pickup.connect(sname, start, CONNECT_ONE_SHOT)
		pickup.tree_exiting.connect(_on_pickup_exiting, CONNECT_ONE_SHOT)
	else:
		push_warning("StyleMeter: node '%s' tidak ketemu, aktif saat wave pertama" % pickup_node_name)


## Aktifkan style meter (otomatis dipanggil saat pistol diambil).
func start() -> void:
	_active = true


func _on_pickup_exiting() -> void:
	# tree_exiting juga terjadi saat scene di-reload: abaikan kalau kita ikut hilang
	if not is_inside_tree():
		return                                  # scene sedang diganti (mis. ke main menu)
	var tree := get_tree()
	await tree.process_frame
	if is_inside_tree():
		start()


# ---------- UI ----------
func _lbl(size: int, color: Color, align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	# jangkar kanan-atas: posisi otomatis benar di ukuran layar berapa pun (termasuk saat window/fullscreen berubah)
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.anchor_left = 1.0
	anchor.anchor_right = 1.0
	anchor.anchor_top = 0.0
	anchor.anchor_bottom = 0.0
	anchor.offset_left = -300.0 - margin
	anchor.offset_right = -margin
	anchor.offset_top = margin + 40.0
	anchor.offset_bottom = margin + 40.0 + 190.0
	_layer.add_child(anchor)
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = Vector2(300, 190)
	_panel.position = Vector2.ZERO
	_panel.modulate.a = 0.0
	anchor.add_child(_panel)

	_tag = _lbl(13, Color(0.65, 0.62, 0.58))
	_tag.text = "// STYLE"
	_tag.size = Vector2(300, 18)
	_panel.add_child(_tag)

	_letter = _lbl(92, COLORS[0])
	_letter.text = "D"
	_letter.size = Vector2(300, 100)
	_letter.position = Vector2(0, 8)
	_letter.pivot_offset = Vector2(270, 56)
	_panel.add_child(_letter)

	_word = _lbl(18, COLORS[0])
	_word.text = "C O L D"
	_word.size = Vector2(300, 24)
	_word.position = Vector2(0, 104)
	_panel.add_child(_word)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.12)
	_bar_bg.size = Vector2(220, 4)
	_bar_bg.position = Vector2(80, 134)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = COLORS[0]
	_bar.size = Vector2(0, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)

	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 0)
	_feed.size = Vector2(300, 60)
	_feed.position = Vector2(0, 146)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_panel.add_child(_feed)
	_base_pos = Vector2.ZERO


# ---------- INPUT EVENT ----------
## Dipanggil dari mana saja: get_tree().call_group("style", "register", "parry")
func register(ev: String, mult: float = 1.0) -> void:
	if not enabled or not _active or not EVENTS.has(ev):
		return
	print("StyleMeter: ", ev)
	var def: Array = EVENTS[ev]
	var pts: float = def[0] * mult
	var now := Time.get_ticks_msec() / 1000.0
	if def[2]:
		var arr: Array = _recent.get(ev, [])
		arr = arr.filter(func(x): return now - x < 7.0)
		pts *= pow(repeat_decay, arr.size())
		arr.append(now)
		_recent[ev] = arr
	points = minf(points + pts, MAX_POINTS)
	_score += pts
	if ev == "parry":
		_parries += 1
	_idle = 0.0
	_log("+ %s" % def[1], COLORS[clampi(_rank, 0, 4)])
	_ping()
	_try_heal(ev)


## Menerima sfx dari group "sfx": hanya "parry" yang dipakai.
func play(sfx_name: String = "", _db = 0.0, _pitch = 0.0) -> void:
	if sfx_name == "parry":
		register("parry")


func _on_node_added(n: Node) -> void:
	if n is CharacterBody3D and n != _player and n.has_signal("died"):
		_hook_enemy(n)


func _hook_enemy(e: Node) -> void:
	if e.has_meta("_style_hooked"):
		return
	e.set_meta("_style_hooked", true)
	e.connect("died", _on_enemy_died.bind(e))


func _on_enemy_died(_arg = null, e: Node = null) -> void:
	# bind menaruh e di akhir; sinyal died(enemy) mengirim enemy di depan
	kills += 1
	_combo = _combo + 1 if _combo_t < 3.0 else 1
	_combo_t = 0.0
	_best_chain = maxi(_best_chain, _combo)
	register("kill", 1.0 + minf(0.15 * (_combo - 1), 0.9))
	if _combo >= 3:
		_log("x%d CHAIN" % _combo, Color(0.82, 0.78, 0.7))
	if _player:
		if "is_on_floor" in _player and not _player.is_on_floor():
			register("aerial_kill")
		if "is_sliding" in _player and _player.is_sliding:
			register("slide_kill")
		var ep = e if e is Node3D else (_arg if _arg is Node3D else null)
		if ep and (ep as Node3D).global_position.distance_to((_player as Node3D).global_position) < point_blank_range:
			register("point_blank")


func _on_health(cur: float, _max: float) -> void:
	if _last_hp >= 0.0 and cur < _last_hp:
		points = maxf(0.0, points - damage_penalty)
		_combo = 0
		_damage_hits += 1
		_log("- DAMAGE", Color(1.0, 0.3, 0.25))
		_shake(7.0)
		_sfx("style_down", -4.0)
	_last_hp = cur


func _on_all_cleared() -> void:
	if not enabled or not _active:
		return
	_idle = -3.0                          # panel tetap tampil beberapa detik
	var r: Array = RANKS[best_rank]
	_log("BEST RANK: %s  %s" % [r[0], r[1]], COLORS[best_rank])
	if results_enabled:
		await get_tree().create_timer(results_delay, true, false, true).timeout
		if is_inside_tree():
			_show_results()


# ---------- HEAL ----------
func _try_heal(ev: String) -> void:
	if not heal_enabled or _player == null or not HEAL.has(ev):
		return
	var amt: float = HEAL[ev] * RANK_HEAL[clampi(_rank, 0, 4)] * heal_scale
	var healed := _heal_player(amt)
	if healed > 0.4:
		_log("+ %d HP" % roundi(healed), Color(0.5, 1.0, 0.6))


## Mengembalikan HP yang benar-benar bertambah. Mencoba beberapa nama method/properti umum di node Health.
func _heal_player(amt: float) -> float:
	var h: Node = _player.get_node_or_null("Health")
	if h == null:
		return 0.0
	var cur_name := ""
	var max_name := ""
	for n in ["health", "current_health", "hp", "current"]:
		if n in h:
			cur_name = n
			break
	for n in ["max_health", "max_hp", "maximum", "max"]:
		if n in h:
			max_name = n
			break
	var cur := -1.0
	var mx := -1.0
	if cur_name != "":
		cur = float(h.get(cur_name))
	if max_name != "":
		mx = float(h.get(max_name))
	if cur >= 0.0 and mx > 0.0 and cur >= mx - 0.01:
		return 0.0                                  # sudah penuh
	for m in ["heal", "add_health", "restore", "increase_health", "recover"]:
		if h.has_method(m):
			h.call(m, amt)
			return amt if mx <= 0.0 else minf(amt, mx - cur)
	if cur_name != "" and mx > 0.0:
		var new_hp := minf(cur + amt, mx)
		h.set(cur_name, new_hp)
		if h.has_signal("health_changed"):
			h.emit_signal("health_changed", new_hp, mx)
		return new_hp - cur
	if not _heal_warned:
		_heal_warned = true
		push_warning("StyleMeter: node Health tidak punya method heal / properti health+max_health, heal tidak jalan. Kirim health.gd untuk disambungkan.")
	return 0.0


# ---------- KARTU HASIL ----------
func _fmt_time(s: float) -> String:
	return "%02d:%02d" % [int(s) / 60, int(s) % 60]  # integer division disengaja


## huruf rank menghantam: kilat putih + getar kartu
func _slam(grade: Label) -> void:
	grade.modulate = Color(3.0, 2.6, 2.0, 1.0)
	if best_rank < 3:
		_sfx("style_up", -1.0)
	_shake_card(7.0 + best_rank * 2.5)
	if best_rank == 3:
		_fx_rank(grade, false)
	elif best_rank == 4:
		_fx_rank(grade, true)


# ================= EFEK RANK TINGGI =================
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 c = UV - 0.5;
	float v = smoothstep(0.22, 0.78, length(c));
	COLOR = vec4(1.0, 0.1, 0.06, v * amount);
}
"""


## Titik tengah GLYPH huruf (bukan kotak label) dalam koordinat kartu: dihitung dari metrik font.
func _glyph_center(l: Label) -> Vector2:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var line_h := f.get_height(fs)
	var top := l.position.y + (l.size.y - line_h) * 0.5
	return Vector2(l.position.x + l.size.x * 0.5, top + f.get_ascent(fs) - 0.36 * fs)


func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## A (strong=false): cincin kejut, percikan, huruf terbelah RGB menyatu, sapuan cahaya, aura
## S (strong=true) : semua itu lebih besar + kilat layar, vinyet merah berdenyut, glitch, banner REVENANT
func _fx_rank(grade: Label, strong: bool) -> void:
	if _card == null:
		return
	var col: Color = COLORS[best_rank]
	var gc := _glyph_center(grade)
	var center: Vector2 = _card.global_position + gc
	var fxl := CanvasLayer.new()
	fxl.layer = 71
	add_child(fxl)
	var vp := get_viewport().get_visible_rect().size

	# cincin kejut
	var ring_n := 2 if strong else 1
	for i in ring_n:
		var ring := Ring.new()
		ring.col = col if i != 1 else Color(1, 0.95, 0.85)
		ring.width = 5.0 if strong else 3.0
		ring.position = center
		ring.material = _additive()
		fxl.add_child(ring)
		var rt := create_tween().set_ignore_time_scale(true)
		rt.tween_interval(i * 0.09)
		rt.tween_method(_ring_step.bind(ring, (vp.y * 0.75 if strong else 260.0) * (1.0 + i * 0.35)), 0.0, 1.0, 0.7 + i * 0.1)
		rt.tween_callback(ring.queue_free)

	# percikan
	_sparks(fxl, center, 64 if strong else 48, 520.0 if strong else 420.0, col)

	# huruf pecah RGB lalu menyatu
	for i in 2:
		var g := _lbl(96, Color(1.0, 0.15, 0.2, 0.85) if i == 0 else Color(0.2, 0.9, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.text = grade.text
		g.size = grade.size
		g.pivot_offset = grade.pivot_offset
		g.material = _additive()
		var base_x := grade.position.x
		g.position = grade.position
		_card.add_child(g)
		_card.move_child(g, grade.get_index())
		var dir := -1.0 if i == 0 else 1.0
		var gt := create_tween().set_ignore_time_scale(true)
		if strong:
			gt.tween_method(_ghost_step.bind(g, base_x, dir, 30.0), 0.0, 1.0, 0.8)
		else:
			gt.tween_method(_ghost_step.bind(g, base_x, dir, 22.0), 0.0, 1.0, 0.55)
		gt.tween_callback(g.queue_free)

	# sapuan cahaya turun melewati kartu
	var sw := ColorRect.new()
	sw.color = Color(1.0, 0.95, 0.85, 0.5)
	sw.size = Vector2(380, 4 if not strong else 8)
	sw.material = _additive()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(sw)
	var swt := create_tween().set_ignore_time_scale(true)
	swt.tween_property(sw, "position:y", 300.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	swt.tween_callback(sw.queue_free)

	if strong:
		_s_banner(fxl, vp, col)
	else:
		# banner nama rank melintas di layar
		var word := String(RANKS[best_rank][1])
		var ban := _lbl(78 if strong else 44, col, HORIZONTAL_ALIGNMENT_CENTER)
		ban.text = " ".join(word.split(""))
		ban.size = Vector2(vp.x, 120)
		ban.position = Vector2(0, vp.y * (0.14 if strong else 0.2))
		ban.pivot_offset = ban.size * 0.5
		ban.scale = Vector2.ONE * (1.7 if strong else 1.35)
		ban.modulate.a = 0.0
		fxl.add_child(ban)
		var bt := create_tween().set_ignore_time_scale(true)
		bt.tween_property(ban, "modulate:a", 1.0, 0.12)
		bt.parallel().tween_property(ban, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		bt.tween_interval(1.5 if strong else 0.9)
		bt.tween_property(ban, "modulate:a", 0.0, 0.6)
		bt.parallel().tween_property(ban, "scale", Vector2.ONE * 1.08, 0.6)

	# denyut huruf + aura partikel selama kartu tampil
	var pt := grade.create_tween().set_loops()
	pt.set_ignore_time_scale(true)
	pt.tween_interval(0.5)
	pt.tween_property(grade, "modulate", Color(1.5, 1.25, 1.0) if strong else Color(1.3, 1.15, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
	pt.tween_property(grade, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	var aura := CPUParticles2D.new()
	aura.position = gc
	aura.amount = 26 if strong else 16
	aura.lifetime = 1.7
	aura.direction = Vector2(0, -1)
	aura.spread = 40.0
	aura.gravity = Vector2(0, -18)
	aura.initial_velocity_min = 25.0
	aura.initial_velocity_max = 85.0 if strong else 55.0
	aura.scale_amount_min = 2.0
	aura.scale_amount_max = 4.5 if strong else 3.0
	aura.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	aura.emission_rect_extents = Vector2(26, 34)
	aura.color_ramp = _ramp(col)
	aura.material = _additive()
	_card.add_child(aura)

	if strong:
		# satu kilat bersih
		var fl := ColorRect.new()
		fl.color = Color(1, 0.96, 0.9, 0.6)
		fl.set_anchors_preset(Control.PRESET_FULL_RECT)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fxl.add_child(fl)
		create_tween().set_ignore_time_scale(true).tween_property(fl, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		# vinyet merah: satu tarikan napas, bukan denyut
		var vg := ColorRect.new()
		vg.set_anchors_preset(Control.PRESET_FULL_RECT)
		vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vm := ShaderMaterial.new()
		var vs := Shader.new()
		vs.code = VIGNETTE_SHADER
		vm.shader = vs
		vm.set_shader_parameter("amount", 0.0)
		vg.material = vm
		fxl.add_child(vg)
		var vt := create_tween().set_ignore_time_scale(true)
		vt.tween_method(_vig_step.bind(vm), 0.0, 0.5, 0.3)
		vt.tween_interval(1.4)
		vt.tween_method(_vig_step.bind(vm), 0.5, 0.0, 1.2)
		_shake_card(9.0)
		# lambang silinder revolver berputar pelan di belakang S: hanya rank ini yang punya
		var em := Emblem.new()
		em.col = col
		em.size = Vector2(176, 176)
		em.pivot_offset = em.size * 0.5
		em.position = gc - em.size * 0.5
		em.modulate.a = 0.0
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(em)
		_card.move_child(em, grade.get_index())
		var emt := create_tween().set_ignore_time_scale(true)
		emt.tween_property(em, "modulate:a", 0.85, 0.8).set_delay(0.3)
		var spin := em.create_tween().set_loops()
		spin.set_ignore_time_scale(true)
		spin.tween_property(em, "rotation", TAU, 22.0).from(0.0)

	var kill := create_tween().set_ignore_time_scale(true)
	kill.tween_interval(3.5)
	kill.tween_callback(fxl.queue_free)


## Rank S: tenang tapi megah. Letterbox sinematik masuk, garis tipis melebar, "REVENANT" merenggang huruf demi huruf,
## satu kalimat kecil menyusul. Tanpa kekacauan: kesan langka datang dari kontrol, bukan dari keramaian.
func _s_banner(fxl: CanvasLayer, vp: Vector2, col: Color) -> void:
	var bar_h := vp.y * 0.1
	for side in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(vp.x, bar_h)
		var y_in := 0.0 if side == 0 else vp.y - bar_h
		var y_out := -bar_h if side == 0 else vp.y
		bar.position = Vector2(0, y_out)
		fxl.add_child(bar)
		var bt := create_tween().set_ignore_time_scale(true)
		bt.tween_property(bar, "position:y", y_in, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		bt.tween_interval(2.6)
		bt.tween_property(bar, "position:y", y_out, 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	var cy := vp.y * 0.2
	var fsize := int(vp.y * 0.085)
	# garis tipis atas & bawah melebar dari tengah
	for k in 2:
		var ln := ColorRect.new()
		ln.color = Color(col, 0.75)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ln.size = Vector2(0, 2)
		ln.position = Vector2(vp.x * 0.5, cy - fsize * 0.75 if k == 0 else cy + fsize * 0.75)
		fxl.add_child(ln)
		var lt := create_tween().set_ignore_time_scale(true)
		lt.tween_interval(0.35)
		lt.tween_method(_line_step.bind(ln, vp.x * 0.5, vp.x * 0.34), 0.0, 1.0, 0.7)
		lt.tween_interval(1.7)
		lt.tween_property(ln, "modulate:a", 0.0, 0.5)

	# kata utama: kerning melebar pelan
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.spacing_glyph = -6
	var word := _lbl(fsize, Color(1.0, 0.95, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	word.add_theme_font_override("font", fv)
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.text = "REVENANT"
	word.size = Vector2(vp.x, fsize * 1.5)
	word.position = Vector2(0, cy - fsize * 0.75)
	word.modulate.a = 0.0
	fxl.add_child(word)
	var wt := create_tween().set_ignore_time_scale(true)
	wt.tween_interval(0.5)
	wt.tween_property(word, "modulate:a", 1.0, 0.5)
	wt.parallel().tween_property(fv, "spacing_glyph", int(fsize * 0.5), 2.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	wt.parallel().tween_property(word, "theme_override_colors/font_color", col, 1.4).set_delay(0.3)
	wt.tween_interval(1.0)
	wt.tween_property(word, "modulate:a", 0.0, 0.5)

	# kalimat kecil
	var sub := _lbl(int(vp.y * 0.022), Color(0.82, 0.78, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	sub.text = " ".join("YOU ARE STILL WARM.".split(""))
	sub.size = Vector2(vp.x, 30)
	sub.position = Vector2(0, cy + fsize * 0.95)
	sub.modulate.a = 0.0
	fxl.add_child(sub)
	var st := create_tween().set_ignore_time_scale(true)
	st.tween_interval(1.5)
	st.tween_property(sub, "modulate:a", 0.9, 0.7)
	st.tween_interval(1.1)
	st.tween_property(sub, "modulate:a", 0.0, 0.5)


func _line_step(k: float, ln: ColorRect, cx: float, half: float) -> void:
	if is_instance_valid(ln):
		var e := 1.0 - pow(1.0 - k, 3.0)
		ln.size.x = half * 2.0 * e
		ln.position.x = cx - half * e


func _ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 0.0), Color(c, 0.9), Color(c, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	return g


func _sparks(parent: Node, pos: Vector2, count: int, speed: float, c: Color) -> void:
	var pr := CPUParticles2D.new()
	pr.position = pos
	pr.one_shot = true
	pr.emitting = false
	pr.amount = count
	pr.lifetime = 1.0
	pr.lifetime_randomness = 0.4
	pr.explosiveness = 1.0
	pr.direction = Vector2(0, -1)
	pr.spread = 180.0
	pr.gravity = Vector2(0, 520)
	pr.initial_velocity_min = speed * 0.3
	pr.initial_velocity_max = speed
	pr.damping_min = 40.0
	pr.damping_max = 120.0
	pr.scale_amount_min = 2.0
	pr.scale_amount_max = 5.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.97, 0.85, 1.0), c, Color(c, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	pr.color_ramp = g
	pr.material = _additive()
	parent.add_child(pr)
	pr.emitting = true
	pr.finished.connect(pr.queue_free)


func _ring_step(k: float, ring: Control, r1: float) -> void:
	if is_instance_valid(ring):
		ring.set_state(r1 * (1.0 - pow(1.0 - k, 3.0)), 1.0 - k)


func _ghost_step(k: float, g: Label, base_x: float, dir: float, amount: float) -> void:
	if is_instance_valid(g):
		var e := pow(1.0 - k, 2.0)
		g.position.x = base_x + dir * amount * e + randf_range(-1.0, 1.0) * 6.0 * e
		g.modulate.a = 1.0 - k * k


func _vig_step(v: float, m: ShaderMaterial) -> void:
	m.set_shader_parameter("amount", v)


func _glitch_bar() -> void:
	if _card == null:
		return
	var b := ColorRect.new()
	b.color = Color(COLORS[4], 0.55) if randf() < 0.6 else Color(0.9, 0.95, 1.0, 0.5)
	b.size = Vector2(380.0 + randf_range(0.0, 60.0), randf_range(3.0, 13.0))
	b.position = Vector2(randf_range(-40.0, 10.0), randf_range(0.0, 290.0))
	b.material = _additive()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(b)
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_interval(randf_range(0.04, 0.1))
	t.tween_callback(b.queue_free)


func _shake_card(amount: float) -> void:
	if _card == null:
		return
	var c := _card
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(_shake_card_step.bind(c, amount), 0.0, 1.0, 0.28)
	tw.tween_callback(_shake_card_step.bind(1.0, c, 0.0))


func _shake_card_step(k: float, c: Control, amount: float) -> void:
	if is_instance_valid(c):
		c.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount * (1.0 - k)


## KELUAR: berkedip glitch -> menyala terang -> runtuh jadi garis -> garis menyusut ke tengah dan hilang
func _close_card() -> void:
	var c := _card
	_card = null
	var tw := create_tween().set_ignore_time_scale(true)
	for i in 3:
		tw.tween_property(c, "modulate:a", 0.3, 0.03)
		tw.tween_property(c, "modulate:a", 1.0, 0.05)
	tw.tween_property(c, "modulate", Color(2.4, 2.4, 2.4, 1.0), 0.06)
	tw.tween_property(c, "scale:y", 0.012, 0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale:x", 0.0, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(c.get_parent().get_parent().queue_free)


func _show_row(a: Label, b: Label) -> void:
	a.modulate.a = 1.0
	b.modulate.a = 1.0


func _set_row(v: float, lbl: Label, fmt: String) -> void:
	lbl.text = _fmt_time(v) if fmt == "T" else (fmt % int(v))


func _show_results() -> void:
	if _results_shown:
		return
	_results_shown = true
	var rl := CanvasLayer.new()
	rl.layer = 70
	add_child(rl)
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.anchor_top = 0.5
	anchor.anchor_bottom = 0.5
	anchor.offset_left = margin + 10.0
	anchor.offset_right = margin + 10.0 + 380.0
	anchor.offset_top = -150.0
	anchor.offset_bottom = 150.0
	rl.add_child(anchor)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = Vector2(380, 300)
	_card.pivot_offset = Vector2(190, 150)
	_card.scale = Vector2(0.0, 0.012)                 # mulai sebagai titik, lalu 'dinyalakan' seperti monitor
	_card.modulate = Color(2.4, 2.4, 2.4, 1.0)
	anchor.add_child(_card)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.74)
	bg.size = Vector2(380, 300)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(bg)
	var gr: Array = RANKS[best_rank]
	var col: Color = COLORS[best_rank]
	for r in [Rect2(0, 0, 380, 2), Rect2(0, 0, 2, 300)]:
		var line := ColorRect.new()
		line.color = col
		line.position = r.position
		line.size = r.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(line)

	var tag := _lbl(13, Color(0.65, 0.62, 0.58), HORIZONTAL_ALIGNMENT_LEFT)
	tag.text = "// SIGNAL REPORT"
	tag.position = Vector2(18, 14)
	tag.size = Vector2(300, 18)
	_card.add_child(tag)

	var grade := _lbl(96, col, HORIZONTAL_ALIGNMENT_CENTER)
	grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grade.text = gr[0]
	grade.position = Vector2(200, 4)
	grade.size = Vector2(164, 104)
	grade.pivot_offset = Vector2(82, 52)
	_card.add_child(grade)
	var gword := _lbl(16, col, HORIZONTAL_ALIGNMENT_CENTER)
	gword.text = " ".join(String(gr[1]).split(""))
	gword.position = Vector2(192, 106)
	gword.size = Vector2(180, 22)
	_card.add_child(gword)
	var best := _lbl(13, Color(0.65, 0.62, 0.58), HORIZONTAL_ALIGNMENT_LEFT)
	best.text = "BEST RANK"
	best.position = Vector2(18, 60)
	best.size = Vector2(150, 18)
	_card.add_child(best)

	var deaths_n: int = int(Engine.get_meta("death_count", 0))
	var rows := [
		["KILLS", float(kills), "%d"],
		["PARRIES", float(_parries), "%d"],
		["BEST CHAIN", float(_best_chain), "x%d"],
		["TIME", _play_time, "T"],
		["DAMAGE TAKEN", float(_damage_hits), "%d"],
		["DEATHS", float(deaths_n), "%d"],
	]
	# MASUK: garis melebar -> terbuka ke bawah -> teks diketik -> huruf rank menghantam
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_card, "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_card, "modulate", Color.WHITE, 0.5)
	_sfx("rank_s" if best_rank == 4 else ("rank_a" if best_rank == 3 else "style_up"), -2.0 if best_rank >= 3 else -5.0)
	for l in [tag, gword, best]:
		l.visible_ratio = 0.0
		create_tween().set_ignore_time_scale(true).tween_property(l, "visible_ratio", 1.0, 0.35).set_delay(0.45)
	grade.modulate.a = 0.0
	grade.scale = Vector2.ONE * 2.8
	var tg := create_tween().set_ignore_time_scale(true)
	tg.tween_interval(0.62)
	tg.tween_callback(_slam.bind(grade))
	tg.tween_property(grade, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tg.parallel().tween_property(grade, "modulate", Color.WHITE, 0.4)
	for i in rows.size():
		var y := 140.0 + i * 22.0
		var ln := _lbl(15, Color(0.82, 0.78, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
		ln.text = rows[i][0]
		ln.position = Vector2(18, y)
		ln.size = Vector2(190, 20)
		ln.modulate.a = 0.0
		_card.add_child(ln)
		var vl := _lbl(15, Color(0.95, 0.92, 0.84), HORIZONTAL_ALIGNMENT_RIGHT)
		vl.position = Vector2(200, y)
		vl.size = Vector2(164, 20)
		vl.modulate.a = 0.0
		_card.add_child(vl)
		var target: float = rows[i][1]
		var fmt: String = rows[i][2]
		var d := 0.8 + i * 0.17
		var t2 := create_tween().set_ignore_time_scale(true)
		t2.tween_interval(d)
		t2.tween_callback(_show_row.bind(ln, vl))
		t2.tween_method(_set_row.bind(vl, fmt), 0.0, target, 0.5)
	if _damage_hits == 0:
		var fl := _lbl(14, COLORS[2], HORIZONTAL_ALIGNMENT_LEFT)
		fl.text = "[ FLAWLESS ]"
		fl.position = Vector2(18, 272)
		fl.size = Vector2(200, 20)
		fl.modulate.a = 0.0
		_card.add_child(fl)
		create_tween().set_ignore_time_scale(true).tween_property(fl, "modulate:a", 1.0, 0.4).set_delay(2.1)
	_card_age = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if debug_key and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		register("parry")


# ---------- LOOP ----------
func _process(delta: float) -> void:
	var paused := get_tree().paused
	if paused != _hidden_by_pause:
		_hidden_by_pause = paused
		for c in get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = not paused    # panel, kartu hasil, efek: semua di bawah menu pause
	if paused:
		return                                 # waktu style berhenti selama pause
	if not _active:
		_panel.modulate.a = 0.0
		return
	_idle += delta
	_combo_t += delta
	if not _results_shown:
		_play_time += delta
	if _card:
		_card_age += delta
		if _card_age > results_duration:
			_close_card()
	if _idle > grace and points > 0.0:
		points = maxf(0.0, points - (5.0 + _rank * 5.0) * delta)

	var idx := 0
	for i in THRESH.size():
		if points >= THRESH[i]:
			idx = i
	if idx != _rank:
		_change_rank(idx)

	var lo: float = THRESH[_rank]
	var hi: float = THRESH[_rank + 1] if _rank < 4 else MAX_POINTS
	var frac := clampf((points - lo) / (hi - lo), 0.0, 1.0)
	_bar.size.x = lerpf(_bar.size.x, _bar_bg.size.x * frac, delta * 14.0)
	_bar.color = COLORS[_rank]

	# panel muncul saat ada poin / aktivitas, memudar kalau sepi
	var want := 1.0 if (points > 1.0 or _idle < 0.0 or _idle < 1.5) else idle_alpha
	_t_show = move_toward(_t_show, want, delta * (4.0 if want > _t_show else 1.2))
	_panel.modulate.a = _t_show


func _change_rank(idx: int) -> void:
	var up := idx > _rank
	_rank = idx
	best_rank = maxi(best_rank, idx)
	var r: Array = RANKS[idx]
	_letter.text = r[0]
	_word.text = " ".join(String(r[1]).split(""))
	_letter.add_theme_color_override("font_color", COLORS[idx])
	_word.add_theme_color_override("font_color", COLORS[idx])
	var tw := create_tween().set_ignore_time_scale(true)
	if up:
		_letter.scale = Vector2.ONE * 1.7
		_letter.modulate = Color(2.2, 2.0, 1.6)
		tw.set_parallel(true)
		tw.tween_property(_letter, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_letter, "modulate", Color.WHITE, 0.4)
		_sfx("style_up", -3.0)
		_shake(4.0 + idx)
	else:
		_letter.scale = Vector2(0.85, 0.85)
		tw.set_parallel(true)
		tw.tween_property(_letter, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_sfx("style_down", -6.0)
		_log("RANK LOST", Color(0.62, 0.6, 0.57))


func _ping() -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	_bar.modulate = Color(1.8, 1.8, 1.8)
	tw.tween_property(_bar, "modulate", Color.WHITE, 0.2)


func _log(text: String, color: Color) -> void:
	var l := _lbl(14, color)
	l.text = text
	l.size = Vector2(300, 18)
	l.custom_minimum_size = Vector2(300, 18)
	_feed.add_child(l)
	while _feed.get_child_count() > 4:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _shake(amount: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(k: float): _panel.position = _base_pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * (1.0 - k), 0.0, 1.0, 0.25)
	tw.tween_callback(func(): _panel.position = _base_pos)


func _sfx(sfx_name: String, db: float) -> void:
	var path := sfx_dir.path_join(sfx_name + ".wav")
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# Cincin kejut (digambar pakai arc)
class Ring extends Control:
	var radius := 0.0
	var alpha := 1.0
	var col := Color.WHITE
	var width := 4.0

	func set_state(r: float, a: float) -> void:
		radius = r
		alpha = a
		queue_redraw()

	func _draw() -> void:
		if radius > 0.5:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, Color(col, alpha), width, true)


# Lambang silinder revolver (sama dengan death screen): ring bersudut, 6 ruang peluru, satu terisi
class Emblem extends Control:
	var col := Color(1.0, 0.3, 0.25)

	func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in n + 1:
			out.append(c + Vector2.from_angle(rot + TAU * float(i % n) / float(n)) * r)
		return out

	func _draw() -> void:
		var R := minf(size.x, size.y) * 0.46
		var c := size * 0.5
		draw_polyline(_ngon(c, R, 12, 0.26), Color(col, 0.9), 2.4)
		draw_polyline(_ngon(c, R * 0.86, 12, 0.26), Color(col, 0.4), 1.0)
		for i in 6:
			var a := TAU * i / 6.0
			var cc := c + Vector2.from_angle(a) * R * 0.66
			draw_polyline(_ngon(cc, R * 0.13, 8, a), Color(col, 0.7), 1.6)
			if i == 2:
				draw_colored_polygon(_ngon(cc, R * 0.07, 8, a).slice(0, 8), Color(1.0, 0.72, 0.27))
		for i in 12:
			var a2 := TAU * (i + 0.5) / 12.0
			draw_line(c + Vector2.from_angle(a2) * R * 0.93, c + Vector2.from_angle(a2) * R * 1.0, Color(col, 0.6), 1.2)
