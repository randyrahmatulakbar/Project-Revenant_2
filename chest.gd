class_name LootChest
extends StaticBody3D
## CRATE. Tekan interact -> membuka UI crate (ChestScreen). Isi diacak saat pertama dibuka (atau isi manual lewat `items`).
## Animasi reveal hanya main saat PERTAMA dibuka; buka berikutnya isinya langsung tampil.
##
## Pasang pada StaticBody3D yang punya CollisionShape3D (sedikit LEBIH BESAR dari model crate, supaya raycast pemain kena ini dulu).
## Belum diuji di Godot (aku tidak bisa menjalankannya).

signal opened
signal closed

const PICK_LAYER: int = 1 << 19

@export var interact_text := "OPEN CRATE"
@export_range(1, 8, 1) var chest_rows := 4                 # tinggi grid crate (lebarnya = Inventory.cols)
@export_range(0, 12, 1) var min_items := 3
@export_range(0, 12, 1) var max_items := 6
@export var items: Array[ItemData] = []                    # diisi = isi MANUAL (tidak diacak)
@export_group("Tutup")
@export var lid_paths: Array[NodePath] = []                # node CSG yang jadi tutup (mis. ../Crate7 dan ../light)
@export var lid_impulse := 4.5                             # kecepatan lontar ke atas
@export var lid_side := 1.0                                # sebaran sisi acak
@export var lid_spin := 5.0                                # putaran acak
@export var lid_mass := 3.0
@export var lid_lifetime := 20.0                           # detik sejak dilempar sebelum tutup mulai memudar (0 = tidak pernah hilang)
@export var lid_fade_time := 1.5                            # lama memudar (detik), lalu tutup dihapus
@export var ui_delay := 0.45                               # jeda sebelum UI muncul (detik), supaya lontaran terlihat
@export_group("Penanda")
@export var marker_enabled := true                         # bracket + cahaya peach berkedip supaya beda dari crate dekorasi
@export var marker_color := Color("dea68a")
@export var marker_size := Vector3(1.3, 1.3, 1.3)          # kotak yang dibingkai (sedikit lebih besar dari crate)
@export var marker_offset := Vector3(0.0, -0.13, 0.0)      # geser dari titik node ini ke pusat crate
@export var marker_brackets := false                       # true = tambah siku (outline) di sudut crate
@export var marker_bracket := 0.3                          # panjang siku sudut
@export var marker_thickness := 0.035
@export var marker_light := true
@export_group("Acak")
@export var consumable_weight := 1.0
@export var ammo_weight := 0.8
@export var equipment_weight := 0.15
@export var weapon_weight := 0.0                           # 0 = senjata tidak pernah muncul
@export var other_weight := 0.3
@export var catalog_path := ""                             # kosong = cari item_catalog.gd otomatis

## Tiap entry (format sama dengan Inventory.entries): {"data","amount","x","y","rot", "rounds"(ammo)}
var contents: Array = []
var generated := false
var opened_once := false
var anim_started := false                                   # dipakai ChestScreen untuk melanjutkan animasi reveal
var anim_elapsed := 0.0
var anim_total := 0.0
var _lid_thrown := false
var _opening := false
var _marker: Node3D = null
var _marker_mat: StandardMaterial3D = null
var _marker_lamp: OmniLight3D = null

static var _catalog = null


func _ready() -> void:
	collision_layer = PICK_LAYER
	collision_mask = 0
	if marker_enabled:
		_build_marker()
	else:
		set_process(false)


# ------------------------------------------------------------------ penanda (beda dari crate dekorasi)

func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "Marker"
	_marker.position = marker_offset
	add_child(_marker)

	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = marker_color
	var h := marker_size * 0.5
	if marker_brackets:

		var bar := BoxMesh.new()
		bar.size = Vector3.ONE
		bar.material = _marker_mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bar
		mm.instance_count = 24
		var l := marker_bracket
		var t := marker_thickness
		var i := 0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c := Vector3(sx * h.x, sy * h.y, sz * h.z)
					mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(l, t, t)), c - Vector3(sx * l * 0.5, 0.0, 0.0)))
					mm.set_instance_transform(i + 1, Transform3D(Basis.from_scale(Vector3(t, l, t)), c - Vector3(0.0, sy * l * 0.5, 0.0)))
					mm.set_instance_transform(i + 2, Transform3D(Basis.from_scale(Vector3(t, t, l)), c - Vector3(0.0, 0.0, sz * l * 0.5)))
					i += 3
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker.add_child(mmi)

	if marker_light:
		_marker_lamp = OmniLight3D.new()
		_marker_lamp.light_color = marker_color
		_marker_lamp.omni_range = 3.6
		_marker_lamp.light_energy = 0.8
		_marker_lamp.shadow_enabled = false
		_marker_lamp.position = Vector3(0.0, h.y + 0.25, 0.0)
		_marker.add_child(_marker_lamp)


func _process(_delta: float) -> void:
	if _marker == null:
		set_process(false)
		return
	if generated and contents.is_empty():               # sudah dikosongkan -> penanda hilang
		_marker.queue_free()
		_marker = null
		set_process(false)
		return
	var f := floorf(float(Time.get_ticks_msec()) / 1000.0 * 12.0)      # berkedip patah-patah 12 FPS
	var p := 0.5 + 0.5 * sin(f * 0.45)
	var k := 0.55 + 0.45 * p
	_marker_mat.albedo_color = Color(marker_color.r * k, marker_color.g * k, marker_color.b * k)
	if _marker_lamp != null:
		_marker_lamp.light_energy = 0.7 + 1.3 * p


func interact() -> void:
	if _opening:
		return
	if not generated:
		_generate()
	if not _lid_thrown and lid_paths.size() > 0:
		_throw_lid()
		_opening = true
		await get_tree().create_timer(ui_delay).timeout
		_opening = false
	var root := get_tree().root
	var ui = root.get_node_or_null("ChestScreen")
	if ui == null:
		ui = ChestScreen.new()
		ui.name = "ChestScreen"
		root.add_child(ui)
	ui.open_chest(self)


# ------------------------------------------------------------------ tutup crate (fisika asli, bukan animasi)

## Tutup dijadikan RigidBody3D lalu ditendang ke atas. Setelah diam, dibekukan dan tidak lagi menghalangi raycast.
func _throw_lid() -> void:
	_lid_thrown = true
	var parts: Array[Node3D] = []
	for p in lid_paths:
		var n := get_node_or_null(p) as Node3D
		if n != null:
			parts.append(n)
	if parts.is_empty():
		return
	var host := get_parent()
	var body := RigidBody3D.new()
	body.name = "CrateLid"
	body.mass = lid_mass
	body.continuous_cd = true
	body.collision_layer = 1 << 20            # layer sendiri, supaya pemain tidak terdorong
	body.collision_mask = 1                   # menabrak dunia
	body.process_mode = Node.PROCESS_MODE_ALWAYS   # tetap jalan walau UI crate mem-pause game
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.8
	body.physics_material_override = pm
	host.add_child(body)
	var base: Transform3D = parts[0].global_transform
	base.basis = base.basis.orthonormalized()
	body.global_transform = base
	for part in parts:
		var gt: Transform3D = part.global_transform
		var sc: Vector3 = gt.basis.get_scale().abs()
		var csg := part as CSGShape3D
		if csg != null:
			csg.use_collision = false         # tabrakan diganti collider body ini
		var sz := Vector3.ONE
		var box := part as CSGBox3D
		if box != null:
			sz = box.size
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz * sc
		cs.shape = shape
		body.add_child(cs)
		var ct: Transform3D = gt
		ct.basis = ct.basis.orthonormalized()
		cs.global_transform = ct
		part.reparent(body)                   # global transform tetap
	body.sleeping_state_changed.connect(_on_lid_sleep.bind(body))
	if lid_lifetime > 0.0:
		var tw := body.create_tween()                   # terikat ke body (process ALWAYS), jadi tetap jalan saat game di-pause
		tw.tween_interval(lid_lifetime)
		tw.tween_method(_fade_lid.bind(parts), 0.0, 1.0, maxf(lid_fade_time, 0.05))
		tw.tween_callback(body.queue_free)
	var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * lid_side
	body.apply_central_impulse((Vector3.UP * lid_impulse + side) * lid_mass)
	body.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * lid_spin * lid_mass * 0.3)


func _fade_lid(v: float, parts: Array) -> void:
	for p in parts:
		if is_instance_valid(p):
			(p as GeometryInstance3D).transparency = v


func _on_lid_sleep(body: RigidBody3D) -> void:
	if body.sleeping:
		body.set_deferred("freeze_mode", RigidBody3D.FREEZE_MODE_STATIC)
		body.set_deferred("freeze", true)
		body.set_deferred("collision_layer", 0)


# ------------------------------------------------------------------ rarity (menyusul)

## HOOK: kembalikan 0..3 (0 biasa, 1 uncommon, 2 rare, 3 epic). Nanti isi sesuai daftar rarity-mu.
static func rarity_of(_item: ItemData) -> int:
	return 0


# ------------------------------------------------------------------ grid crate

static func make_entry(item: ItemData, amount: int, x: int, y: int, rot: int, rounds: int = -1) -> Dictionary:
	var e := {"data": item, "amount": amount, "x": x, "y": y, "rot": rot, "st": 4, "wipe": 1.0, "fx": 1.0}
	if item.type == ItemData.Type.AMMO:
		e["rounds"] = rounds if rounds >= 0 else item.mag_rounds
	return e


## Muat di grid crate pada (ax, ay) dengan putaran rot? `ignore` = entry yang diabaikan (saat dipindah).
func fits(item: ItemData, ax: int, ay: int, rot: int, ignore = null) -> bool:
	var taken := {}
	for e in contents:
		if ignore != null and is_same(e, ignore):
			continue
		var o := Vector2i(e["x"], e["y"])
		for c in Inventory.cells_of(e["data"], e["rot"]):
			taken[o + c] = true
	for c in Inventory.cells_of(item, rot):
		var p: Vector2i = Vector2i(ax, ay) + c
		if p.x < 0 or p.y < 0 or p.x >= Inventory.cols or p.y >= chest_rows or taken.has(p):
			return false
	return true


## Tempat kosong pertama (boleh diputar). {} kalau penuh.
func find_spot(item: ItemData) -> Dictionary:
	var rots: Array = [0]
	if Inventory.can_rotate(item):
		rots = [0, 1, 2, 3] if Inventory.is_shaped(item) else [0, 1]
	for rot in rots:
		var fp := Inventory.footprint(item, rot)
		for y in range(chest_rows - fp.y + 1):
			for x in range(Inventory.cols - fp.x + 1):
				if fits(item, x, y, rot):
					return {"x": x, "y": y, "rot": rot}
	return {}


func _pack(item: ItemData, amount: int) -> bool:
	var s := find_spot(item)
	if s.is_empty():
		return false
	contents.append(make_entry(item, amount, s["x"], s["y"], s["rot"]))
	return true


# ------------------------------------------------------------------ isi

func _generate() -> void:
	generated = true
	contents.clear()
	if items.size() > 0:
		for it in items:
			if it != null:
				_pack(it, 1)
		return

	var cat = _get_catalog()
	if cat == null:
		push_warning("LootChest: item_catalog.gd tidak ketemu, crate kosong. Isi `catalog_path` atau `items`.")
		return
	var cand: Array = []
	for id in cat.all_ids():
		var it: ItemData = cat.get_item(id)
		if it == null:
			continue
		var w := _weight(it)
		if w <= 0.0:
			continue
		if cat.is_unique(it) and Inventory.has_item(it.id):
			continue
		cand.append({"d": it, "w": w})

	var n := randi_range(mini(min_items, max_items), maxi(min_items, max_items))
	for _i in n:
		if cand.is_empty():
			break
		var total := 0.0
		for c in cand:
			total += c["w"]
		var roll := randf() * total
		var k := 0
		for j in cand.size():
			roll -= cand[j]["w"]
			if roll <= 0.0:
				k = j
				break
		var pick: ItemData = cand[k]["d"]
		if cat.is_unique(pick):
			cand.remove_at(k)
		var amt := 1
		if pick.stackable and pick.max_stack > 1:
			amt = randi_range(1, pick.max_stack)
		_pack(pick, amt)


func _weight(it: ItemData) -> float:
	match String(ItemData.Type.keys()[it.type]):
		"CONSUMABLE":
			return consumable_weight
		"AMMO":
			return ammo_weight
		"EQUIPMENT":
			return equipment_weight
		"WEAPON":
			return weapon_weight
	return other_weight


func _get_catalog():
	if _catalog != null:
		return _catalog
	var p := catalog_path
	if p == "" or not ResourceLoader.exists(p):
		p = _scan("res://", "item_catalog.gd", 0)
	if p != "":
		_catalog = load(p)
	return _catalog


static func _scan(dir: String, file: String, depth: int) -> String:
	if depth > 4:
		return ""
	for f in DirAccess.get_files_at(dir):
		if f.trim_suffix(".remap") == file:
			return dir.path_join(file)
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		var r := _scan(dir.path_join(d), file, depth + 1)
		if r != "":
			return r
	return ""
