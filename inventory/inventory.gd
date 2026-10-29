extends Node
## Autoload dengan nama "Inventory" (taruh SEBELUM InventoryUI di daftar Autoload).
## Inventory gaya Resident Evil 4: case berbentuk grid, tiap item punya ukuran (w x h),
## bisa diputar dan dipindah. Item yang sama bisa ditumpuk dalam satu penempatan.

signal inventory_changed
signal item_added(item: ItemData, amount: int)
signal item_removed(item: ItemData, amount: int)
signal item_used(item: ItemData)
signal item_discarded(item: ItemData, amount: int, rounds: int)   # dibuang dari case (LootManager menjatuhkannya ke lantai)
signal ammo_collected(ammo_type: StringName, amount: int)
signal message(text: String)           # notifikasi singkat (HUD + layar inventory)

@export var cols: int = 10
@export var rows: int = 6

## Tiap entry: {"data": ItemData, "amount": int, "x": int, "y": int, "rot": int (0..3)}
var entries: Array = []

## Diisi oleh player. Mengembalikan "" kalau item boleh dipakai, atau alasan penolakan
## (mis. "HP sudah penuh"). Tidak diisi = selalu boleh.
var can_use_item: Callable


# ---------------------------------------------------------------- geometri

var _cell_cache := {}


func is_shaped(item: ItemData) -> bool:
	return not item.shape.is_empty()


## Kotak yang dipakai item setelah diputar rot x 90 derajat, digeser supaya mulai dari (0,0).
## Bentuk khusus (item.shape) atau persegi panjang grid_w x grid_h.
func cells_of(item: ItemData, rot: int) -> Array:
	var r := posmod(rot, 4)
	var key := str(item.get_instance_id()) + ":" + str(r)
	if _cell_cache.has(key):
		return _cell_cache[key]
	var cells: Array = []
	if is_shaped(item):
		for c in item.shape:
			cells.append(c)
	else:
		for y in item.grid_h:
			for x in item.grid_w:
				cells.append(Vector2i(x, y))
	for i in r:
		var t: Array = []
		for c in cells:
			t.append(Vector2i(-c.y, c.x))
		cells = t
	var mn := Vector2i(9999, 9999)
	for c in cells:
		mn.x = mini(mn.x, c.x)
		mn.y = mini(mn.y, c.y)
	var res: Array = []
	for c in cells:
		res.append(c - mn)
	_cell_cache[key] = res
	return res


## Ukuran kotak pembatas item setelah diputar.
func footprint(item: ItemData, rot: int) -> Vector2i:
	if not is_shaped(item):
		return Vector2i(item.grid_h, item.grid_w) if posmod(rot, 2) == 1 else Vector2i(item.grid_w, item.grid_h)
	var mx := 0
	var my := 0
	for c in cells_of(item, rot):
		mx = maxi(mx, c.x + 1)
		my = maxi(my, c.y + 1)
	return Vector2i(mx, my)


func can_rotate(item: ItemData) -> bool:
	if not item.allow_rotate:
		return false
	return is_shaped(item) or item.grid_w != item.grid_h


## Putaran berikutnya: bentuk khusus 4 arah, persegi panjang 2 arah.
func next_rot(item: ItemData, rot: int) -> int:
	if not can_rotate(item):
		return rot
	if is_shaped(item):
		return (rot + 1) % 4
	return 1 - posmod(rot, 2)


func rect_of(entry: Dictionary) -> Rect2i:
	var s := footprint(entry["data"], entry["rot"])
	return Rect2i(entry["x"], entry["y"], s.x, s.y)


## Entry yang menutupi kotak (x, y), atau null.
func entry_at(x: int, y: int):
	var p := Vector2i(x, y)
	for e in entries:
		var o := Vector2i(e["x"], e["y"])
		for c in cells_of(e["data"], e["rot"]):
			if o + c == p:
				return e
	return null


func _occupancy(ignore = null) -> Array:
	var occ: Array = []
	occ.resize(cols * rows)
	occ.fill(false)
	for e in entries:
		if ignore != null and is_same(e, ignore):
			continue
		_mark(occ, Vector2i(e["x"], e["y"]), cells_of(e["data"], e["rot"]))
	return occ


func _mark(occ: Array, origin: Vector2i, cells: Array) -> void:
	for c in cells:
		var p: Vector2i = origin + c
		occ[p.y * cols + p.x] = true


func _fits(occ: Array, origin: Vector2i, cells: Array) -> bool:
	for c in cells:
		var p: Vector2i = origin + c
		if p.x < 0 or p.y < 0 or p.x >= cols or p.y >= rows:
			return false
		if occ[p.y * cols + p.x]:
			return false
	return true


func can_place(item: ItemData, x: int, y: int, rot: int, ignore = null) -> bool:
	return _fits(_occupancy(ignore), Vector2i(x, y), cells_of(item, rot))


func _find_spot(item: ItemData, occ: Array) -> Dictionary:
	var rots: Array = [0]
	if can_rotate(item):
		rots = [0, 1, 2, 3] if is_shaped(item) else [0, 1]
	for rot in rots:
		var cells := cells_of(item, rot)
		var s := footprint(item, rot)
		for y in range(rows - s.y + 1):
			for x in range(cols - s.x + 1):
				if _fits(occ, Vector2i(x, y), cells):
					return {"x": x, "y": y, "rot": rot}
	return {}


func _index_of(entry) -> int:
	for i in entries.size():
		if is_same(entries[i], entry):
			return i
	return -1


# ---------------------------------------------------------------- tambah

func add_item(item: ItemData, amount: int = 1, rounds: int = -1) -> bool:
	if item == null or amount <= 0:
		return false

	if not _can_fit(item, amount):
		message.emit("Case penuh")
		return false

	var left := amount

	# 1) isi tumpukan yang sudah ada
	if item.stackable:
		for e in entries:
			if left <= 0:
				break
			if e["data"].id == item.id and e["amount"] < item.max_stack:
				var add := mini(item.max_stack - e["amount"], left)
				e["amount"] += add
				left -= add

	# 2) sisanya ditaruh di kotak kosong pertama yang muat (otomatis diputar kalau perlu)
	while left > 0:
		var spot := _find_spot(item, _occupancy())
		var put := mini(left, item.max_stack if item.stackable else 1)
		var entry := {"data": item, "amount": put, "x": spot["x"], "y": spot["y"], "rot": spot["rot"]}
		if item.type == ItemData.Type.AMMO:
			entry["rounds"] = rounds if rounds >= 0 else item.mag_rounds     # isi magazine (berkurang saat dipakai reload)
		entries.append(entry)
		left -= put

	item_added.emit(item, amount)
	inventory_changed.emit()
	if amount > 1:
		message.emit("Mengambil: %s x%d" % [item.display_name, amount])
	else:
		message.emit("Mengambil: %s" % item.display_name)
	return true


func _can_fit(item: ItemData, amount: int) -> bool:
	var left := amount
	if item.stackable:
		for e in entries:
			if e["data"].id == item.id:
				left -= item.max_stack - e["amount"]
	if left <= 0:
		return true
	var occ := _occupancy()
	var per := item.max_stack if item.stackable else 1
	while left > 0:
		var spot := _find_spot(item, occ)
		if spot.is_empty():
			return false
		_mark(occ, Vector2i(spot["x"], spot["y"]), cells_of(item, spot["rot"]))
		left -= per
	return true


# ---------------------------------------------------------------- cek / ambil

func find_entry(id: StringName):
	for e in entries:
		if e["data"].id == id:
			return e
	return null


func get_amount(id: StringName) -> int:
	var total := 0
	for e in entries:
		if e["data"].id == id:
			total += e["amount"]
	return total


func has_item(id: StringName, amount: int = 1) -> bool:
	return get_amount(id) >= amount


func remove_entry(entry: Dictionary, amount: int = 1) -> void:
	var idx := _index_of(entry)
	if idx == -1:
		return
	var data: ItemData = entry["data"]
	entry["amount"] -= amount
	if entry["amount"] <= 0:
		entries.remove_at(idx)
	item_removed.emit(data, amount)
	inventory_changed.emit()



func remove_item(id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return false

	if not has_item(id, amount):
		return false

	var left: int = amount

	while left > 0:
		var e = find_entry(id)

		if e == null:
			push_warning("Entry tidak ditemukan: " + str(id))
			return false

		if not e is Dictionary:
			push_warning("Entry bukan Dictionary: " + str(id))
			return false

		if not e.has("amount"):
			push_warning("Entry tidak memiliki key amount: " + str(id))
			return false

		var take: int = mini(int(e["amount"]), left)

		if take <= 0:
			push_warning("Jumlah item tidak valid: " + str(id))
			return false

		remove_entry(e, take)
		left -= take

	return true



func discard_entry(entry: Dictionary) -> void:
	var data: ItemData = entry["data"]
	var amount: int = entry["amount"]
	var rounds: int = int(entry.get("rounds", -1))
	remove_entry(entry, amount)
	item_discarded.emit(data, amount, rounds)
	message.emit("Dibuang: %s" % data.display_name)


# ---------------------------------------------------------------- pindah / gabung

func move_entry(entry: Dictionary, x: int, y: int, rot: int) -> bool:
	if not can_place(entry["data"], x, y, rot, entry):
		return false
	entry["x"] = x
	entry["y"] = y
	entry["rot"] = rot
	inventory_changed.emit()
	return true


## Gabungkan tumpukan src ke dst (item sama). Mengembalikan true kalau ada yang dipindah.
func merge_entries(src: Dictionary, dst: Dictionary) -> bool:
	if is_same(src, dst) or src["data"].id != dst["data"].id or not src["data"].stackable:
		return false
	var space: int = dst["data"].max_stack - dst["amount"]
	if space <= 0:
		return false
	var moved := mini(space, src["amount"])
	dst["amount"] += moved
	src["amount"] -= moved
	if src["amount"] <= 0:
		var idx := _index_of(src)
		if idx != -1:
			entries.remove_at(idx)
	inventory_changed.emit()
	return true


# ---------------------------------------------------------------- peluru (magazine)

## Total peluru di semua magazine bertipe ammo_type.
func count_rounds(ammo_type: StringName) -> int:
	var n := 0
	for e in entries:
		var d: ItemData = e["data"]
		if d.type == ItemData.Type.AMMO and d.ammo_type == ammo_type:
			n += int(e.get("rounds", d.mag_rounds))
	return n


## Ambil peluru dari magazine (yang isinya paling sedikit dulu). Magazine kosong hilang dari case.
## Mengembalikan jumlah yang benar-benar terambil.
func take_rounds(ammo_type: StringName, amount: int) -> int:
	var mags: Array = []
	for e in entries:
		var d: ItemData = e["data"]
		if d.type == ItemData.Type.AMMO and d.ammo_type == ammo_type:
			mags.append(e)
	mags.sort_custom(func(a, b): return int(a.get("rounds", 0)) < int(b.get("rounds", 0)))
	var left := amount
	for e in mags:
		if left <= 0:
			break
		var r := int(e.get("rounds", e["data"].mag_rounds))
		var take := mini(r, left)
		e["rounds"] = r - take
		left -= take
		if int(e["rounds"]) <= 0:
			var idx := _index_of(e)
			if idx != -1:
				entries.remove_at(idx)
			item_removed.emit(e["data"], 1)
	if left < amount:
		inventory_changed.emit()
	return amount - left


# ---------------------------------------------------------------- pakai

func use_entry(entry) -> bool:
	if entry == null:
		return false
	var item: ItemData = entry["data"]
	if item.type != ItemData.Type.CONSUMABLE:
		message.emit("Item ini tidak bisa dipakai")
		return false
	if can_use_item.is_valid():
		var reason: String = can_use_item.call(item)
		if reason != "":
			message.emit(reason)
			return false
	item_used.emit(item)
	remove_entry(entry, 1)
	return true


## Pakai item pertama dengan id tertentu (untuk tombol pintas).
func use_item(id: StringName) -> bool:
	return use_entry(find_entry(id))


func clear() -> void:
	entries.clear()
	inventory_changed.emit()
