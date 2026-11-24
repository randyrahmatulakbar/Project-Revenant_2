extends CanvasLayer
## DEV CONSOLE untuk tes game. Tekan ` (backtick, di bawah ESC) untuk buka / tutup.
##
## Buka: ` (backtick) atau F1.
## Pasang sebagai AUTOLOAD (Project > Project Settings > Globals > Autoload), nama bebas (mis. DevConsole),
## file ini boleh di folder mana saja (item_catalog.gd dan grenade_projectile.gd dicari otomatis).
## Semuanya dibangun lewat kode, tidak butuh scene. Matikan total lewat `enabled` (mis. untuk build rilis).
##
## Tab:  PLAYER (god, fly, infinite ammo, heal, teleport)  /  ITEMS (spawn ke case atau lantai)
##       ENEMIES (spawn, kill, freeze AI, wave, style rank)  /  WORLD (time scale, fullbright, HUD, screenshot, reload)
##       FX (tes ledakan, kilatan layar)

# Dicari otomatis di seluruh project (dev_menu.gd boleh ditaruh di folder mana saja).
var Catalog                       # Script (dinamis)
var Grenade

@export var enabled := true                      # KILL SWITCH: false = menu tidak dibuat sama sekali
@export var toggle_key: Key = KEY_QUOTELEFT      # tombol buka / tutup
@export var fly_speed := 9.0                     # m/detik (tahan sprint = 3x)
@export var show_stats := false                  # panel kecil FPS / posisi di pojok kanan atas (nyalakan lewat toggle STATS OVERLAY)
@export var panel_width := 620.0
@export var auto_skip_intro := true            # buka menu saat intro berjalan = semua intro dilewati seketika + player ditaruh di lantai
@export var pause_when_open := false             # true = game berhenti selama menu terbuka

const PEACH := Color("dea68a")
const CREAM := Color(0.92, 0.86, 0.81)
const DIM := Color(0.92, 0.86, 0.81, 0.55)
const BG := Color(0.085, 0.125, 0.125, 0.95)
const PLATE := Color(0.13, 0.19, 0.19, 0.95)
const PLATE_HI := Color(0.19, 0.28, 0.28, 0.98)
const RED := Color(0.9, 0.33, 0.24)
const GREEN := Color(0.43, 0.68, 0.56)
const DARK := Color(0.09, 0.13, 0.13)

var _font: Font
var _panel: PanelContainer
var _stats: Label
var _toast: Label
var _toast_tw: Tween
var _open := false
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _paused_by_us := false
var _tabs: Array[Control] = []
var _tab_btns: Array[Button] = []

var _god := false
var _fly := false
var _inf_ammo := false
var _frozen := false
var _fullbright := false
var _hide_hud := false
var _unshaded := false
var _in_hp := false
var _hp_conn: Node
var _saved_pos := Vector3.ZERO
var _has_saved := false
var _start_pos := Vector3.ZERO
var _has_start := false
var _env_backup := {}
var _node_cache := {}
var _stats_t := 0.0
var _ammo_seen := -1

var _iw: Array = []              # blok item (tab ITEMS + versi simple di GENERAL): {list, filter, amount, ids}
var _enemy_paths: Array = []
var _ew: Array = []              # blok enemy: {list, count, info}
var _scan_done := false
var _toggles := {}               # key -> Array[Button]   (toggle yang sama di beberapa tab selalu sinkron)
var _time_btns: Array = []       # {btn, val}
var _time_labels: Array = []
var _pistol_pos := Vector3(32, -0.7, -91)    # posisi PistolPickup di intro.tscn (cadangan kalau node sudah hilang)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("dev_menu")                         # dipakai script lain (mis. boot_sequence) untuk tahu menu sedang terbuka
	if not enabled:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_font = load("res://font/Rajdhani-Bold.ttf")
	Catalog = _find_res("item_catalog.gd")
	Grenade = _find_res("grenade_projectile.gd")
	if Catalog == null:
		push_warning("[DevConsole] item_catalog.gd tidak ditemukan, tab ITEMS kosong.")
	if Grenade == null:
		push_warning("[DevConsole] grenade_projectile.gd tidak ditemukan, tab FX tidak jalan.")
	_build()
	_panel.hide()
	print("[DevConsole] siap. Tekan ` atau F1 untuk membuka.")


# ---------------------------------------------------------------- input / buka tutup

func _input(event: InputEvent) -> void:
	var ke := event as InputEventKey
	if ke != null and ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE and _open:
		_set_open(false)
		get_viewport().set_input_as_handled()


# Tombol buka / tutup dicek langsung tiap frame (tidak bisa ditelan node lain yang memakai set_input_as_handled).
var _k_prev := false
var _esc_prev := false

func _poll_keys() -> void:
	var down := Input.is_key_pressed(KEY_F1) or Input.is_key_pressed(toggle_key) or Input.is_physical_key_pressed(toggle_key)
	if down and not _k_prev:
		_set_open(not _open)
	_k_prev = down
	var esc := Input.is_key_pressed(KEY_ESCAPE)
	if esc and not _esc_prev and _open:
		_set_open(false)
	_esc_prev = esc


func _set_open(v: bool) -> void:
	if v == _open:
		return
	_open = v
	_panel.visible = v
	var p = _player()
	if v:
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if auto_skip_intro and _intro_running(p):
			_skip_intro()
		if p != null:
			if not _has_start:
				_has_start = true
				_start_pos = p.global_position
			p.set_physics_process(false)
			p.set_process_unhandled_input(false)
		if pause_when_open and not get_tree().paused:
			get_tree().paused = true
			_paused_by_us = true
		if not _scan_done:
			_scan_enemy_scenes()
		_refresh_items()
		_refresh_enemies()
	else:
		get_viewport().gui_release_focus()
		Input.mouse_mode = _prev_mouse
		if p != null and p.get("_dead") != true:        # kalau player sudah mati, jangan dihidupkan lagi
			if not _fly:
				p.set_physics_process(true)
			p.set_process_unhandled_input(true)
		if _paused_by_us:
			get_tree().paused = false
			_paused_by_us = false


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- skip intro

# Intro masih berjalan kalau BootSequence masih ada, atau IntroLanding ada dan player masih terkunci (fisika mati).
func _intro_running(p) -> bool:
	var root := get_tree().current_scene
	if root == null:
		return false
	var bs := root.find_child("BootSequence", true, false)
	if bs != null and is_instance_valid(bs) and not bs.is_queued_for_deletion():
		return true
	var landing := root.find_child("IntroLanding", true, false)
	return landing != null and p != null and not p.is_physics_processing() and not _fly and p.get("_dead") != true


func _skip_intro() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p = _player()
	# 1) intro boot (terminal + kelopak mata): buang, game jangan tetap di-pause
	var bs := root.find_child("BootSequence", true, false)
	if bs != null and is_instance_valid(bs):
		bs.queue_free()
	if get_tree().paused and not _paused_by_us:
		get_tree().paused = false
	# 2) intro landing: panggil fungsi skip kalau ada, kalau tidak kirim sinyal landed (supaya sfx / event lain jalan)
	var landing := root.find_child("IntroLanding", true, false)
	if landing != null and is_instance_valid(landing):
		var called := false
		for m in ["skip", "skip_landing", "finish", "land", "force_land"]:
			if landing.has_method(m):
				landing.call(m)
				called = true
				break
		if not called and landing.has_signal("landed"):
			landing.emit_signal("landed")
		landing.queue_free()
	# 3) player: taruh di lantai tepat di bawahnya, hidupkan lagi kontrolnya
	if p != null:
		var from: Vector3 = p.global_position + Vector3.UP * 0.5
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 120.0)
		q.collision_mask = 1
		var ex: Array[RID] = [p.get_rid()]
		q.exclude = ex
		var r: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			p.global_position = r.position + Vector3(0, 1.1, 0)
		p.velocity = Vector3.ZERO
		p.set_physics_process(true)
	say("INTRO DILEWATI")


func _a_skip_intro() -> void:
	_skip_intro()
	_set_open(false)


func _a_auto_skip(on: bool) -> void:
	auto_skip_intro = on
	_sync("autoskip", on)


# ---------------------------------------------------------------- cari file script

func _find_res(fname: String, path: String = "res://", depth: int = 0) -> Script:
	if depth > 6:
		return null
	var d := DirAccess.open(path)
	if d == null:
		return null
	var subdirs: Array[String] = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with(".") and f != "addons":
				subdirs.append(path.path_join(f))
		elif f == fname:
			d.list_dir_end()
			return load(path.path_join(f)) as Script
		f = d.get_next()
	d.list_dir_end()
	for sd in subdirs:
		var r := _find_res(fname, sd, depth + 1)
		if r != null:
			return r
	return null


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_poll_keys()
	_update_time_ui()
	var p = _player()
	if p != null:
		var h: Node = p.get_node_or_null("Health")
		if h != null:
			_hook_health(h)
			if _god and float(h.current_health) < float(h.max_health):
				_set_hp(h, float(h.max_health))
		if _inf_ammo and p.get("current_ammo") != null:
			var mx: int = int(p.max_ammo_per_clip)
			if int(p.current_ammo) != mx:
				p.current_ammo = mx
				p.reserve_ammo = maxi(int(p.reserve_ammo), 24)
				if p.has_method("_update_ammo_ui"):
					p._update_ammo_ui()
	if _frozen:
		for e in get_tree().get_nodes_in_group("enemy"):
			e.set_physics_process(false)
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = 0.2
		_update_stats(p)


func _physics_process(delta: float) -> void:
	if not _fly or _open or get_tree().paused:
		return
	var p = _player()
	if p == null:
		return
	var cam: Camera3D = p.camera
	var ip := Input.get_vector("left", "right", "foward", "back")
	var dir := cam.global_transform.basis.x * ip.x - cam.global_transform.basis.z * (-ip.y)
	if Input.is_action_pressed("jump"):
		dir += Vector3.UP
	if Input.is_action_pressed("crouch"):
		dir += Vector3.DOWN
	var spd := fly_speed * (3.0 if Input.is_action_pressed("sprint") else 1.0)
	p.global_position += dir.normalized() * spd * delta if dir.length() > 0.01 else Vector3.ZERO
	p.velocity = Vector3.ZERO


func _update_stats(p) -> void:
	if _stats == null:
		return
	_stats.visible = show_stats
	if not show_stats:
		return
	var s := "%d FPS" % Engine.get_frames_per_second()
	if p != null:
		var pos: Vector3 = p.global_position
		s += "\nXYZ  %.1f  %.1f  %.1f" % [pos.x, pos.y, pos.z]
		s += "\nSPD  %.1f" % Vector2(p.velocity.x, p.velocity.z).length()
	s += "\nENEMIES  %d" % get_tree().get_nodes_in_group("enemy").size()
	if Engine.time_scale != 1.0:
		s += "\nTIME  x%.2f" % Engine.time_scale
	var flags := []
	if _god:
		flags.append("GOD")
	if _fly:
		flags.append("FLY")
	if _inf_ammo:
		flags.append("AMMO")
	if _frozen:
		flags.append("FREEZE")
	if not flags.is_empty():
		s += "\n[" + " ".join(flags) + "]"
	_stats.text = s


# ---------------------------------------------------------------- helper game

func _player():
	return get_tree().get_first_node_in_group("player")


func _find_script(fname: String) -> Node:
	var c = _node_cache.get(fname)
	if c != null and is_instance_valid(c):
		return c
	var found := _walk(get_tree().root, fname)
	_node_cache[fname] = found
	return found


func _walk(n: Node, fname: String) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.get_file() == fname:
		return n
	for ch in n.get_children():
		var r := _walk(ch, fname)
		if r != null:
			return r
	return null


func _aim_point() -> Vector3:
	var p = _player()
	if p == null:
		return Vector3.ZERO
	var cam: Camera3D = p.camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 200.0)
	var ex: Array[RID] = [p.get_rid()]
	q.exclude = ex
	var r: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return from + fwd * 4.0
	return r.position


func _front_point() -> Vector3:
	var p = _player()
	if p == null:
		return Vector3.ZERO
	var f: Vector3 = -p.global_transform.basis.z
	f.y = 0.0
	return p.global_position + f.normalized() * 1.6


func _hook_health(h: Node) -> void:
	if _hp_conn == h:
		return
	_hp_conn = h
	if h.has_signal("health_changed"):
		h.health_changed.connect(_on_hp_changed.bind(h))


func _on_hp_changed(cur: float, mx: float, h: Node) -> void:
	if _god and not _in_hp and cur < mx:
		_set_hp(h, mx)


func _set_hp(h: Node, v: float) -> void:
	_in_hp = true
	var mx := float(h.max_health)
	var cur := clampf(v, 1.0, mx)
	h.current_health = cur
	if h.has_signal("health_changed"):
		h.emit_signal("health_changed", cur, mx)
	_in_hp = false


func say(t: String) -> void:
	if _toast == null:
		return
	_toast.text = t
	_toast.modulate.a = 1.0
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_interval(2.2)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------- aksi PLAYER

func _a_god(on: bool) -> void:
	_god = on
	_sync("god", on)
	say("GOD MODE " + ("ON" if on else "OFF"))


func _a_fly(on: bool) -> void:
	_fly = on
	_sync("fly", on)
	var p = _player()
	if p != null:
		p.velocity = Vector3.ZERO
		if not on and not _open:
			p.set_physics_process(true)
		elif on:
			p.set_physics_process(false)
	say("FLY " + ("ON  (WASD + SPACE / CTRL, SHIFT = cepat)" if on else "OFF"))


func _a_inf_ammo(on: bool) -> void:
	_inf_ammo = on
	_sync("ammo", on)
	_ammo_seen = -1
	say("INFINITE AMMO " + ("ON" if on else "OFF"))


func _a_heal(v: float) -> void:
	var p = _player()
	if p == null:
		return
	var h: Node = p.get_node_or_null("Health")
	if h == null:
		return
	_set_hp(h, float(h.max_health) if v < 0.0 else v)
	say("HP -> %d" % int(h.current_health))


func _a_kill_self() -> void:
	var p = _player()
	if p == null:
		return
	var h: Node = p.get_node_or_null("Health")
	if h != null and h.has_method("take_damage"):
		_god = false
		_sync("god", false)
		h.take_damage(float(h.max_health) * 10.0)


func _a_tp_aim() -> void:
	var p = _player()
	if p == null:
		return
	p.global_position = _aim_point() + Vector3(0, 1.0, 0)
	p.velocity = Vector3.ZERO
	say("TELEPORT ke crosshair")


func _a_save_pos() -> void:
	var p = _player()
	if p == null:
		return
	_saved_pos = p.global_position
	_has_saved = true
	say("POSISI DISIMPAN")


func _a_load_pos() -> void:
	var p = _player()
	if p == null or not _has_saved:
		say("Belum ada posisi tersimpan")
		return
	p.global_position = _saved_pos
	p.velocity = Vector3.ZERO
	say("KEMBALI ke posisi tersimpan")


func _a_to_start() -> void:
	var p = _player()
	if p == null or not _has_start:
		return
	p.global_position = _start_pos
	p.velocity = Vector3.ZERO
	say("KEMBALI ke titik awal")


# ---------------------------------------------------------------- aksi ITEMS

func _refresh_items() -> void:
	for w in _iw:
		var l: ItemList = w["list"]
		var ids: Array = w["ids"]
		l.clear()
		ids.clear()
		if Catalog == null:
			continue
		var f := (w["filter"] as LineEdit).text.strip_edges().to_lower()
		for id in Catalog.all_ids():
			var it: ItemData = Catalog.get_item(id)
			if it == null:
				continue
			var nm := it.display_name if it.display_name != "" else str(id)
			if f != "" and not (nm.to_lower().contains(f) or str(id).to_lower().contains(f) or ItemData.Type.keys()[it.type].to_lower().contains(f)):
				continue
			l.add_item("%s     ·  %s" % [nm, ItemData.Type.keys()[it.type]])
			ids.append(id)


func _selected_item(w: Dictionary) -> ItemData:
	var sel: PackedInt32Array = (w["list"] as ItemList).get_selected_items()
	if sel.is_empty() or Catalog == null:
		say("Pilih item dulu")
		return null
	return Catalog.get_item((w["ids"] as Array)[sel[0]])


func _a_item_add(w: Dictionary) -> void:
	var it := _selected_item(w)
	if it == null:
		return
	var n := int((w["amount"] as SpinBox).value)
	if Inventory.add_item(it, n):
		say("+ %s x%d ke case" % [it.display_name, n])
	else:
		say("Case penuh / gagal")


func _drop(items: Array, pos: Vector3) -> void:
	var lm := _find_script("loot_manager.gd")
	if lm == null or not lm.has_method("spawn_drop"):
		say("LootManager tidak ditemukan di scene")
		return
	lm.spawn_drop(pos, items)


func _a_item_drop(w: Dictionary, at_aim: bool) -> void:
	var it := _selected_item(w)
	if it == null:
		return
	_drop([{"item": it, "amount": int((w["amount"] as SpinBox).value)}], _aim_point() if at_aim else _front_point())
	say("DROP %s" % it.display_name)


func _a_drop_all() -> void:
	if Catalog == null:
		say("item_catalog.gd tidak ditemukan")
		return
	var items := []
	for id in Catalog.all_ids():
		var it: ItemData = Catalog.get_item(id)
		if it != null:
			items.append({"item": it, "amount": 1})
	_drop(items, _front_point())
	say("DROP semua item di depanmu")


func _a_give_all() -> void:
	if Catalog == null:
		say("item_catalog.gd tidak ditemukan")
		return
	var n := 0
	for id in Catalog.all_ids():
		var it: ItemData = Catalog.get_item(id)
		if it != null and Inventory.add_item(it, 1):
			n += 1
	say("%d item masuk case" % n)


func _a_fill_ammo() -> void:
	if Catalog == null:
		say("item_catalog.gd tidak ditemukan")
		return
	var n := 0
	for id in Catalog.all_ids():
		var it: ItemData = Catalog.get_item(id)
		if it != null and it.type == ItemData.Type.AMMO:
			for i in 3:
				if Inventory.add_item(it, 1):
					n += 1
	say("%d magazine ditambah" % n)


func _a_clear_case() -> void:
	Inventory.clear()
	say("CASE dikosongkan")


# ---------------------------------------------------------------- aksi ENEMIES

func _scan_enemy_scenes() -> void:
	_scan_done = true
	_enemy_paths.clear()
	var sp := _find_script("enemy_spawner.gd")
	if sp != null:
		for sc in sp.enemy_scenes:
			if sc != null and sc.resource_path != "" and not _enemy_paths.has(sc.resource_path):
				_enemy_paths.append(sc.resource_path)
	_scan_dir("res://", 0)


func _scan_dir(path: String, depth: int) -> void:
	if depth > 5:
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with(".") and f != "addons":
				_scan_dir(path.path_join(f), depth + 1)
		else:
			var fl := f.to_lower()
			if fl.ends_with(".tscn") and (fl.contains("enemy") or fl.contains("flayer") or fl.contains("leaper") or fl.contains("mauler") or fl.contains("spitter")):
				var full := path.path_join(f)
				if not _enemy_paths.has(full):
					_enemy_paths.append(full)
		f = d.get_next()
	d.list_dir_end()


func _refresh_enemies() -> void:
	for w in _ew:
		var l: ItemList = w["list"]
		l.clear()
		for pth in _enemy_paths:
			l.add_item(String(pth).get_file().get_basename().to_upper())
		(w["info"] as Label).text = ("%d jenis musuh ditemukan" % _enemy_paths.size()) if not _enemy_paths.is_empty() else "Tidak ada scene musuh ditemukan. Cek Enemy Scenes di EnemySpawner."


func _spawn_enemy(path: String, pos: Vector3) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		say("Gagal memuat " + path.get_file())
		return
	var e := ps.instantiate()
	var parent: Node = null
	var existing := get_tree().get_first_node_in_group("enemy")
	if existing != null:
		parent = existing.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if e is Node3D and parent is Node3D:
		(e as Node3D).position = (parent as Node3D).to_local(pos)      # posisi diset SEBELUM add_child (efek spawn pas di tempatnya)
	parent.add_child(e)


func _a_enemy_spawn(w: Dictionary, mode: int) -> void:
	var sel: PackedInt32Array = (w["list"] as ItemList).get_selected_items()
	if sel.is_empty():
		say("Pilih jenis musuh dulu")
		return
	var path: String = _enemy_paths[sel[0]]
	var n := int((w["count"] as SpinBox).value)
	var center := _aim_point()
	var p = _player()
	if mode == 1 and p != null:
		center = p.global_position
	for i in n:
		var pos := center
		if mode == 1 and p != null:
			var a := randf() * TAU
			pos = center + Vector3(cos(a), 0.0, sin(a)) * randf_range(6.0, 10.0)
		elif n > 1:
			pos = center + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		_spawn_enemy(path, pos + Vector3(0, 0.1, 0))
	say("SPAWN %d x %s" % [n, path.get_file().get_basename()])


func _a_kill_all() -> void:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.has_method("take_damage"):
			e.take_damage(99999.0)
			n += 1
	say("%d musuh dibunuh" % n)


func _a_remove_all() -> void:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
		n += 1
	say("%d musuh dihapus" % n)


func _a_freeze(on: bool) -> void:
	_frozen = on
	_sync("freeze", on)
	if not on:
		for e in get_tree().get_nodes_in_group("enemy"):
			e.set_physics_process(true)
	say("FREEZE AI " + ("ON" if on else "OFF"))


func _a_wave(start: bool) -> void:
	var sp := _find_script("enemy_spawner.gd")
	if sp == null:
		say("EnemySpawner tidak ditemukan")
		return
	if start:
		sp.start()
	else:
		sp.stop()
	say("WAVE " + ("START" if start else "STOP"))


func _a_style(idx: int) -> void:
	var st := get_tree().get_first_node_in_group("style")
	if st == null:
		say("StyleMeter tidak ditemukan")
		return
	var th = st.get_script().get_script_constant_map().get("THRESH")
	if th == null or idx >= th.size():
		return
	st._active = true
	st.points = float(th[idx]) + 1.0
	say("STYLE RANK -> %d" % idx)


# ---------------------------------------------------------------- aksi WORLD / FX

func _a_time(v: float) -> void:
	Engine.time_scale = v
	_last_ts = -1.0
	say("TIME SCALE " + _fmt_x(v))


func _fmt_x(v: float) -> String:
	return ("x%.2f" % v).rstrip("0").rstrip(".")


func _a_stats(on: bool) -> void:
	show_stats = on
	_sync("stats", on)


func _a_pause_open(on: bool) -> void:
	pause_when_open = on
	_sync("pauseopen", on)


func _sync(key: String, on: bool) -> void:
	var arr: Array = _toggles.get(key, [])
	for b in arr:
		(b as Button).set_pressed_no_signal(on)


# tanda "aktif" pada tombol time scale + label angka sekarang (dicek tiap frame)
var _last_ts := -1.0

func _update_time_ui() -> void:
	var cur := Engine.time_scale
	if is_equal_approx(cur, _last_ts):
		return
	_last_ts = cur
	for d in _time_btns:
		(d["btn"] as Button).set_pressed_no_signal(is_equal_approx(cur, float(d["val"])))
	for lb in _time_labels:
		(lb as Label).text = "AKTIF  " + _fmt_x(cur)
		(lb as Label).add_theme_color_override("font_color", GREEN if is_equal_approx(cur, 1.0) else PEACH)


# ---------------------------------------------------------------- aksi GENERAL (intro / parkour)

func _a_take_pistol() -> void:
	var root := get_tree().current_scene
	var pk: Node = root.find_child("PistolPickup", true, false) if root != null else null
	var pos := _pistol_pos
	if pk is Node3D:
		pos = (pk as Node3D).global_position
		_pistol_pos = pos
	var p = _player()
	if p != null:
		p.global_position = pos + Vector3(0, 1.2, 2.0)
		p.velocity = Vector3.ZERO
	var msg := "SENJATA DIAMBIL + teleport ke ruangannya"
	if pk == null:
		msg = "Senjata sudah diambil. Teleport ke ruangannya."
	elif pk.has_method("interact"):
		pk.interact()
	elif pk.has_signal("picked_up"):
		pk.emit_signal("picked_up")
	else:
		msg = "PistolPickup tidak punya interact(): hanya teleport"
	_set_open(false)
	say(msg)


func _a_goto_parkour() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var door: Node = root.find_child("BackDoor", true, false)
	if door != null:
		for m in ["open_instant", "open_now", "force_open", "open", "unlock"]:
			if door.has_method(m):
				door.call(m)
				break
		var panel := door.get_node_or_null("Panel")           # pastikan terbuka instan walau script pintu beranimasi
		if panel is CSGShape3D:
			(panel as CSGShape3D).use_collision = false
			(panel as CSGShape3D).visible = false
		var dl := door.get_node_or_null("DoorLight")
		if dl is OmniLight3D:
			(dl as OmniLight3D).light_color = Color(0.3, 1.0, 0.45)
	var room: Node = root.find_child("ParkourRoom", true, false)
	var spot: Node = room.get_node_or_null("Checkpoints/CP0/Spot") if room != null else null
	var target := Vector3(18.5, 1.5, -104.5)
	if spot is Node3D:
		target = (spot as Node3D).global_position + Vector3(0, 1.0, 0)
	elif room is Node3D:
		target = (room as Node3D).global_position + Vector3(0, 1.5, -3.0)
	var p = _player()
	if p != null:
		p.global_position = target
		p.velocity = Vector3.ZERO
	_set_open(false)
	say("RUANG PARKOUR: pintu terbuka" if door != null else "RUANG PARKOUR (node BackDoor tidak ditemukan)")


func _env() -> Environment:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.environment != null:
		return cam.environment
	var w := get_viewport().world_3d
	return w.environment if w != null else null


func _a_fullbright(on: bool) -> void:
	_fullbright = on
	_sync("fullbright", on)
	var env := _env()
	if env == null:
		say("Environment tidak ditemukan")
		return
	if on:
		_env_backup = {
			"src": env.ambient_light_source, "col": env.ambient_light_color,
			"en": env.ambient_light_energy, "fog": env.fog_enabled,
		}
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 1.3
		env.fog_enabled = false
	elif not _env_backup.is_empty():
		env.ambient_light_source = _env_backup["src"]
		env.ambient_light_color = _env_backup["col"]
		env.ambient_light_energy = _env_backup["en"]
		env.fog_enabled = _env_backup["fog"]
	say("FULLBRIGHT " + ("ON" if on else "OFF"))


func _a_unshaded(on: bool) -> void:
	_unshaded = on
	_sync("unshaded", on)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_UNSHADED if on else Viewport.DEBUG_DRAW_DISABLED
	say("UNSHADED VIEW " + ("ON" if on else "OFF"))


func _a_hide_hud(on: bool) -> void:
	_hide_hud = on
	_sync("hidehud", on)
	for h in get_tree().get_nodes_in_group("hud"):
		if h is CanvasLayer:
			(h as CanvasLayer).visible = not on
		elif h is CanvasItem:
			(h as CanvasItem).visible = not on
	say("HUD " + ("DISEMBUNYIKAN" if on else "TAMPIL"))


func _a_screenshot() -> void:
	var was := _panel.visible
	_panel.hide()
	_stats.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	_panel.visible = was
	_stats.visible = show_stats
	say("Screenshot: " + ProjectSettings.globalize_path(path))


func _a_reload() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	_set_open(false)
	get_tree().reload_current_scene()


func _glow_col() -> Color:
	if Grenade != null:
		return Grenade.get_script_constant_map().get("GLOW_COL", PEACH)
	return PEACH


func _a_boom(rad: float) -> void:
	if Grenade == null:
		say("grenade_projectile.gd tidak ditemukan")
		return
	Grenade.explosion_fx(get_tree().current_scene, _aim_point(), rad)
	get_tree().call_group("item_effects", "screen_glow", _glow_col(), 0.6)
	say("BOOM  radius %.1f" % rad)


func _a_bt_preview() -> void:
	if get_tree().get_first_node_in_group("borrowed_time") == null:
		say("BorrowedTime belum terpasang (item_effects.gd belum diganti?)")
		return
	_set_open(false)
	get_tree().call_group("borrowed_time", "preview")


func _a_glow() -> void:
	get_tree().call_group("item_effects", "screen_glow", _glow_col(), 1.0)


# ---------------------------------------------------------------- bangun UI

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# overlay statistik (pojok kanan atas, selalu tampil kalau show_stats)
	_stats = Label.new()
	_stats.anchor_left = 1.0
	_stats.anchor_right = 1.0
	_stats.offset_left = -240.0
	_stats.offset_right = -16.0
	_stats.offset_top = 14.0
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_stats, 15, Color(CREAM, 0.7))
	root.add_child(_stats)

	_panel = PanelContainer.new()
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 24.0
	_panel.offset_top = 24.0
	_panel.offset_right = 24.0 + panel_width
	_panel.offset_bottom = -24.0
	_panel.add_theme_stylebox_override("panel", _sb(BG, PEACH, 0, 4, 18))
	root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "// D E V   C O N S O L E"
	_style_label(title, 20, PEACH)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := Label.new()
	hint.text = "` / ESC  TUTUP"
	_style_label(hint, 13, DIM)
	head.add_child(hint)

	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 6)
	col.add_child(tabrow)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)

	var names := ["GENERAL", "PLAYER", "ITEMS", "ENEMIES", "WORLD", "FX"]
	var builders := [_tab_general, _tab_player, _tab_items, _tab_enemies, _tab_world, _tab_fx]
	for i in names.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.add_child(page)
		builders[i].call(page)
		_tabs.append(page)
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		_style_button(b)
		b.pressed.connect(_show_tab.bind(i))
		tabrow.add_child(b)
		_tab_btns.append(b)

	_toast = Label.new()
	_toast.text = ""
	_style_label(_toast, 15, GREEN)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_toast)
	_show_tab(0)


func _show_tab(i: int) -> void:
	for k in _tabs.size():
		_tabs[k].visible = (k == i)
		_tab_btns[k].set_pressed_no_signal(k == i)


# ---------- blok yang dipakai di beberapa tab
func _blk_cheats(page: VBoxContainer) -> void:
	page.add_child(_sec("CHEATS"))
	page.add_child(_grid([
		_toggle("GOD MODE", _god, _a_god, "god"),
		_toggle("FLY / NOCLIP", _fly, _a_fly, "fly"),
		_toggle("INFINITE AMMO", _inf_ammo, _a_inf_ammo, "ammo"),
	]))
	page.add_child(_note("Fly: WASD gerak, SPACE naik, CTRL turun, SHIFT 3x lebih cepat. Menu harus ditutup dulu."))


func _blk_time(page: VBoxContainer) -> void:
	page.add_child(_sec("TIME SCALE"))
	var lb := Label.new()
	_style_label(lb, 18, GREEN)
	_time_labels.append(lb)
	page.add_child(lb)
	var items := []
	for v in [0.1, 0.25, 0.5, 1.0, 2.0, 3.0]:
		var b := Button.new()
		b.text = _fmt_x(v)
		b.toggle_mode = true
		_style_button(b)
		b.pressed.connect(func(): _a_time(v))
		_time_btns.append({"btn": b, "val": v})
		items.append(b)
	page.add_child(_grid(items))


func _blk_view(page: VBoxContainer) -> void:
	page.add_child(_sec("TAMPILAN"))
	page.add_child(_grid([
		_toggle("FULLBRIGHT", _fullbright, _a_fullbright, "fullbright"),
		_toggle("UNSHADED VIEW", _unshaded, _a_unshaded, "unshaded"),
		_toggle("SEMBUNYIKAN HUD", _hide_hud, _a_hide_hud, "hidehud"),
		_toggle("STATS OVERLAY", show_stats, _a_stats, "stats"),
		_toggle("PAUSE SAAT MENU BUKA", pause_when_open, _a_pause_open, "pauseopen"),
	]))


func _blk_items(page: VBoxContainer, compact: bool) -> void:
	var w := {"ids": []}
	page.add_child(_sec("CARI ITEM" if not compact else "ITEM"))
	var f := LineEdit.new()
	f.placeholder_text = "ketik nama / jenis (ammo, equipment, ...)"
	f.clear_button_enabled = true
	_style_edit(f)
	f.text_changed.connect(func(_t): _refresh_items())
	page.add_child(f)
	w["filter"] = f
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(0, 130 if compact else 250)
	l.select_mode = ItemList.SELECT_SINGLE
	_style_list(l)
	page.add_child(l)
	w["list"] = l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	var lb := Label.new()
	lb.text = "JUMLAH"
	_style_label(lb, 15, DIM)
	row.add_child(lb)
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 99
	sb.value = 1
	_style_edit(sb.get_line_edit())
	row.add_child(sb)
	w["amount"] = sb
	if compact:
		page.add_child(_grid([
			_btn("MASUK CASE", func(): _a_item_add(w), GREEN),
			_btn("DROP DI DEPAN", func(): _a_item_drop(w, false)),
		], 2))
	else:
		page.add_child(_grid([
			_btn("MASUK CASE", func(): _a_item_add(w), GREEN),
			_btn("DROP DI DEPAN", func(): _a_item_drop(w, false)),
			_btn("DROP DI CROSSHAIR", func(): _a_item_drop(w, true)),
		]))
	_iw.append(w)


func _blk_enemies(page: VBoxContainer, compact: bool) -> void:
	var w := {}
	page.add_child(_sec("SPAWN MUSUH" if not compact else "MUSUH"))
	var l := ItemList.new()
	l.custom_minimum_size = Vector2(0, 100 if compact else 130)
	_style_list(l)
	page.add_child(l)
	w["list"] = l
	var info := Label.new()
	_style_label(info, 13, DIM)
	page.add_child(info)
	w["info"] = info
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	var lb := Label.new()
	lb.text = "JUMLAH"
	_style_label(lb, 15, DIM)
	row.add_child(lb)
	var sb := SpinBox.new()
	sb.min_value = 1
	sb.max_value = 30
	sb.value = 1
	_style_edit(sb.get_line_edit())
	row.add_child(sb)
	w["count"] = sb
	if compact:
		page.add_child(_grid([
			_btn("SPAWN DI CROSSHAIR", func(): _a_enemy_spawn(w, 0), GREEN),
			_btn("BUNUH SEMUA", _a_kill_all, RED),
		], 2))
	else:
		page.add_child(_grid([
			_btn("SPAWN DI CROSSHAIR", func(): _a_enemy_spawn(w, 0), GREEN),
			_btn("SPAWN MENGELILINGIMU", func(): _a_enemy_spawn(w, 1)),
		]))
	_ew.append(w)


# ---------- tab GENERAL
func _tab_general(page: VBoxContainer) -> void:
	page.add_child(_sec("QUICK"))
	page.add_child(_grid([
		_btn("AMBIL SENJATA + KE RUANGANNYA", _a_take_pistol, GREEN),
		_btn("KE RUANG PARKOUR (PINTU TERBUKA)", _a_goto_parkour, GREEN),
		_btn("SKIP INTRO SEKARANG", _a_skip_intro),
		_toggle("AUTO SKIP INTRO SAAT MENU DIBUKA", auto_skip_intro, _a_auto_skip, "autoskip"),
	], 2))
	_blk_cheats(page)
	_blk_items(page, true)
	_blk_enemies(page, true)
	_blk_time(page)
	_blk_view(page)
	page.add_child(_sec("SCREENSHOT"))
	page.add_child(_grid([_btn("SCREENSHOT", _a_screenshot)], 2))


# ---------- tab PLAYER
func _tab_player(page: VBoxContainer) -> void:
	_blk_cheats(page)
	page.add_child(_sec("HEALTH"))
	page.add_child(_grid([
		_btn("HEAL FULL", func(): _a_heal(-1.0)),
		_btn("HP 25", func(): _a_heal(25.0)),
		_btn("HP 1", func(): _a_heal(1.0)),
		_btn("KILL SELF", _a_kill_self, RED),
	]))
	page.add_child(_sec("TELEPORT"))
	page.add_child(_grid([
		_btn("KE CROSSHAIR", _a_tp_aim),
		_btn("SIMPAN POSISI", _a_save_pos),
		_btn("KEMBALI KE POSISI", _a_load_pos),
		_btn("KE TITIK AWAL", _a_to_start),
	]))


# ---------- tab ITEMS
func _tab_items(page: VBoxContainer) -> void:
	_blk_items(page, false)
	page.add_child(_sec("SEKALIGUS"))
	page.add_child(_grid([
		_btn("1 DARI SEMUA ITEM -> CASE", _a_give_all),
		_btn("DROP SEMUA (seperti F9)", _a_drop_all),
		_btn("ISI MAGAZINE (x3)", _a_fill_ammo),
		_btn("KOSONGKAN CASE", _a_clear_case, RED),
	]))


# ---------- tab ENEMIES
func _tab_enemies(page: VBoxContainer) -> void:
	_blk_enemies(page, false)
	page.add_child(_sec("KONTROL"))
	page.add_child(_grid([
		_btn("BUNUH SEMUA", _a_kill_all, RED),
		_btn("HAPUS SEMUA", _a_remove_all),
		_toggle("FREEZE AI", _frozen, _a_freeze, "freeze"),
	]))
	page.add_child(_sec("WAVE SPAWNER"))
	page.add_child(_grid([
		_btn("START WAVE", func(): _a_wave(true)),
		_btn("STOP WAVE", func(): _a_wave(false)),
	]))
	page.add_child(_sec("STYLE RANK"))
	page.add_child(_grid([
		_btn("D", func(): _a_style(0)), _btn("C", func(): _a_style(1)), _btn("B", func(): _a_style(2)),
		_btn("A", func(): _a_style(3)), _btn("S", func(): _a_style(4)),
	]))


# ---------- tab WORLD
func _tab_world(page: VBoxContainer) -> void:
	_blk_time(page)
	_blk_view(page)
	page.add_child(_sec("LAINNYA"))
	page.add_child(_grid([
		_btn("SCREENSHOT", _a_screenshot),
		_btn("RELOAD SCENE", _a_reload),
		_btn("QUIT GAME", func(): get_tree().quit(), RED),
	]))
	page.add_child(_note("Screenshot disimpan di folder user:// (path-nya muncul di bawah setelah dipotret)."))


# ---------- tab FX
func _tab_fx(page: VBoxContainer) -> void:
	page.add_child(_sec("LEDAKAN (di crosshair)"))
	page.add_child(_grid([
		_btn("GRENADE  r5", func(): _a_boom(5.0)),
		_btn("EMBER CORE  r3.5", func(): _a_boom(3.5)),
		_btn("BESAR  r9", func(): _a_boom(9.0)),
	]))
	page.add_child(_sec("LAYAR"))
	page.add_child(_grid([
		_btn("KILATAN LAYAR", _a_glow),
		_btn("TES EFEK BORROWED TIME", _a_bt_preview),
	]))
	page.add_child(_note("Tes ledakan tidak melukai siapa pun, hanya efek visual."))


# ---------------------------------------------------------------- komponen UI

func _sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, bl: int = 0, m: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	if bl > 0:
		s.border_width_left = bl
	s.content_margin_left = m + bl
	s.content_margin_right = m
	s.content_margin_top = maxi(m - 4, 4)
	s.content_margin_bottom = maxi(m - 4, 4)
	return s


func _style_label(l: Label, size: int, c: Color) -> void:
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)


func _style_button(b: Button, accent: Color = PEACH) -> void:
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", DARK)
	b.add_theme_color_override("font_hover_pressed_color", DARK)
	b.add_theme_stylebox_override("normal", _sb(PLATE, Color(accent, 0.3), 1, 0, 10))
	b.add_theme_stylebox_override("hover", _sb(PLATE_HI, Color(accent, 0.8), 1, 0, 10))
	b.add_theme_stylebox_override("pressed", _sb(accent, accent, 1, 0, 10))
	b.add_theme_stylebox_override("hover_pressed", _sb(accent, accent, 1, 0, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE


func _style_edit(e: LineEdit) -> void:
	if _font:
		e.add_theme_font_override("font", _font)
	e.add_theme_font_size_override("font_size", 16)
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_color_override("caret_color", PEACH)
	e.add_theme_stylebox_override("normal", _sb(PLATE, Color(PEACH, 0.25), 1, 0, 10))
	e.add_theme_stylebox_override("focus", _sb(PLATE_HI, PEACH, 1, 0, 10))


func _style_list(l: ItemList) -> void:
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", CREAM)
	l.add_theme_color_override("font_selected_color", DARK)
	l.add_theme_color_override("font_hovered_color", Color.WHITE)
	l.add_theme_stylebox_override("panel", _sb(PLATE, Color(PEACH, 0.25), 1, 0, 6))
	l.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	l.add_theme_stylebox_override("selected", _sb(PEACH, PEACH, 0, 0, 4))
	l.add_theme_stylebox_override("selected_focus", _sb(PEACH, PEACH, 0, 0, 4))
	l.add_theme_stylebox_override("hovered", _sb(PLATE_HI, Color(0, 0, 0, 0), 0, 0, 4))


func _sec(t: String) -> Label:
	var l := Label.new()
	l.text = "// " + " ".join(t.split(""))
	_style_label(l, 15, PEACH)
	return l


func _note(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(l, 13, DIM)
	return l


func _btn(t: String, cb: Callable, accent: Color = PEACH) -> Button:
	var b := Button.new()
	b.text = t
	_style_button(b, accent)
	b.pressed.connect(cb)
	return b


func _toggle(t: String, init: bool, cb: Callable, key: String = "") -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = true
	b.button_pressed = init
	_style_button(b)
	b.toggled.connect(cb)
	if key != "":
		if not _toggles.has(key):
			_toggles[key] = []
		(_toggles[key] as Array).append(b)
	return b


func _grid(items: Array, cols: int = 3) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		(it as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(it)
	return g
