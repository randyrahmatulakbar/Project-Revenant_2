extends Node
## JEMBATAN PELURU: magazine di Inventory (grid) <-> cadangan peluru player.
##   - reserve_ammo player = total peluru di semua magazine bertipe ammo_type di Inventory.
##   - Saat player reload dan reserve_ammo berkurang, peluru diambil dari magazine (yang paling sedikit isinya dulu).
##     Magazine yang habis hilang dari case.
##   - Case juga di-reset tiap scene game dimuat (restart / mati), lalu diisi magazine awal.
##   - Tidak perlu mengubah script player. Cukup ada variabel reserve_ammo (dan _update_ammo_ui kalau ada).
## Dibuat otomatis oleh LootManager. Boleh juga ditaruh manual sebagai Node biasa.

const Catalog = preload("item_catalog.gd")

@export var enabled := true
## Tipe peluru revolver. HARUS sama dengan ammo_type_revolver di LootManager.
@export var ammo_type: StringName = &"pistol"
## Magazine awal setiap kali game dimulai / diulang.
@export var starting_mags := 4
@export var starting_item_id := "ammo_revolver"

## EXTENDED MAG: kalau item ini ada di case, cadangan peluru ditampilkan +50% (dan pemakaiannya dihitung ulang).
@export_group("EXTENDED MAG")
@export var extended_enabled := false      # false = bonusnya berupa magazine asli (lihat item_effects.gd); true = hanya angka cadangan x1.5
@export var extended_bonus := 0.5
@export var extended_types: Array[StringName] = [&"pistol", &"smg"]
@export var extended_item_id: StringName = &"extended_mag"

var _player: Node
var _mult_cur := 1.0
var _last := 0
var _dirty := true


func _ready() -> void:
	add_to_group("ammo_bridge")
	if not enabled:
		set_process(false)
		return
	# Setiap kali scene game dimuat (mulai baru, restart, mati lalu ulang) case dikosongkan dan diisi bekal awal.
	# Kalau suatu saat pindah level dan case harus ikut: Engine.set_meta("keep_inventory", true) sebelum pindah scene.
	if Engine.has_meta("keep_inventory"):
		Engine.remove_meta("keep_inventory")
	else:
		Inventory.clear()
		if starting_mags > 0:
			var item := Catalog.get_item(starting_item_id)
			if item:
				var copy: ItemData = item.duplicate()
				copy.ammo_type = ammo_type
				Inventory.add_item(copy, starting_mags)
	Inventory.inventory_changed.connect(_on_changed)


func _on_changed() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null or not ("reserve_ammo" in _player):
			_player = null
			return
		_dirty = true
	if _dirty:
		_dirty = false
		_mult_cur = _mult()
		_last = int(round(float(Inventory.count_rounds(ammo_type)) * _mult_cur))
		_player.reserve_ammo = _last
		if _player.has_method("_update_ammo_ui"):
			_player.call("_update_ammo_ui")
		return
	var cur: int = _player.reserve_ammo
	if cur < _last:
		var used := _last - cur                              # peluru "tampilan" yang terpakai -> ubah ke peluru asli di magazine
		Inventory.take_rounds(ammo_type, int(ceil(float(used) / _mult_cur)))
	elif cur > _last:
		_dirty = true                                       # ada kode lain yang menambah reserve -> kembalikan sesuai magazine


func _mult() -> float:
	if extended_enabled and ammo_type in extended_types and Inventory.has_item(extended_item_id):
		return 1.0 + extended_bonus
	return 1.0
