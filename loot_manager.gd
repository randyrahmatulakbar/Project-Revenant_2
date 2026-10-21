extends Node
## LOOT: musuh mati -> kemungkinan drop tumpukan loot -> dekati -> muncul panel kecil di kanan layar.
##   Roda mouse / panah atas-bawah = pilih barang,  tekan interact = ambil,  TAHAN interact = ambil semua.
## Pasang: tambah Node biasa bernama LootManager di intro.tscn, pasang script ini. Selesai.
## Butuh file: item_db.gd, loot_drop.gd, loot_panel.gd, temp_inventory.gd (semua di res://).
## Kalau tidak ada inventory (node di group "inventory"), dibuat inventory sementara otomatis.

const ItemDB = preload("res://item_db.gd")
const LootDrop = preload("res://loot_drop.gd")
const LootPanel = preload("res://loot_panel.gd")
const TempInventory = preload("res://temp_inventory.gd")

@export_group("KILL SWITCH")
@export var enabled := true
@export_group("Pengaturan")
@export var chance_scale := 1.0              # pengali semua peluang (2.0 = dua kali lebih sering)
@export var pickup_range := 2.4
@export var hold_time := 0.45                # lama menahan interact untuk "ambil semua"
@export var drop_lifetime := 90.0            # detik sebelum hilang (0 = selamanya)
@export var merge_radius := 2.2              # drop yang jatuh sedekat ini dari tumpukan lain digabung ke tumpukan itu (0 = tidak digabung)
@export var drop_delay := 0.5                # jeda setelah musuh mati sebelum loot muncul
@export var assume_weapons: Array[String] = ["revolver"]   # dipakai kalau inventory tidak punya owned_weapons()
@export var debug_key: Key = KEY_F9          # tekan = loot berisi SEMUA item muncul di depanmu (buat tes). KEY_NONE = mati
@export var debug_inv_key: Key = KEY_F10     # tekan = cetak isi grid ke panel Output

## ATURAN DROP.  enemies: [] = semua musuh.  chance 0..1.
## item "ammo" khusus: drop amunisi untuk senjata yang SEDANG dimiliki (salah satu, acak).
const RULES := [
	{"item": "bandage", "enemies": ["flayer", "leaper"], "chance": 0.35},
	{"item": "ammo", "enemies": [], "chance": 0.70},
	{"item": "grenade", "enemies": ["mauler"], "chance": 0.12},
	{"item": "poison_dissolver", "enemies": ["spitter"], "chance": 0.12},
	{"item": "leapers_claw", "enemies": ["leaper"], "chance": 0.05},
]
const WEAPON_AMMO := {"revolver": "ammo_revolver", "mp5": "ammo_smg", "shotgun": "ammo_shotgun"}

var _player: Node3D
var _inv: Node
var _near: Node3D
var _sel := 0
var _holding := false
var _hold := 0.0
var _panel: PanelContainer
var _layer: CanvasLayer


func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_unhandled_input(false)
		return
	randomize()
	_layer = CanvasLayer.new()
	_layer.layer = 55
	add_child(_layer)
	_panel = LootPanel.new()
	_layer.add_child(_panel)
	_panel.set_keys(_key("interact"))
	get_tree().node_added.connect(_hook)
	for n in get_tree().get_nodes_in_group("enemy"):
		_hook(n)


# ---------- HOOK MUSUH ----------
func _hook(n: Node) -> void:
	if n is CharacterBody3D and n.has_signal("died") and n.has_method("_think"):
		if not n.died.is_connected(_on_enemy_died):
			n.died.connect(_on_enemy_died)


func _kind_of(n: Node) -> String:
	var s := (n.name + " " + n.scene_file_path).to_lower()
	var sc: Script = n.get_script()
	if sc:
		s += " " + sc.resource_path.to_lower()
	for k in ["flayer", "mauler", "leaper", "spitter"]:
		if k in s:
			return k
	return ""


func _on_enemy_died(enemy: Node) -> void:
	if not enabled or not is_instance_valid(enemy) or not is_inside_tree():
		return
	var kind := _kind_of(enemy)
	var pos: Vector3 = enemy.global_position
	var loot := roll_loot(kind)
	if loot.is_empty():
		return
	await get_tree().create_timer(drop_delay).timeout
	if is_inside_tree():
		spawn_drop(pos, loot)


# ---------- ROLL ----------
func roll_loot(kind: String) -> Array:
	var got := {}
	for r in RULES:
		var who: Array = r.enemies
		if not who.is_empty() and not (kind in who):
			continue
		if randf() > float(r.chance) * chance_scale:
			continue
		var id: String = r.item
		if id == "ammo":
			id = _pick_ammo()
			if id == "":
				continue
		var d := ItemDB.get_item(id)
		if d.is_empty():
			continue
		if ItemDB.is_unique(d) and (_has(id) or _in_world(id)):
			continue                                   # equipment/weapon yang sudah dimiliki tidak muncul lagi
		got[id] = int(got.get(id, 0)) + int(d.per_drop)
	var out := []
	for id in got:
		out.append({"id": id, "amount": got[id]})
	return out


func _pick_ammo() -> String:
	var opts := []
	for w in _owned():
		if WEAPON_AMMO.has(w):
			opts.append(WEAPON_AMMO[w])
	return "" if opts.is_empty() else str(opts.pick_random())


func _owned() -> Array:
	var inv := _get_inv(false)
	if inv and inv.has_method("owned_weapons"):
		return inv.owned_weapons()
	return assume_weapons


func _has(id: String) -> bool:
	var inv := _get_inv(false)
	return inv != null and inv.has_method("has_item") and inv.has_item(id)


func _in_world(id: String) -> bool:
	for d in get_tree().get_nodes_in_group("loot_drop"):
		if d.has_method("has_unique") and d.has_unique(id):
			return true
	return false


func _get_inv(create: bool) -> Node:
	if _inv and is_instance_valid(_inv):
		return _inv
	_inv = get_tree().get_first_node_in_group("inventory")
	if _inv == null and create:
		_inv = TempInventory.new()
		_inv.name = "TempInventory"
		add_child(_inv)
		print("LootManager: tidak ada inventory, memakai inventory sementara (grid %dx%d)." % [_inv.grid_w, _inv.grid_h])
	return _inv


# ---------- SPAWN ----------
func spawn_drop(pos: Vector3, items: Array) -> Node3D:
	if merge_radius > 0.0:
		var nearest: Node3D = null
		var best := merge_radius
		for d in get_tree().get_nodes_in_group("loot_drop"):
			if d.is_queued_for_deletion() or not d.has_method("add_items"):
				continue
			var dist := (d as Node3D).global_position.distance_to(pos)
			if dist < best:
				best = dist
				nearest = d
		if nearest:
			nearest.add_items(items)
			return nearest
	var drop := LootDrop.new()
	drop.items = items
	drop.lifetime = drop_lifetime
	get_tree().current_scene.add_child(drop)
	var from := pos + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0), 1)
	var hit := drop.get_world_3d().direct_space_state.intersect_ray(q)
	drop.global_position = (hit.position + Vector3(0, 0.3, 0)) if not hit.is_empty() else (pos + Vector3(0, 0.3, 0))
	return drop


# ---------- PANEL & INPUT ----------
func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var best_d := pickup_range
	var best: Node3D = null
	if _player:
		for d in get_tree().get_nodes_in_group("loot_drop"):
			if d.items.is_empty():
				continue
			var dist := _player.global_position.distance_to((d as Node3D).global_position)
			if dist < best_d:
				best_d = dist
				best = d
	if best != _near:
		_near = best
		_sel = 0
		_holding = false
		_hold = 0.0
		_panel.set_hold(0.0)
	if _near == null:
		_panel.visible = false
		return
	_sel = clampi(_sel, 0, _near.items.size() - 1)
	_panel.visible = true
	_panel.refresh(_near.items, _get_inv(true), _sel)
	if _holding:
		_hold += delta
		_panel.set_hold(_hold / maxf(hold_time, 0.05))
		if _hold >= hold_time:
			_holding = false
			_hold = 0.0
			_panel.set_hold(0.0)
			_take_all()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if debug_key != KEY_NONE and event.keycode == debug_key:
			_debug_spawn()
			return
		if debug_inv_key != KEY_NONE and event.keycode == debug_inv_key:
			var inv := _get_inv(true)
			if inv and inv.has_method("print_grid"):
				inv.print_grid()
			return
	if _near == null or not is_instance_valid(_near):
		return
	# pilih barang
	var step := 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP:
			step = -1
		elif event.keycode == KEY_DOWN:
			step = 1
	if step != 0 and _near.items.size() > 1:
		_sel = posmod(_sel + step, _near.items.size())
		get_viewport().set_input_as_handled()
		return
	# ambil: tekan = barang terpilih, tahan = semua
	if not InputMap.has_action("interact"):
		return
	if event.is_action_pressed("interact"):
		_holding = true
		_hold = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("interact") and _holding:
		_holding = false
		_hold = 0.0
		_panel.set_hold(0.0)
		_take_selected()


func _take_selected() -> void:
	if _near == null or _near.items.is_empty():
		return
	var inv := _get_inv(true)
	var it: Dictionary = _near.items[_sel]
	var left: int = inv.add_item(it.id, int(it.amount))
	if left >= int(it.amount):
		_panel.flash("Tidak muat di inventory.")
		return
	if left <= 0:
		_near.items.remove_at(_sel)
	else:
		it.amount = left
	_after_take()


func _take_all() -> void:
	if _near == null:
		return
	var inv := _get_inv(true)
	var i := 0
	var any := false
	while i < _near.items.size():
		var it: Dictionary = _near.items[i]
		var left: int = inv.add_item(it.id, int(it.amount))
		if left < int(it.amount):
			any = true
		if left <= 0:
			_near.items.remove_at(i)
		else:
			it.amount = left
			i += 1
	if not any:
		_panel.flash("Tidak ada yang muat.")
	_after_take()


func _after_take() -> void:
	if _near.items.is_empty():
		_near.queue_free()
		_near = null
		_panel.visible = false


func _debug_spawn() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	var items := []
	for id in ItemDB.all_ids():
		var d := ItemDB.get_item(id)
		items.append({"id": id, "amount": int(d.per_drop)})
	var f := -_player.global_transform.basis.z
	spawn_drop(_player.global_position + f * 1.6, items)


func _key(action: String) -> String:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				return OS.get_keycode_string(e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode)
	return "E"
