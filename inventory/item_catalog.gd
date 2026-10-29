extends RefCounted
## KATALOG ITEM untuk sistem loot. Menghasilkan ItemData untuk sebuah id.
## 1) Kalau kamu sudah punya file .tres dengan id itu (folder di SEARCH_DIRS), yang dipakai adalah punyamu
##    (jadi ikon, deskripsi, dan angka dari kamu menang).
## 2) Kalau belum ada, dibuat otomatis dari TABLE di bawah. Jadi loot langsung jalan tanpa bikin .tres satu-satu.
## Dipakai lewat:  const Catalog = preload("res://inventory/item_catalog.gd")   (sesuaikan folder)

## true = ukuran/bentuk/heal/stack dari TABLE selalu menang atas file .tres (ikon & deskripsi tetap dari .tres).
## Matikan kalau mau ukuran murni dari .tres kamu.
const TABLE_WINS := true

const SEARCH_DIRS := ["res://inventory/items/", "res://items/", "res://inventory/"]
## Gambar item: <id>.png (16 piksel per kotak grid). Dicari di folder-folder ini.
const ICON_DIRS := ["res://inventory/icons/", "res://icons/", "res://inventory/items/icons/"]

## type: KEY / DOCUMENT / CONSUMABLE / AMMO / EQUIPMENT / WEAPON.   w x h = ukuran kotak (persegi panjang saja).
## Item peluru = 1 MAGAZINE: memakai kotak di case, tidak bisa ditumpuk, "mag" = isi peluru per magazine.
## ANGKA di sini masih tebakan, ubah sesuai gamemu.
const TABLE := [
	{"id": "medkit", "name": "Medkit", "type": "CONSUMABLE", "w": 2, "h": 2, "stack": 1, "heal": 35,
		"desc": "Pulihkan 35 HP."},
	{"id": "bandage", "name": "Bandage", "type": "CONSUMABLE", "w": 1, "h": 2, "stack": 3, "heal": 15,
		"desc": "Pulihkan 15 HP."},
	{"id": "grenade", "name": "Grenade", "type": "CONSUMABLE", "w": 1, "h": 2, "stack": 3,
		"desc": "Lempar, meledak di area."},
	{"id": "molotov", "name": "Molotov", "type": "CONSUMABLE", "w": 1, "h": 3, "stack": 3,
		"desc": "Lempar, membakar area."},
	{"id": "adrenaline", "name": "Adrenaline Shot", "type": "CONSUMABLE", "w": 1, "h": 2, "stack": 2,
		"desc": "Gerak lebih cepat sebentar."},
	{"id": "poison_dissolver", "name": "Poison Dissolver", "type": "CONSUMABLE", "w": 1, "h": 1, "stack": 3,
		"desc": "Hapus efek poison."},
	{"id": "ammo_revolver", "name": "Revolver Mag", "type": "AMMO", "w": 1, "h": 1, "stack": 1,
		"ammo_type": "pistol", "mag": 6, "desc": "Magazine revolver."},
	{"id": "ammo_smg", "name": "SMG Mag", "type": "AMMO", "w": 1, "h": 2, "stack": 1,
		"ammo_type": "smg", "mag": 30, "desc": "Magazine MP5."},
	{"id": "ammo_shotgun", "name": "Shotgun Shells", "type": "AMMO", "w": 1, "h": 3, "stack": 1,
		"ammo_type": "shotgun", "mag": 8, "desc": "Isi ulang shotgun."},
	# ---- EQUIPMENT. "shape" = bentuk khusus (daftar kotak); w x h = kotak pembatasnya.
	{"id": "trigger", "name": "Trigger", "type": "EQUIPMENT", "w": 2, "h": 2, "stack": 1,
		"desc": "Revolver: tahan tembak untuk charge shot. Peluru lebih kencang, lebih sakit, dan memantul ke musuh lain."},
	{"id": "extended_mag", "name": "Extended Mag", "type": "EQUIPMENT", "w": 1, "h": 2, "stack": 1,
		"desc": "Total magazine revolver dan SMG +50%."},
	{"id": "parry_sigil", "name": "Parry Sigil", "type": "EQUIPMENT", "w": 1, "h": 3, "stack": 1,
		"desc": "Jendela parry lebih lebar, tapi damage tembakan biasa turun."},
	{"id": "leapers_claw", "name": "Leaper's Claw", "type": "EQUIPMENT", "w": 2, "h": 2, "stack": 1,
		"shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],                  # L, 3 kotak
		"desc": "Wallhop lebih tinggi dan satu wallhop tambahan."},
	{"id": "borrowed_time", "name": "Borrowed Time", "type": "EQUIPMENT", "w": 2, "h": 2, "stack": 1,
		"desc": "Satu kali mati diganti hidup kembali 25% HP, lalu artefak hancur."},
	{"id": "ember_core", "name": "Ember Core", "type": "EQUIPMENT", "w": 3, "h": 2, "stack": 1,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],  # T, 4 kotak
		"desc": "Musuh mati bisa meledak kecil (ada peluang dan cooldown). Ledakan bisa melukai kamu."},
	# ---- WEAPON
	{"id": "mp5", "name": "MP5", "type": "WEAPON", "w": 2, "h": 4, "stack": 1, "desc": "Senapan serbu ringan."},
	{"id": "shotgun", "name": "Shotgun", "type": "WEAPON", "w": 2, "h": 6, "stack": 1, "desc": "Tembakan jarak dekat yang berat."},
]

static var _cache := {}
static var _index := {}
static var _scanned := false


static func get_item(id: String) -> ItemData:
	if _cache.has(id):
		return _cache[id]
	_scan()
	var it: ItemData = _index.get(id)
	if it == null:
		it = _build(id)
	elif TABLE_WINS:
		_apply_table(it)
	if it != null and it.icon == null:
		it.icon = _find_icon(id)
	_cache[id] = it
	return it


static func all_ids() -> Array:
	var out := []
	for t in TABLE:
		out.append(t.id)
	return out


static func is_unique(item: ItemData) -> bool:
	return item.type == ItemData.Type.EQUIPMENT or item.type == ItemData.Type.WEAPON


static func color_of(item: ItemData) -> Color:
	match item.type:
		ItemData.Type.CONSUMABLE:
			return Color(0.43, 0.68, 0.56)
		ItemData.Type.AMMO:
			return Color(0.87, 0.66, 0.4)
		ItemData.Type.EQUIPMENT:
			return Color(0.72, 0.55, 0.9)
		ItemData.Type.WEAPON:
			return Color(0.68, 0.74, 0.84)
	return Color(0.91, 0.86, 0.78)


static func size_text(item: ItemData, rounds: int = -1) -> String:
	if item.type == ItemData.Type.AMMO:
		return "%d PELURU   %dx%d" % [rounds if rounds >= 0 else item.mag_rounds, item.grid_w, item.grid_h]
	return "%dx%d" % [item.grid_w, item.grid_h]


# ---- internal ----
static func _find_icon(id: String) -> Texture2D:
	for dir in ICON_DIRS:
		var p: String = dir + id + ".png"
		if ResourceLoader.exists(p):
			return load(p)
	return null



static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for dir in SEARCH_DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			var fn: String = f.trim_suffix(".remap")
			if not fn.ends_with(".tres"):
				continue
			var r = load(dir + fn)
			if r is ItemData and not _index.has(String(r.id)):
				_index[String(r.id)] = r


static func _build(id: String) -> ItemData:
	for t in TABLE:
		if t.id != id:
			continue
		var it := ItemData.new()
		it.id = StringName(t.id)
		it.display_name = t.name
		it.description = t.desc
		it.type = ItemData.Type[t.type]
		it.grid_w = t.w
		it.grid_h = t.h
		it.max_stack = t.stack
		it.stackable = t.stack > 1
		it.heal_amount = int(t.get("heal", 0))
		if t.has("shape"):
			var sh: Array[Vector2i] = []
			for c in t.shape:
				sh.append(c)
			it.shape = sh
		if t.has("ammo_type"):
			it.ammo_type = StringName(t.ammo_type)
			it.mag_rounds = int(t.mag)
		return it
	push_warning("ItemCatalog: id '%s' tidak ada di TABLE maupun file .tres" % id)
	return null


static func _apply_table(it: ItemData) -> void:
	for t in TABLE:
		if t.id != String(it.id):
			continue
		it.grid_w = t.w
		it.grid_h = t.h
		it.max_stack = t.stack
		it.stackable = t.stack > 1
		if t.has("heal"):
			it.heal_amount = int(t.heal)
		var sh: Array[Vector2i] = []
		if t.has("shape"):
			for c in t.shape:
				sh.append(c)
		it.shape = sh
		if t.has("ammo_type"):
			it.ammo_type = StringName(t.ammo_type)
			it.mag_rounds = int(t.mag)
		return
