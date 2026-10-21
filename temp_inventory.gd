extends Node
## INVENTORY SEMENTARA (grid ala Resident Evil, auto-susun, tanpa UI).
## Hanya supaya sistem loot bisa dites sebelum inventory aslimu jadi.
## Kalau tidak ada node di group "inventory", LootManager membuat satu otomatis.
##
## KONTRAK yang dibutuhkan loot dari inventory aslimu nanti (node masuk group "inventory"):
##   add_item(id: String, amount: int) -> int   # return sisa yang TIDAK muat (0 = semua masuk)
##   has_item(id: String) -> bool
##   can_fit(id: String) -> bool
##   owned_weapons() -> Array                   # mis. ["revolver", "mp5"]

const ItemDB = preload("res://item_db.gd")

signal item_added(id: String, amount: int)

@export var grid_w := 8
@export var grid_h := 6
@export var start_weapons: Array[String] = ["revolver"]
@export var debug_print := true

var stacks: Array = []            # tiap isi: {id, amount, pos: Vector2i, rot: int}
var _occ := {}                    # Vector2i -> stack


func _ready() -> void:
	add_to_group("inventory")


func has_item(id: String) -> bool:
	for s in stacks:
		if s.id == id:
			return true
	return false


func count_of(id: String) -> int:
	var n := 0
	for s in stacks:
		if s.id == id:
			n += int(s.amount)
	return n


func owned_weapons() -> Array:
	var w: Array = start_weapons.duplicate()
	for s in stacks:
		if ItemDB.get_item(s.id).get("kind", "") == "weapon":
			w.append(s.id)
	return w


func can_fit(id: String) -> bool:
	var d := ItemDB.get_item(id)
	if d.is_empty():
		return false
	if ItemDB.is_unique(d) and has_item(id):
		return false
	if int(d.stack_max) > 1:
		for s in stacks:
			if s.id == id and int(s.amount) < int(d.stack_max):
				return true
	return not _find_spot(d).is_empty()


func add_item(id: String, amount: int = 1) -> int:
	var d := ItemDB.get_item(id)
	if d.is_empty():
		push_warning("Inventory: item '%s' tidak ada di item_db.gd" % id)
		return amount
	if ItemDB.is_unique(d) and has_item(id):
		return amount
	var left := amount
	var smax := int(d.stack_max)
	if smax > 1:
		for s in stacks:
			if s.id == id and int(s.amount) < smax:
				var put := mini(left, smax - int(s.amount))
				s.amount = int(s.amount) + put
				left -= put
				if left <= 0:
					break
	while left > 0:
		var spot := _find_spot(d)
		if spot.is_empty():
			break
		var put2 := mini(left, smax)
		_place({"id": id, "amount": put2, "pos": spot.pos, "rot": spot.rot})
		left -= put2
	if left < amount:
		item_added.emit(id, amount - left)
		if debug_print:
			print_grid()
	return left


func remove_item(id: String, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	var left := amount
	for i in range(stacks.size() - 1, -1, -1):
		var s: Dictionary = stacks[i]
		if s.id != id:
			continue
		var take := mini(left, int(s.amount))
		s.amount = int(s.amount) - take
		left -= take
		if int(s.amount) <= 0:
			_unplace(s)
		if left <= 0:
			break
	return true


func _find_spot(d: Dictionary) -> Dictionary:
	var seen := []
	for rot in 4:
		var cells := ItemDB.rotated(d.cells, rot)
		var key := str(cells)
		if key in seen:
			continue
		seen.append(key)
		for y in grid_h:
			for x in grid_w:
				var ok := true
				for c in cells:
					var p: Vector2i = Vector2i(x, y) + c
					if p.x >= grid_w or p.y >= grid_h or _occ.has(p):
						ok = false
						break
				if ok:
					return {"pos": Vector2i(x, y), "rot": rot}
	return {}


func _place(s: Dictionary) -> void:
	var d := ItemDB.get_item(s.id)
	for c in ItemDB.rotated(d.cells, s.rot):
		_occ[s.pos + c] = s
	stacks.append(s)


func _unplace(s: Dictionary) -> void:
	for k in _occ.keys():
		if _occ[k] == s:
			_occ.erase(k)
	stacks.erase(s)


## Gambar grid di panel Output (buat ngecek)
func print_grid() -> void:
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var out := "--- INVENTORY %dx%d ---\n" % [grid_w, grid_h]
	for y in grid_h:
		var row := ""
		for x in grid_w:
			var s = _occ.get(Vector2i(x, y))
			row += (letters[stacks.find(s) % 26] if s else ".")
		out += row + "\n"
	for i in stacks.size():
		out += "%s = %s x%d\n" % [letters[i % 26], stacks[i].id, stacks[i].amount]
	print(out)
