extends Node
## EFEK ITEM yang dipakai dari Inventory (tombol USE):
##   Medkit dan Bandage memulihkan HP sebesar heal_amount di ItemData. Ditolak kalau HP sudah penuh.
##   Adrenaline Shot: lari lebih cepat beberapa detik (+ garis kecepatan di tepi layar, indikator di StatusHUD).
##   Leaper's Claw (equipment): wallhop lebih tinggi + satu wallhop tambahan, dengan goresan cakar di layar.
##   Ember Core (equipment): musuh yang mati bisa meledak kecil (peluang + cooldown), ledakan juga bisa melukai player.
##   Extended Mag (equipment): efek layar saat didapat; hitungan +50% peluru ada di ammo_bridge.gd.
##   Poison Dissolver menghapus poison (node anak "PoisonDot" di player). Ditolak kalau tidak sedang keracunan.
## Kalau player-mu sudah memasang Inventory.can_use_item sendiri, berarti player yang menangani efek,
## dan script ini tidak memasang apa-apa (supaya tidak heal dua kali).
## Dibuat otomatis oleh LootManager. Boleh juga ditaruh manual sebagai Node biasa.

@export var enabled := true
@export_group("EQUIPMENT")
@export var equipment_enabled := true
@export var claw_height_mult := 1.3          # pengali tinggi wallhop (wall_hop_up) saat punya Leaper's Claw
@export var claw_extra_hops := 1             # wallhop tambahan per sekali di udara
@export var claw_fx := true                  # goresan cakar di layar saat wallhop
@export var equip_fx := true                 # kilau saat equipment didapat
@export var extended_bonus := 0.5            # Extended Mag: tambah magazine asli sebanyak 50% dari yang dimiliki (sekali per game)
@export var extended_types := {"ammo_revolver": &"pistol", "ammo_smg": &"smg"}   # id item magazine -> ammo_type
@export_group("EMBER CORE")
@export var ember_enabled := true
@export_range(0.0, 1.0) var ember_chance := 0.3     # peluang meledak tiap musuh mati
@export var ember_cooldown := 5.0                   # detik antar ledakan
@export var ember_fuse := 0.45                      # jeda peringatan sebelum meledak (lingkaran bahaya + bara)
@export var ember_radius := 3.5
@export var ember_damage_enemy := 4.0
@export var ember_damage_player := 14.0             # di tengah ledakan; menurun sampai 40% di tepi
@export var ember_can_kill_player := false          # false = ledakan tidak pernah membunuh (HP minimal 1)
@export var ember_knockback := 6.0
@export var ember_fx := true
@export_group("ADRENALINE")
@export var adrenaline_enabled := true
@export var adrenaline_time := 12.0          # detik
@export var adrenaline_speed := 1.35         # pengali kecepatan jalan (1.35 = +35%)
@export var adrenaline_fx := true            # garis kecepatan di tepi layar
@export_group("EFEK LAYAR (kill switch)")
@export var fx_enabled := true
@export var heal_fx := true                  # medkit / bandage: tepi layar menyala lembut + tanda "+" naik
@export var cure_fx := true                  # poison dissolver: gelombang hijau + percikan

const FX_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.5, 0.95, 0.7, 1.0);
uniform float glow = 0.0;
uniform float ring = -1.0;
void fragment() {
	vec2 c = UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(c);
	float a = smoothstep(0.3, 0.85, r) * glow * 0.55 + glow * 0.04;
	if (ring >= 0.0) {
		float d = abs(r - ring * 0.95);
		a += smoothstep(0.07, 0.0, d) * (1.0 - ring) * 0.55;
	}
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
"""
const Catalog = preload("item_catalog.gd")

const LINES_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.95, 0.62, 0.66, 1.0);
uniform float amount = 0.0;
float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 c = UV - 0.5;
	c.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(c);
	float id = floor(atan(c.y, c.x) * 70.0);
	float rnd = h(id);
	float streak = step(0.78, rnd);
	float flick = 0.5 + 0.5 * sin(TIME * (14.0 + rnd * 18.0) + rnd * 40.0);
	float edge = smoothstep(0.36, 0.86, r);
	float a = (streak * flick * 0.55 + 0.1) * edge * amount;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
"""
const CLAW_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.92, 0.86, 0.8, 1.0);
uniform float t = 1.0;
uniform float flip = 1.0;
uniform float power = 1.0;
void fragment() {
	vec2 p = UV - vec2(0.5 + 0.2 * flip, 0.5);
	p.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float ang = -0.95 * flip;
	vec2 q = vec2(p.x * cos(ang) - p.y * sin(ang), p.x * sin(ang) + p.y * cos(ang));
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		float o = float(i - 1) * 0.075;
		float len = 0.42 - abs(float(i - 1)) * 0.05;
		float along = (q.x + len) / (2.0 * len);                       // 0..1 sepanjang goresan
		float w = 0.014 * power * (1.0 - abs(along * 2.0 - 1.0)) ;     // runcing di kedua ujung
		float reveal = step(along, t * 1.6 - float(i) * 0.12);        // tersapu dari ujung
		float d = abs(q.y - o) - w;
		a = max(a, smoothstep(0.004, 0.0, d) * reveal * step(0.0, along) * step(along, 1.0));
	}
	a *= (1.0 - smoothstep(0.45, 1.0, t)) * 0.9;
	COLOR = vec4(tint.rgb, a);
}
"""
const COL_PEACH := Color(0.87, 0.65, 0.54)
const COL_ADR := Color(0.95, 0.56, 0.62)
const COL_HEAL := Color(0.55, 0.95, 0.72)
const COL_CURE := Color(0.62, 0.86, 0.3)
const COL_CREAM := Color(0.92, 0.86, 0.8)

var _active := false
var _fx_layer: CanvasLayer
var _fx_root: Control
var _fx_rect: ColorRect
var _fx_mat: ShaderMaterial
var _lines_mat: ShaderMaterial
var _lines_rect: ColorRect
var _claw_mat: ShaderMaterial
var _claw_rect: ColorRect
var _claw_flip := 1.0
var _claw_on := false
var _claw_player: Node
var _claw_base_up := 0.0
var _claw_base_limit := 0
var _last_wh := 0
var _owned: Dictionary = {}
var _equip_ready := false
var _ext_granted := false
var _equip_poll := 0.0
var _ember_cd := 0.0
var _adr_left := 0.0
var _adr_amount := 0.0


func _ready() -> void:
	add_to_group("item_effects")
	if not enabled:
		set_physics_process(false)
		return
	if fx_enabled:
		_build_fx()
		Inventory.item_used.connect(_play_fx)
	if adrenaline_enabled:
		Inventory.item_used.connect(_adr_used)
	if ember_enabled:
		for en in get_tree().get_nodes_in_group("enemy"):
			_hook_enemy(en)
		get_tree().node_added.connect(_hook_enemy)
	await get_tree().create_timer(0.4).timeout          # beri waktu player memasang handler-nya sendiri
	if not is_inside_tree():
		return
	if Inventory.can_use_item.is_valid():
		print("ItemEffects: player sudah menangani item (can_use_item terpasang), efek bawaan tidak dipakai.")
		return
	Inventory.can_use_item = _can_use
	Inventory.item_used.connect(_on_used)
	_active = true


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_hook_enemy):
		get_tree().node_added.disconnect(_hook_enemy)
	if Inventory.item_used.is_connected(_adr_used):
		Inventory.item_used.disconnect(_adr_used)
	if Inventory.item_used.is_connected(_play_fx):
		Inventory.item_used.disconnect(_play_fx)
	if _active:
		if Inventory.item_used.is_connected(_on_used):
			Inventory.item_used.disconnect(_on_used)
		if Inventory.can_use_item == _can_use:
			Inventory.can_use_item = Callable()


func _health() -> Node:
	var p := get_tree().get_first_node_in_group("player")
	return p.get_node_or_null("Health") if p else null


## Return "" kalau boleh dipakai, atau alasan penolakan.
func _can_use(item: ItemData) -> String:
	if item.id == &"adrenaline" and adrenaline_enabled and _adr_left > 0.0:
		return "Adrenaline masih aktif"
	if item.id == &"poison_dissolver" and not _poisoned():
		return "Tidak sedang keracunan"
	if item.heal_amount > 0:
		var h := _health()
		if h == null:
			return "Tidak ada player"
		if float(h.current_health) >= float(h.max_health):
			return "HP sudah penuh"
	return ""


func _on_used(item: ItemData) -> void:
	if item.id == &"poison_dissolver":
		_cure_poison()
		return
	var h := _health()
	if h == null:
		return
	if item.heal_amount > 0:
		_heal(h, float(item.heal_amount))
		Inventory.message.emit("+%d HP" % item.heal_amount)
	if item.armor_amount > 0 and "armor" in h and "max_armor" in h:
		h.armor = minf(float(h.armor) + float(item.armor_amount), float(h.max_armor))


func _heal(h: Node, amount: float) -> void:
	for m in ["heal", "add_health", "restore", "increase_health", "recover"]:
		if h.has_method(m):
			h.call(m, amount)
			return
	var cur := minf(float(h.current_health) + amount, float(h.max_health))
	h.current_health = cur
	if h.has_signal("health_changed"):
		h.emit_signal("health_changed", cur, float(h.max_health))


# ---------------------------------------------------------------- poison

func _poison_node() -> Node:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return null
	var cands: Array = p.get_children()
	var h := p.get_node_or_null("Health")
	if h:
		cands.append_array(h.get_children())
	for n in cands:
		if "poison" in str(n.name).to_lower() and not n.is_queued_for_deletion():
			return n
	return null


func _poisoned() -> bool:
	var d := _poison_node()
	if d == null:
		return false
	var t = d.get("time_left")
	return t == null or float(t) > 0.0


func _cure_poison() -> void:
	var d := _poison_node()
	while d != null:
		if d.get("time_left") != null:
			d.set("time_left", 0.0)
		if d.get("dps") != null:
			d.set("dps", 0.0)
		d.queue_free()
		d = _poison_node()                             # node yang sudah antri hapus tidak dihitung lagi
	for n in get_tree().get_nodes_in_group("status"):
		if n.has_method("cure_status"):
			n.call("cure_status", "poison")
		elif n.has_method("clear_status"):
			n.call("clear_status", "poison")
	Inventory.message.emit("Poison hilang")


# ---------------------------------------------------------------- efek layar

func _build_fx() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 47                               # di bawah StatusHUD (48) dan inventory (50)
	add_child(_fx_layer)
	_fx_root = Control.new()
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_fx_root)
	_fx_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FX_SHADER
	_fx_mat.shader = sh
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.material = _fx_mat
	_fx_rect.visible = false
	_fx_root.add_child(_fx_rect)
	_lines_mat = ShaderMaterial.new()
	var sh2 := Shader.new()
	sh2.code = LINES_SHADER
	_lines_mat.shader = sh2
	_lines_rect = ColorRect.new()
	_lines_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_rect.material = _lines_mat
	_lines_rect.visible = false
	_fx_root.add_child(_lines_rect)
	_fx_root.move_child(_lines_rect, 0)                # garis kecepatan di belakang efek lain
	_claw_mat = ShaderMaterial.new()
	var sh3 := Shader.new()
	sh3.code = CLAW_SHADER
	_claw_mat.shader = sh3
	_claw_rect = ColorRect.new()
	_claw_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_claw_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claw_rect.material = _claw_mat
	_claw_rect.visible = false
	_fx_root.add_child(_claw_rect)


func _play_fx(item: ItemData) -> void:
	if _fx_root == null:
		return
	if item.id == &"poison_dissolver":
		if cure_fx:
			_fx_cure()
	elif item.heal_amount > 0:
		if heal_fx:
			_fx_heal(clampf(float(item.heal_amount) / 35.0, 0.5, 1.4))


func _set_glow(v: float) -> void:
	_fx_mat.set_shader_parameter("glow", v)


func _set_ring(v: float) -> void:
	_fx_mat.set_shader_parameter("ring", v)


func _hide_rect() -> void:
	_fx_rect.visible = false


func _fx_heal(power: float) -> void:
	_fx_mat.set_shader_parameter("tint", COL_HEAL)
	_fx_mat.set_shader_parameter("ring", -1.0)
	_fx_rect.visible = true
	var tw := create_tween()                           # menempel ke node ini: baru jalan setelah game lanjut
	tw.tween_method(_set_glow, 0.0, power, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_glow, power, 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_hide_rect)
	var vp := get_viewport().get_visible_rect().size
	var n := int(round(6.0 + 6.0 * power))
	for i in n:
		var pos := Vector2(randf_range(0.36, 0.64) * vp.x, randf_range(0.62, 0.84) * vp.y)
		_spawn_plus(pos, COL_HEAL if i % 3 != 0 else COL_CREAM, randf_range(0.0, 0.4), randf_range(0.9, 1.3))


func _fx_cure() -> void:
	_fx_mat.set_shader_parameter("tint", COL_CURE)
	_fx_rect.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_glow, 0.0, 0.7, 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_glow, 0.7, 0.0, 0.7).set_delay(0.15).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_ring, 0.0, 1.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_hide_rect)
	var vp := get_viewport().get_visible_rect().size
	var center := vp * Vector2(0.5, 0.55)
	for i in 16:
		var ang := randf() * TAU
		var dist := randf_range(0.12, 0.3) * vp.y
		_spawn_drop(center + Vector2(cos(ang), sin(ang)) * 30.0, Vector2(cos(ang), sin(ang)) * dist,
				COL_CURE if i % 3 != 0 else COL_CREAM, randf_range(0.0, 0.15), randf_range(0.6, 0.95))


func _spawn_plus(pos: Vector2, col: Color, delay: float, life: float) -> void:
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	p.modulate.a = 0.0
	var u := 4.0
	var a := ColorRect.new()
	a.color = col
	a.position = Vector2(-u * 1.5, -u * 0.5)
	a.size = Vector2(u * 3.0, u)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := ColorRect.new()
	b.color = col
	b.position = Vector2(-u * 0.5, -u * 1.5)
	b.size = Vector2(u, u * 3.0)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(a)
	p.add_child(b)
	_fx_root.add_child(p)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "position:y", pos.y - randf_range(90.0, 160.0), life).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.1).set_delay(delay)
	tw.tween_property(p, "modulate:a", 0.0, life * 0.5).from(1.0).set_delay(delay + life * 0.5)
	tw.chain().tween_callback(p.queue_free)


func _spawn_drop(pos: Vector2, move: Vector2, col: Color, delay: float, life: float) -> void:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = col
	r.size = Vector2(5, 5)
	r.position = pos
	r.modulate.a = 0.0
	_fx_root.add_child(r)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(r, "position", pos + move, life).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 1.0, 0.06).set_delay(delay)
	tw.tween_property(r, "modulate:a", 0.0, life * 0.6).from(1.0).set_delay(delay + life * 0.4)
	tw.chain().tween_callback(r.queue_free)


# ---------------------------------------------------------------- adrenaline

func _adr_used(item: ItemData) -> void:
	if item.id != &"adrenaline":
		return
	_adr_left = adrenaline_time
	get_tree().call_group("status", "apply_status", "adrenaline", adrenaline_time)
	Inventory.message.emit("Adrenaline: +%d%% kecepatan" % int(round((adrenaline_speed - 1.0) * 100.0)))
	if _fx_root != null and adrenaline_fx:
		_fx_adr_burst()


func _fx_adr_burst() -> void:
	_fx_mat.set_shader_parameter("tint", COL_ADR)
	_fx_mat.set_shader_parameter("ring", -1.0)
	_fx_rect.visible = true
	var tw := create_tween()
	tw.tween_method(_set_glow, 0.0, 1.0, 0.08).set_ease(Tween.EASE_OUT)     # sengatan cepat
	tw.tween_method(_set_glow, 1.0, 0.0, 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_hide_rect)
	var vp := get_viewport().get_visible_rect().size
	for i in 14:                                       # percikan pixel memancar dari tengah
		var ang := randf() * TAU
		var dist := randf_range(0.18, 0.4) * vp.y
		_spawn_drop(vp * 0.5 + Vector2(cos(ang), sin(ang)) * 40.0, Vector2(cos(ang), sin(ang)) * dist,
				COL_ADR if i % 3 != 0 else COL_CREAM, randf_range(0.0, 0.08), randf_range(0.35, 0.6))


func _physics_process(delta: float) -> void:
	_ember_cd = maxf(_ember_cd - delta, 0.0)
	if equipment_enabled:
		_equipment_tick(delta)
	var target_amt := 0.0
	if _adr_left > 0.0:
		_adr_left = maxf(_adr_left - delta, 0.0)
		var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
		if p != null:
			var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
			if hv.length_squared() > 0.01:
				p.move_and_collide(hv * (adrenaline_speed - 1.0) * delta)     # tambahan gerak = kecepatan x pengali
			target_amt = clampf(hv.length() / 8.0, 0.0, 1.0) * 0.8 + 0.2
		target_amt *= clampf(_adr_left / 2.0, 0.0, 1.0)                        # memudar di 2 detik terakhir
	_adr_amount = lerpf(_adr_amount, target_amt, 1.0 - exp(-delta * 6.0))
	if _lines_rect != null:
		var on := adrenaline_fx and _adr_amount > 0.01
		_lines_rect.visible = on
		if on:
			_lines_mat.set_shader_parameter("amount", _adr_amount)


# ---------------------------------------------------------------- equipment

func _equipment_tick(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	# --- Leaper's Claw: pasang / lepas bonus wallhop pada variabel export player
	if p != null and "wall_hop_up" in p and "wall_hop_limit" in p:
		var has_claw := Inventory.has_item(&"leapers_claw")
		if p != _claw_player:
			_claw_player = p
			_claw_on = false                               # player baru (scene dimuat ulang)
		if has_claw and not _claw_on:
			_claw_base_up = float(p.wall_hop_up)
			_claw_base_limit = int(p.wall_hop_limit)
			p.wall_hop_up = _claw_base_up * claw_height_mult
			if _claw_base_limit > 0:                       # 0 = sudah tanpa batas
				p.wall_hop_limit = _claw_base_limit + claw_extra_hops
			_claw_on = true
		elif not has_claw and _claw_on:
			p.wall_hop_up = _claw_base_up
			p.wall_hop_limit = _claw_base_limit
			_claw_on = false
		# goresan cakar tiap kali wallhop terjadi
		var wh = p.get("_wall_hops")
		if wh != null:
			if _claw_on and int(wh) > _last_wh:
				_fx_claw(int(wh) > _claw_base_limit)       # wallhop tambahan (dari cakar) -> goresan lebih tebal
			_last_wh = int(wh)
	# --- kilau saat equipment didapat
	_equip_poll -= delta
	if _equip_poll <= 0.0:
		_equip_poll = 0.2
		for id in [&"leapers_claw", &"extended_mag", &"ember_core"]:
			var now := Inventory.has_item(id)
			if _equip_ready and now and not _owned.get(id, false):
				_fx_equip(id)
			_owned[id] = now
		_equip_ready = true


func _fx_equip(id: StringName) -> void:
	if id == &"extended_mag":
		_grant_extended()
	elif id == &"ember_core":
		Inventory.message.emit("Ember Core: musuh mati bisa meledak")
	elif id == &"leapers_claw":
		Inventory.message.emit("Leaper's Claw: wallhop +1, lebih tinggi")
	if _fx_root == null or not equip_fx:
		return
	_fx_mat.set_shader_parameter("tint", COL_PEACH)
	_fx_rect.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_glow, 0.0, 0.6, 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_glow, 0.6, 0.0, 0.8).set_delay(0.15).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_ring, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_hide_rect)
	var vp := get_viewport().get_visible_rect().size
	for i in 10:
		var pos := Vector2(randf_range(0.4, 0.6) * vp.x, randf_range(0.66, 0.82) * vp.y)
		_spawn_plus(pos, COL_PEACH if i % 2 == 0 else COL_CREAM, randf_range(0.0, 0.3), randf_range(0.8, 1.2))


func _set_claw_t(v: float) -> void:
	_claw_mat.set_shader_parameter("t", v)


func _fx_claw(strong: bool) -> void:
	if _claw_rect == null or not claw_fx:
		return
	_claw_flip = -_claw_flip                           # selang-seling kiri / kanan
	_claw_mat.set_shader_parameter("flip", _claw_flip)
	_claw_mat.set_shader_parameter("power", 1.5 if strong else 1.0)
	_claw_mat.set_shader_parameter("tint", COL_PEACH.lightened(0.5) if strong else COL_CREAM)
	_claw_mat.set_shader_parameter("t", 0.0)
	_claw_rect.visible = true
	var tw := create_tween()
	tw.tween_method(_set_claw_t, 0.0, 1.0, 0.42 if strong else 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _claw_rect.visible = false)


# ---------------------------------------------------------------- ember core

func _hook_enemy(n: Node) -> void:
	if n is CharacterBody3D and n.has_signal("died") and n.has_method("_think"):
		if not n.died.is_connected(_ember_on_died):
			n.died.connect(_ember_on_died)


func _ember_on_died(enemy: Node) -> void:
	if not ember_enabled or _ember_cd > 0.0 or not (enemy is Node3D):
		return
	if not Inventory.has_item(&"ember_core"):
		return
	if randf() > ember_chance:
		return
	var pos: Vector3 = (enemy as Node3D).global_position
	_ember_cd = ember_cooldown
	if ember_fx:
		_ember_fuse(pos)
	get_tree().create_timer(ember_fuse).timeout.connect(_ember_boom.bind(pos))


func _fx_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


func _fx_ring3d(pos: Vector3, col: Color, radius: float, time: float, start_scale: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.94
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	var mat := _fx_material(col)
	tm.material = mat
	mi.mesh = tm
	mi.scale = Vector3.ONE * radius * start_scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func _fx_particles(pos: Vector3, col: Color, amount: int, size: float, speed: float, life: float, spread: float = 180.0, grav: float = -9.8) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## Peringatan sebelum meledak: lingkaran bahaya di lantai yang berdenyut + cahaya bara + percikan naik.
func _ember_fuse(pos: Vector3) -> void:
	if get_tree().current_scene == null:
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	var mat := _fx_material(Color(1.0, 0.45, 0.12, 0.55))
	tm.material = mat
	mi.mesh = tm
	mi.scale = Vector3.ONE * ember_radius
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	var tw := mi.create_tween()
	tw.set_loops(3)
	tw.tween_property(mat, "albedo_color:a", 0.15, ember_fuse / 6.0)
	tw.tween_property(mat, "albedo_color:a", 0.8, ember_fuse / 6.0)
	get_tree().create_timer(ember_fuse).timeout.connect(mi.queue_free)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 0.5
	l.omni_range = 5.0
	l.shadow_enabled = false
	get_tree().current_scene.add_child(l)
	l.global_position = pos + Vector3(0, 0.8, 0)
	var tl := l.create_tween()
	tl.tween_property(l, "light_energy", 3.5, ember_fuse).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(ember_fuse).timeout.connect(l.queue_free)
	_fx_particles(pos + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2), 10, 0.05, 2.5, ember_fuse + 0.2, 40.0, 1.5)


func _ember_boom(pos: Vector3) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	# --- musuh di sekitar
	for en in get_tree().get_nodes_in_group("enemy"):
		if en is Node3D and en.has_method("take_damage"):
			if ((en as Node3D).global_position + Vector3(0, 1.0, 0)).distance_to(pos + Vector3(0, 0.8, 0)) <= ember_radius:
				en.take_damage(ember_damage_enemy)
	# --- player
	var p := get_tree().get_first_node_in_group("player") as Node3D
	var near := 0.0
	if p != null:
		var d := (p.global_position + Vector3(0, 1.0, 0)) - (pos + Vector3(0, 0.8, 0))
		var dist := d.length()
		near = clampf(1.0 - dist / (ember_radius * 1.8), 0.0, 1.0)
		if dist <= ember_radius:
			var dmg := ember_damage_player * lerpf(1.0, 0.4, dist / ember_radius)
			var h := p.get_node_or_null("Health")
			if h != null and h.has_method("take_damage"):
				if not ember_can_kill_player and "current_health" in h:
					dmg = minf(dmg, float(h.current_health) - 1.0)
				if dmg > 0.0:
					h.take_damage(dmg)
			if ember_knockback > 0.0 and "velocity" in p:
				var away := d
				away.y = 0.0
				p.velocity += away.normalized() * ember_knockback + Vector3(0, 2.0, 0)
	if not ember_fx:
		return
	# --- efek 3D
	var c := pos + Vector3(0, 0.9, 0)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var bmat := _fx_material(Color(1.0, 0.62, 0.2, 0.95))
	sm.material = bmat
	ball.mesh = sm
	ball.scale = Vector3.ONE * 0.4
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ball)
	ball.global_position = c
	var tb := ball.create_tween().set_parallel(true)
	tb.tween_property(ball, "scale", Vector3.ONE * ember_radius * 0.9, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tb.tween_property(bmat, "albedo_color", Color(1.0, 0.25, 0.05, 0.0), 0.3).set_delay(0.04)
	tb.chain().tween_callback(ball.queue_free)
	_fx_ring3d(pos, Color(1.0, 0.8, 0.45, 0.9), ember_radius, 0.4, 0.15)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 8.0
	l.omni_range = ember_radius * 2.5
	l.shadow_enabled = false
	get_tree().current_scene.add_child(l)
	l.global_position = c
	var tl := l.create_tween()
	tl.tween_property(l, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	tl.tween_callback(l.queue_free)
	_fx_particles(c, Color(1.0, 0.7, 0.25), 32, 0.09, 8.0, 0.8)
	_fx_particles(c, Color(1.0, 0.95, 0.7), 12, 0.05, 11.0, 0.5)
	_fx_particles(c, Color(0.18, 0.15, 0.14), 12, 0.2, 2.5, 1.1, 90.0, 1.0)
	# --- kilatan layar, makin dekat makin kuat
	if _fx_root != null and near > 0.05:
		_fx_mat.set_shader_parameter("tint", Color(1.0, 0.5, 0.15))
		_fx_mat.set_shader_parameter("ring", -1.0)
		_fx_rect.visible = true
		var ts := create_tween()
		ts.tween_method(_set_glow, 0.0, 0.3 + near * 0.9, 0.05)
		ts.tween_method(_set_glow, 0.3 + near * 0.9, 0.0, 0.5).set_ease(Tween.EASE_OUT)
		ts.tween_callback(_hide_rect)


## Dipanggil dari luar (mis. ledakan granat): kilatan tepi layar berwarna. amount 0..1.
func screen_glow(col: Color, amount: float) -> void:
	if _fx_root == null or amount <= 0.02:
		return
	_fx_mat.set_shader_parameter("tint", col)
	_fx_mat.set_shader_parameter("ring", -1.0)
	_fx_rect.visible = true
	var tw := create_tween()
	tw.tween_method(_set_glow, 0.0, 0.3 + amount * 0.9, 0.05)
	tw.tween_method(_set_glow, 0.3 + amount * 0.9, 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_hide_rect)


## Extended Mag: tambahkan magazine ASLI ke case = 50% dari jumlah magazine yang sedang dimiliki (dibulatkan ke atas).
## Hanya untuk tipe yang sedang dimiliki. Kalau case penuh, magazine tambahan jatuh ke lantai.
func _grant_extended() -> void:
	if _ext_granted:
		return
	_ext_granted = true
	var total := 0
	for mag_id in extended_types:
		var atype: StringName = extended_types[mag_id]
		var n := 0
		for en in Inventory.entries:
			var d: ItemData = en["data"]
			if d.type == ItemData.Type.AMMO and d.ammo_type == atype:
				n += int(en["amount"])
		var bonus := int(ceil(float(n) * extended_bonus))
		var it: ItemData = Catalog.get_item(str(mag_id))
		if bonus <= 0 or it == null:
			continue
		for i in bonus:
			if not Inventory.add_item(it, 1):
				Inventory.item_discarded.emit(it, 1, -1)
		total += bonus
	if total > 0:
		Inventory.message.emit("Extended Mag: +%d magazine" % total)
