extends RefCounted
## DATABASE ITEM. Semua item game didefinisikan di sini (ukuran grid, jenis, stack).
## Dipakai lewat:  const ItemDB = preload("res://item_db.gd")
##   ItemDB.get_item("medkit") -> Dictionary  (kosong kalau id tidak ada)
##
## cells   = kotak yang dipakai item di grid (Vector2i(x, y)). Bentuk L / T cukup tulis daftar kotaknya.
## stack_max = berapa banyak per 1 slot item. per_drop = jumlah saat didrop musuh.
## ANGKA stack_max / per_drop di bawah masih tebakan, silakan ubah.

static var _db := {}


static func _rect(w: int, h: int) -> Array:
	var a := []
	for y in h:
		for x in w:
			a.append(Vector2i(x, y))
	return a


static func _def(id: String, nm: String, kind: String, cells: Array, desc: String,
		stack_max: int = 1, per_drop: int = 1, col: Color = Color.WHITE) -> void:
	_db[id] = {"id": id, "name": nm, "kind": kind, "cells": cells, "desc": desc,
			"stack_max": stack_max, "per_drop": per_drop, "color": col}


static func _build() -> void:
	if not _db.is_empty():
		return
	var green := Color(0.4, 0.9, 0.5)
	var amber := Color(1.0, 0.72, 0.25)
	var purple := Color(0.75, 0.5, 1.0)
	var steel := Color(0.7, 0.75, 0.85)
	# ---- USABLE ----
	_def("medkit", "Medkit", "usable", _rect(2, 2), "Pulihkan banyak darah.", 1, 1, green)
	_def("bandage", "Bandage", "usable", _rect(1, 2), "Pulihkan sedikit darah.", 3, 1, green)
	_def("ammo_revolver", "Revolver Ammo", "usable", _rect(1, 2), "Peluru revolver.", 18, 6, amber)
	_def("ammo_smg", "SMG Ammo", "usable", _rect(1, 2), "Peluru MP5.", 90, 30, amber)
	_def("ammo_shotgun", "Shotgun Shells", "usable", _rect(1, 3), "Peluru shotgun.", 24, 8, amber)
	_def("grenade", "Grenade", "usable", _rect(1, 2), "Lempar, meledak di area.", 3, 1, Color(0.8, 0.9, 0.5))
	_def("molotov", "Molotov", "usable", _rect(1, 3), "Lempar, membakar area.", 3, 1, Color(1.0, 0.5, 0.2))
	_def("adrenaline", "Adrenaline Shot", "usable", _rect(1, 2), "Gerak lebih cepat sebentar.", 2, 1, Color(1.0, 0.5, 0.6))
	_def("poison_dissolver", "Poison Dissolver", "usable", _rect(1, 1), "Hapus efek poison.", 3, 1, Color(0.55, 0.9, 0.3))
	# ---- EQUIPMENT (cuma boleh 1) ----
	_def("trigger", "Trigger", "equipment", _rect(2, 2),
			"Revolver: tahan tembak untuk charge shot. Peluru lebih kencang, lebih sakit, dan memantul ke musuh lain.", 1, 1, purple)
	_def("extended_mag", "Extended Mag", "equipment", _rect(1, 2),
			"Total magazine revolver dan SMG +50%.", 1, 1, purple)
	_def("parry_sigil", "Parry Sigil", "equipment", _rect(1, 3),
			"Jendela parry lebih lebar, tapi damage tembakan biasa turun.", 1, 1, purple)
	_def("leapers_claw", "Leaper's Claw", "equipment",
			[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],                      # bentuk L (3 kotak)
			"Wallhop lebih tinggi dan satu wallhop tambahan.", 1, 1, purple)
	_def("borrowed_time", "Borrowed Time", "equipment", _rect(2, 2),
			"Satu kali mati diganti hidup kembali 25% HP, lalu artefak hancur.", 1, 1, purple)
	_def("ember_core", "Ember Core", "equipment",
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],      # bentuk T (4 kotak)
			"Musuh mati bisa meledak kecil (dengan peluang dan cooldown). Ledakan bisa melukai kamu.", 1, 1, purple)
	# ---- WEAPON (cuma boleh 1) ----
	_def("mp5", "MP5", "weapon", _rect(2, 4), "Senapan serbu ringan.", 1, 1, steel)
	_def("shotgun", "Shotgun", "weapon", _rect(2, 6), "Tembakan jarak dekat yang berat.", 1, 1, steel)


static func get_item(id: String) -> Dictionary:
	_build()
	return _db.get(id, {})


static func all_ids() -> Array:
	_build()
	return _db.keys()


## Item yang cuma boleh dimiliki satu (equipment dan weapon)
static func is_unique(d: Dictionary) -> bool:
	return d.get("kind", "") == "equipment" or d.get("kind", "") == "weapon"


## Bentuk setelah diputar r x 90 derajat, digeser supaya mulai dari (0,0)
static func rotated(cells: Array, r: int) -> Array:
	var out := cells.duplicate()
	for i in (r % 4):
		var t := []
		for c in out:
			t.append(Vector2i(-c.y, c.x))
		out = t
	var mn := Vector2i(9999, 9999)
	for c in out:
		mn.x = mini(mn.x, c.x)
		mn.y = mini(mn.y, c.y)
	var res := []
	for c in out:
		res.append(c - mn)
	return res
