extends Node
## Autoload dengan nama "Inventory" (taruh SEBELUM InventoryUI di daftar Autoload).
## Inventory gaya Resident Evil 4: case berbentuk grid, tiap item punya ukuran (w x h),
## bisa diputar dan dipindah. Item yang sama bisa ditumpuk dalam satu penempatan.

signal inventory_changed
signal item_added(item: ItemData, amount: int)
signal item_removed(item: ItemData, amount: int)
signal item_used(item: ItemData)
signal ammo_collected(ammo_type: StringName, amount: int)
signal message(text: String)           # notifikasi singkat (HUD + layar inventory)

@export var cols: int = 8
@export var rows: int = 5

## Tiap entry: {"data": ItemData, "amount": int, "x": int, "y": int, "rot": bool}
var entries: Array = []

## Diisi oleh player. Mengembalikan "" kalau item boleh dipakai, atau alasan penolakan
## (mis. "HP sudah penuh"). Tidak diisi = selalu boleh.
var can_use_item: Callable


# ---------------------------------------------------------------- geometri

func footprint(item: ItemData, rot: bool) -> Vector2i:
	return Vector2i(item.grid_h, item.grid_w) if rot else Vector2i(item.grid_w, item.grid_h)


func rect_of(entry: Dictionary) -> Rect2i:
	var s := footprint(entry["data"], entry["rot"])
	return Rect2i(entry["x"], entry["y"], s.x, s.y)


## Entry yang menutupi kotak (x, y), atau null.
func entry_at(x: int, y: int):
	for e in entries:
		if rect_of(e).has_point(Vector2i(x, y)):
			return e
	return null


func _occupancy(ignore = null) -> Array:
	var occ: Array = []
	occ.resize(cols * rows)
	occ.fill(false)
	for e in entries:
		if ignore != null and is_same(e, ignore):
			continue
		_mark(occ, rect_of(e))
	return occ


func _mark(occ: Array, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			occ[y * cols + x] = true


func _fits(occ: Array, r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > cols or r.end.y > rows:
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if occ[y * cols + x]:
				return false
	return true


func can_place(item: ItemData, x: int, y: int, rot: bool, ignore = null) -> bool:
	var s := footprint(item, rot)
	return _fits(_occupancy(ignore), Rect2i(x, y, s.x, s.y))


func _find_spot(item: ItemData, occ: Array) -> Dictionary:
	for rot in [false, true]:
		if rot and (not item.allow_rotate or item.grid_w == item.grid_h):
			continue
		var s := footprint(item, rot)
		for y in range(rows - s.y + 1):
			for x in range(cols - s.x + 1):
				if _fits(occ, Rect2i(x, y, s.x, s.y)):
					return {"x": x, "y": y, "rot": rot}
	return {}


func _index_of(entry) -> int:
	for i in entries.size():
		if is_same(entries[i], entry):
			return i
	return -1


# ---------------------------------------------------------------- tambah

func add_item(item: ItemData, amount: int = 1) -> bool:
	if item == null or amount <= 0:
		return false

	# Kotak peluru tidak memakai ruang: langsung jadi cadangan peluru senjata
	if item.type == ItemData.Type.AMMO:
		var n := randi_range(item.ammo_min, item.ammo_max) * amount
		ammo_collected.emit(item.ammo_type, n)
		message.emit("+%d PELURU" % n)
		return true

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
		entries.append({"data": item, "amount": put, "x": spot["x"], "y": spot["y"], "rot": spot["rot"]})
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
		var s := footprint(item, spot["rot"])
		_mark(occ, Rect2i(spot["x"], spot["y"], s.x, s.y))
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
	var name_text: String = entry["data"].display_name
	remove_entry(entry, entry["amount"])
	message.emit("Dibuang: %s" % name_text)


# ---------------------------------------------------------------- pindah / gabung

func move_entry(entry: Dictionary, x: int, y: int, rot: bool) -> bool:
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
