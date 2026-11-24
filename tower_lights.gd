extends Node3D
## LAMPU MENARA: 4 lampu di 4 sudut per tingkat, menyala 4 demi 4 dari bawah ke atas begitu pemain masuk menara.
##
## Struktur node (sudah ada di parkour_room.tscn, node "TowerLights"):
##   TowerLights (script ini)
##     Trigger  (Area3D, kotak seluruh ruangan menara (R4 bagian atas, z -105 sampai -137): pemain masuk -> urutan mulai, sekali saja)
##     Level1 .. Level4  (Node3D, urutan nyala = urutan anak)
##       L?_WS / ES / WN / EN  (Node3D, 4 sudut)  ->  Light (OmniLight3D), Housing, Glow (MeshInstance3D)
## Mau tambah tingkat? Duplikat satu Level, geser Y-nya, beri nama LevelN. Otomatis ikut.
## Nyalanya per frame (12 FPS, kedip kasar) supaya cocok dengan gaya HUD-mu.
##
## Belum diuji di Godot (aku tidak bisa menjalankannya).

@export var enabled := true                       # kill switch: false = semua lampu langsung menyala, tanpa urutan
@export var level_delay := 0.55                   # jeda antar tingkat (detik)
@export var fps := 12.0                           # kecepatan kedip (frame per detik)
@export var ignite_pattern: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 0.1, 1.0, 0.45, 1.0])   # kecerahan per frame saat menyala
@export var trigger_path := NodePath("Trigger")
@export var sfx_name := ""                        # opsional: nama suara di grup "sfx" (kosong = tanpa suara)

var _levels: Array = []                           # tiap isi: {"lights": [], "energy": [], "glows": []}
var _started := false


func _ready() -> void:
	for lv in get_children():
		if not (lv is Node3D) or not String(lv.name).begins_with("Level"):
			continue
		var d := {"lights": [], "energy": [], "glows": []}
		for l in lv.find_children("*", "OmniLight3D", true, false):
			d["lights"].append(l)
			d["energy"].append((l as OmniLight3D).light_energy)
		for g in lv.find_children("Glow*", "MeshInstance3D", true, false):
			d["glows"].append(g)
		_levels.append(d)
	if not enabled:
		return                                    # semua tetap menyala seperti di editor
	_set_level(_levels, 0.0, true)                # gelap dulu
	var t := get_node_or_null(trigger_path) as Area3D
	if t == null:
		push_warning("TowerLights: node Trigger tidak ketemu, lampu tidak akan menyala. Cek trigger_path.")
		return
	t.body_entered.connect(_on_body)


func _on_body(b: Node) -> void:
	if _started:
		return
	if not (b is CharacterBody3D and b.has_node("Health")):      # sama dengan pengecekan pemain di parkour_room.gd
		return
	_started = true
	if sfx_name != "":
		get_tree().call_group("sfx", "play", sfx_name)
	for lv in _levels:
		_ignite(lv)                               # jalan sendiri-sendiri (tidak di-await)
		await get_tree().create_timer(level_delay).timeout
		if not is_inside_tree():
			return


func _ignite(lv: Dictionary) -> void:
	for v in ignite_pattern:
		_apply(lv, v)
		await get_tree().create_timer(1.0 / maxf(fps, 1.0)).timeout
		if not is_inside_tree():
			return
	_apply(lv, 1.0)


func _apply(lv: Dictionary, k: float) -> void:
	var lights: Array = lv["lights"]
	var energy: Array = lv["energy"]
	for i in lights.size():
		var l := lights[i] as OmniLight3D
		if l == null:
			continue
		l.visible = k > 0.01
		l.light_energy = float(energy[i]) * k
	for g in lv["glows"]:
		(g as MeshInstance3D).visible = k > 0.5


func _set_level(levels: Array, k: float, _all: bool) -> void:
	for lv in levels:
		_apply(lv, k)
