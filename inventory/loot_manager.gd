extends Node
## LOOT: musuh mati -> kemungkinan drop tumpukan loot -> dekati -> daftar kecil muncul di tengah-kanan layar.
## Tekan interact = ambil barang yang disorot. Tahan interact = ambil semua. Scroll mouse (atau panah) = pilih barang.
## Tersambung ke autoload Inventory-mu (add_item / has_item). Pasang: Node biasa "LootManager" di intro.tscn.
## Butuh file (satu folder): item_catalog.gd, loot_drop.gd, loot_panel.gd.

const Catalog = preload("item_catalog.gd")
const LootDrop = preload("loot_drop.gd")
const LootPanel = preload("loot_panel.gd")
const AmmoBridge = preload("ammo_bridge.gd")
const ItemEffects = preload("item_effects.gd")

@export_group("KILL SWITCH")
@export var enabled := true
@export_group("Pengaturan")
@export var chance_scale := 1.0              # pengali semua peluang (2.0 = dua kali lebih sering)
@export var pickup_range := 2.4
@export var take_all_hold := 0.6             # detik tahan interact untuk ambil semua
@export var merge_radius := 2.2              # drop sedekat ini digabung ke tumpukan yang ada (0 = tidak digabung)
@export var drop_lifetime := 90.0            # detik sebelum hilang (0 = selamanya)
@export var drop_delay := 0.5                # jeda setelah musuh mati sebelum loot muncul
@export var auto_ammo_bridge := true        # otomatis memasang ammo_bridge.gd (magazine <-> peluru player, reset case tiap mulai) dan item_effects.gd (heal medkit/bandage)
@export var debug_key: Key = KEY_F9          # tekan = loot berisi SEMUA item muncul di depanmu (tes). KEY_NONE = mati
@export var debug_inv_key: Key = KEY_F10     # tekan = cetak isi Inventory ke panel Output

@export_group("Peluru")
## Senjata yang SELALU dianggap dimiliki (revolver). MP5 / shotgun dianggap dimiliki kalau ada di Inventory.
@export var always_weapons: Array[String] = ["revolver"]
## ammo_type tiap peluru. HARUS sama dengan nama yang dipakai player-mu di sinyal Inventory.ammo_collected.
@export var ammo_type_revolver: StringName = &"pistol"
@export var ammo_type_smg: StringName = &"smg"
@export var ammo_type_shotgun: StringName = &"shotgun"

## ATURAN DROP.  enemies: [] = semua musuh.  chance 0..1.
## item "ammo" khusus: drop peluru untuk senjata yang SEDANG dimiliki (salah satu, acak).
const RULES := [
	{"item": "bandage", "enemies": ["flayer", "leaper"], "chance": 0.35},
	{"item": "ammo", "enemies": [], "chance": 0.70},
	{"item": "grenade", "enemies": ["mauler"], "chance": 0.12},
	{"item": "poison_dissolver", "enemies": ["spitter"], "chance": 0.12},
	{"item": "leapers_claw", "enemies": ["leaper"], "chance": 0.05},
]
const WEAPON_AMMO := {"revolver": "ammo_revolver", "mp5": "ammo_smg", "shotgun": "ammo_shotgun"}

var _player: Node3D
var _panel: Node
var _near: Node3D
var _shown: Node3D
var _sel := 0
var _hold := 0.0
var _holding := false


func _ready() -> void:
	if auto_ammo_bridge and get_tree().get_first_node_in_group("ammo_bridge") == null:
		add_child(AmmoBridge.new())
	if auto_ammo_bridge and get_tree().get_first_node_in_group("item_effects") == null:
		add_child(ItemEffects.new())
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS         # panel harus bisa disembunyikan saat game dijeda (inventory / pause)
	_panel = LootPanel.new()
	add_child(_panel)
	_panel.set_keys(_key("interact"))
	get_tree().node_added.connect(_hook)
	for n in get_tree().get_nodes_in_group("enemy"):
		_hook(n)
	Inventory.item_discarded.connect(_on_discarded)


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
		var item := Catalog.get_item(id)
		if item == null:
			continue
		if Catalog.is_unique(item) and (Inventory.has_item(item.id) or _in_world(item.id)):
			continue                                   # equipment / senjata yang sudah dimiliki tidak muncul lagi
		if item.type == ItemData.Type.AMMO:
			item = _with_ammo_type(item, id)
		var prev := 0
		if got.has(id):
			prev = int(got[id].amount)
		got[id] = {"item": item, "amount": prev + 1}
	return got.values()


func _pick_ammo() -> String:
	var opts := []
	for w in always_weapons:
		if WEAPON_AMMO.has(w):
			opts.append(WEAPON_AMMO[w])
	for w in ["mp5", "shotgun"]:
		if Inventory.has_item(StringName(w)):
			opts.append(WEAPON_AMMO[w])
	return "" if opts.is_empty() else str(opts.pick_random())


## ammo_type pada ItemData dari katalog disesuaikan dengan pengaturan di atas
func _with_ammo_type(item: ItemData, id: String) -> ItemData:
	var want: StringName = item.ammo_type
	match id:
		"ammo_revolver":
			want = ammo_type_revolver
		"ammo_smg":
			want = ammo_type_smg
		"ammo_shotgun":
			want = ammo_type_shotgun
	if want == item.ammo_type:
		return item
	var copy: ItemData = item.duplicate()
	copy.ammo_type = want
	return copy


func _in_world(id: StringName) -> bool:
	for d in get_tree().get_nodes_in_group("loot_drop"):
		if d.has_method("has_unique") and d.has_unique(id):
			return true
	return false


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


# ---------- INTERAKSI ----------
func _process(delta: float) -> void:
	if get_tree().paused:                            # inventory / pause menu terbuka
		_set_shown(null)
		_holding = false
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_near = null
	if _player:
		var best := pickup_range
		for d in get_tree().get_nodes_in_group("loot_drop"):
			if d.is_queued_for_deletion() or d.items.is_empty():
				continue
			var dist := _player.global_position.distance_to((d as Node3D).global_position)
			if dist < best:
				best = dist
				_near = d
	if _near != _shown:
		_sel = 0
		_holding = false
		_hold = 0.0
		_set_shown(_near)
	if _near:
		_sel = clampi(_sel, 0, _near.items.size() - 1)
		_panel.refresh(_near.items, _sel)
	if _holding and _near:
		_hold += delta
		_panel.set_hold(_hold / maxf(take_all_hold, 0.05))
		if _hold >= take_all_hold:
			_holding = false
			_hold = 0.0
			_panel.set_hold(0.0)
			_take_all()
	else:
		_holding = false
		_hold = 0.0
		_panel.set_hold(0.0)


func _set_shown(d: Node3D) -> void:
	_shown = d
	_panel.visible = d != null


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if debug_key != KEY_NONE and event.keycode == debug_key:
			_debug_spawn()
			return
		if debug_inv_key != KEY_NONE and event.keycode == debug_inv_key:
			var s := "--- INVENTORY (%dx%d) ---\n" % [Inventory.cols, Inventory.rows]
			for e in Inventory.entries:
				s += "%s x%d  @(%d,%d)\n" % [e["data"].id, e["amount"], e["x"], e["y"]]
			print(s)
			return
	if _near == null or not is_instance_valid(_near):
		return
	if InputMap.has_action("interact"):
		if event.is_action_pressed("interact"):
			_holding = true
			_hold = 0.0
			get_viewport().set_input_as_handled()          # interact dipakai loot selama dekat tumpukan
			return
		if event.is_action_released("interact") and _holding:
			_holding = false
			if _hold < take_all_hold:
				_take_selected()
			_hold = 0.0
			_panel.set_hold(0.0)
			get_viewport().set_input_as_handled()
			return
	var step := 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_DOWN:
			step = 1
		elif event.keycode == KEY_UP:
			step = -1
	if step != 0 and _near.items.size() > 1:
		_sel = posmod(_sel + step, _near.items.size())
		get_viewport().set_input_as_handled()


## Ambil sebanyak mungkin dari satu baris. Return jumlah yang masuk.
func _take_from(it: Dictionary) -> int:
	var item: ItemData = it.item
	var n := int(it.amount)
	while n > 0:
		if Inventory._can_fit(item, n):               # cek dulu supaya pesan "Case penuh" tidak muncul berulang
			Inventory.add_item(item, n, int(it.get("rounds", -1)))
			return n
		n -= 1
	return 0


func _take_selected() -> void:
	if _near == null or _near.items.is_empty():
		return
	var it: Dictionary = _near.items[_sel]
	var took := _take_from(it)
	if took <= 0:
		_panel.flash("Case penuh")
		return
	it.amount = int(it.amount) - took
	if int(it.amount) <= 0:
		_near.items.remove_at(_sel)
	_after_take()


func _take_all() -> void:
	if _near == null:
		return
	var i := 0
	var any := false
	while i < _near.items.size():
		var it: Dictionary = _near.items[i]
		var took := _take_from(it)
		if took > 0:
			any = true
		it.amount = int(it.amount) - took
		if int(it.amount) <= 0:
			_near.items.remove_at(i)
		else:
			i += 1
	if not any:
		_panel.flash("Case penuh")
	_after_take()


func _after_take() -> void:
	if _near.items.is_empty():
		_near.queue_free()
		_near = null
		_set_shown(null)
	else:
		_sel = clampi(_sel, 0, _near.items.size() - 1)


## Barang yang di-DISCARD dari inventory dijatuhkan ke lantai di depan player (bisa diambil lagi).
func _on_discarded(item: ItemData, amount: int, rounds: int) -> void:
	if not enabled:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var f := -p.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var row := {"item": item, "amount": amount}
	if rounds >= 0:
		row["rounds"] = rounds
	spawn_drop(p.global_position + f * 1.2, [row])


func _debug_spawn() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	var items := []
	for id in Catalog.all_ids():
		var item := Catalog.get_item(id)
		if item:
			items.append({"item": item, "amount": 1})
	var f := -_player.global_transform.basis.z
	spawn_drop(_player.global_position + f * 1.6, items)


func _key(action: String) -> String:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				return OS.get_keycode_string(e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode)
	return "E"
