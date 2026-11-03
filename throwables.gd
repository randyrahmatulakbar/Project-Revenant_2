extends CanvasLayer
## THROWABLES: lempar Grenade (tombol G) dan Molotov (tombol V) yang diambil dari Inventory.
##   Grenade (1x2): memantul di lantai, meledak setelah grenade_fuse detik. Damage area, menurun ke tepi radius.
##   Molotov (1x3): pecah saat kena sesuatu, meninggalkan api di lantai yang membakar musuh yang berdiri di dalamnya.
##   Ledakan dan api juga melukai pemain kalau terlalu dekat (default tidak sampai membunuh).
## Chip kecil di atas strip senjata menunjukkan tombol dan sisa jumlah; chip baru muncul kalau item itu ada di Inventory.
## Dipasang otomatis oleh player-test.gd (anak dari player). Taruh file ini di res://, sama seperti weapon_manager.gd.

@export_group("TOMBOL")
@export var grenade_key: Key = KEY_G
@export var molotov_key: Key = KEY_V
@export var debug_keys := true             # HOME = +3 grenade, END = +3 molotov (buat tes). Matikan sebelum rilis.

@export_group("LEMPAR")
@export var throw_speed := 15.0
@export var throw_up := 2.8
@export var cooldown := 0.55

@export_group("GRENADE")
@export var grenade_fuse := 2.4
@export var grenade_radius := 5.5
@export var grenade_damage := 90.0         # di tengah ledakan
@export_range(0.0, 1.0) var grenade_edge_scale := 0.35   # damage di tepi radius = damage x angka ini
@export var grenade_self_damage := 30.0    # ke pemain (di tengah ledakan), 0 = pemain kebal
@export var grenade_knockback := 7.0
@export var self_can_die := false          # false = ledakan / api tidak pernah membunuh pemain (HP minimal 1)

@export_group("MOLOTOV")
@export var molotov_fuse_max := 4.0        # pecah sendiri kalau melayang selama ini
@export var fire_radius := 3.2
@export var fire_duration := 6.0
@export var fire_tick := 0.4
@export var fire_damage := 5.0             # per tick ke musuh di dalam api
@export var fire_self_damage := 3.0        # cadangan: dipakai hanya kalau BurnStatus tidak terpasang (kalau terpasang, lihat burn_status.gd)

@export_group("UI")
@export var bottom_margin := 102.0         # jarak chip dari tepi bawah (di atas strip senjata)
@export var shift_x := 24.0                # sama dengan shift_x di weapon_manager

const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float energy = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float n = noise(p * 9.0 + vec2(0.0, -TIME * 1.6)) * 0.6 + noise(p * 18.0 + vec2(TIME * 0.7, -TIME * 2.4)) * 0.4;
	float edge = smoothstep(1.0, 0.55, r + (n - 0.5) * 0.55);
	float core = smoothstep(0.7, 0.0, r);
	vec3 c = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.75, 0.2), clamp(core * n * 1.6, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = clamp(edge * (0.35 + 0.65 * n) * energy, 0.0, 1.0);
}
"""

# Bola api dari kubus (MultiMesh): tumbuh dari tengah, lalu kubus menyusut dari dalam ke luar. Warna panas -> dingin.
# Waktu (t) dibuat melompat per frame di script supaya geraknya patah-patah ala animasi pixel.
const BOOM_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform float t = 0.0;
varying vec3 vcol;
vec3 heat(float h) {
	vec3 c0 = vec3(1.0, 0.95, 0.8);
	vec3 c1 = vec3(1.0, 0.78, 0.28);
	vec3 c2 = vec3(0.93, 0.48, 0.18);
	vec3 c3 = vec3(0.7, 0.18, 0.08);
	vec3 c4 = vec3(0.14, 0.1, 0.1);
	if (h < 0.25) return mix(c0, c1, h / 0.25);
	if (h < 0.5) return mix(c1, c2, (h - 0.25) / 0.25);
	if (h < 0.75) return mix(c2, c3, (h - 0.5) / 0.25);
	return mix(c3, c4, (h - 0.75) / 0.25);
}
void vertex() {
	float d = INSTANCE_CUSTOM.x;
	float rnd = INSTANCE_CUSTOM.y;
	float appear = smoothstep(d * 0.4, d * 0.4 + 0.1, t);
	float vanish_at = 0.35 + d * 0.28 + rnd * 0.18;
	float vanish = 1.0 - smoothstep(vanish_at, vanish_at + 0.12, t);
	VERTEX *= appear * vanish;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = 0.78 + 0.22 * wn.y;
	vcol = heat(clamp(t * 1.1 + d * 0.35 + rnd * 0.1 - 0.1, 0.0, 1.0)) * shade;
}
void fragment() {
	ALBEDO = vcol;
}
"""

const CHIP_DEFS := [
	{"id": &"grenade", "name": "GRENADE", "key": "G"},
	{"id": &"molotov", "name": "MOLOTOV", "key": "V"},
]

var _player
var _hud
var _root: Control
var _row: HBoxContainer
var _chips := {}
var _font: Font
var _cd := 0.0
var _throwing := false


# ---------------------------------------------------------------- chip UI

class Chip extends Control:
	const SKEW := 6.0
	const BG := Color(0.07, 0.10, 0.11, 0.92)
	const EDGE := Color(0.87, 0.65, 0.54)
	const CREAM := Color(0.92, 0.86, 0.8)

	var font: Font
	var key_text := ""
	var label := ""
	var count := -1
	var icon: Texture2D
	var flash := 0.0:
		set(v):
			flash = v
			queue_redraw()

	func _init() -> void:
		font = ThemeDB.fallback_font
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_state(c: int, ic: Texture2D) -> void:
		if c == count and ic == icon:
			return
		count = c
		icon = ic
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(SKEW, 0.0), Vector2(w, 0.0), Vector2(w - SKEW, h), Vector2(0.0, h)])
		draw_colored_polygon(pts, BG)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, EDGE, 2.0, true)
		if flash > 0.0:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.45 * flash))
		draw_string(font, Vector2(11.0, h * 0.5 + 7.0), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, EDGE)
		draw_line(Vector2(31.0, 6.0), Vector2(27.0, h - 6.0), Color(CREAM, 0.3), 1.5)
		var x := 38.0
		if icon != null:
			var sc := minf(24.0 / float(maxi(icon.get_height(), 1)), 24.0 / float(maxi(icon.get_width(), 1)))
			var iw := float(icon.get_width()) * sc
			var ih := float(icon.get_height()) * sc
			draw_texture_rect(icon, Rect2(x, (h - ih) * 0.5, iw, ih), false)
		else:
			draw_string(font, Vector2(x, h * 0.5 + 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CREAM)
		draw_string(font, Vector2(w - SKEW - 30.0, h * 0.5 + 7.0), "x%d" % maxi(count, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, CREAM)


# ---------------------------------------------------------------- api lemparan: api di lantai

class FireZone extends Node3D:
	var shader_code := ""
	var radius := 3.2
	var duration := 6.0
	var tick := 0.4
	var dmg := 5.0
	var self_dmg := 3.0
	var self_can_die := false
	var _t := 0.0
	var _tick_t := 0.0
	var _light: OmniLight3D
	var _mat: ShaderMaterial
	var _flames: CPUParticles3D
	var _phase := randf() * 6.0
	var _ign_t := 0.0

	func _ready() -> void:
		var sh := Shader.new()
		sh.code = shader_code
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		var qm := QuadMesh.new()
		qm.size = Vector2(radius * 2.1, radius * 2.1)
		var floor_mi := MeshInstance3D.new()
		floor_mi.mesh = qm
		floor_mi.material_override = _mat
		floor_mi.rotation_degrees.x = -90.0
		floor_mi.position.y = 0.04
		floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(floor_mi)

		_flames = CPUParticles3D.new()
		_flames.amount = 44
		_flames.lifetime = 0.9
		_flames.preprocess = 0.9
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flames.emission_box_extents = Vector3(radius * 0.7, 0.02, radius * 0.7)
		_flames.direction = Vector3.UP
		_flames.spread = 12.0
		_flames.gravity = Vector3.ZERO
		_flames.initial_velocity_min = 0.8
		_flames.initial_velocity_max = 1.9
		_flames.scale_amount_min = 0.8
		_flames.scale_amount_max = 1.5
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.15))
		_flames.scale_amount_curve = curve
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 0.9, 0.4, 0.0), Color(1.0, 0.65, 0.15, 0.9), Color(0.9, 0.2, 0.05, 0.5), Color(0.2, 0.05, 0.02, 0.0)])
		_flames.color_ramp = g
		var fq := QuadMesh.new()
		fq.size = Vector2(0.38, 0.38)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.vertex_color_use_as_albedo = true
		fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		fq.material = fm
		_flames.mesh = fq
		_flames.position.y = 0.1
		add_child(_flames)
		_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.light_energy = 0.0
		_light.omni_range = radius * 2.6
		_light.shadow_enabled = false
		_light.position.y = 0.7
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var env := clampf(_t / 0.25, 0.0, 1.0) * clampf((duration - _t) / 1.0, 0.0, 1.0)
		_mat.set_shader_parameter("energy", env)
		_light.light_energy = (1.8 + 0.6 * sin(_t * 11.0 + _phase) + randf() * 0.4) * env
		if _t >= duration - 1.0:
			_flames.emitting = false
		if _t >= duration:
			queue_free()
			return
		_ign_t -= delta
		if _ign_t <= 0.0:
			_ign_t = 0.1
			_ignite_check()                                 # musuh / pemain di dalam api langsung terbakar
		_tick_t += delta
		if _tick_t >= tick:
			_tick_t -= tick
			_burn()

	# Terbakar (BurnStatus, group "burn_status"): api memasang status, damage-nya jalan terus sampai padam.
	func _ignite_check() -> void:
		var has_burn := not get_tree().get_nodes_in_group("burn_status").is_empty()
		if not has_burn:
			return
		for en in get_tree().get_nodes_in_group("enemy"):
			if en is Node3D and en.has_method("take_damage") and _inside((en as Node3D).global_position):
				get_tree().call_group("burn_status", "ignite_enemy", en, -1.0)
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null and _inside(p.global_position):
			get_tree().call_group("burn_status", "ignite_player", -1.0)

	func _burn() -> void:
		for en in get_tree().get_nodes_in_group("enemy"):
			if en is Node3D and en.has_method("take_damage") and _inside((en as Node3D).global_position):
				en.take_damage(dmg)
		# cadangan: kalau BurnStatus tidak terpasang, pemain di dalam api kena damage langsung seperti dulu
		if not get_tree().get_nodes_in_group("burn_status").is_empty():
			return
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null and self_dmg > 0.0 and _inside(p.global_position):
			var h := p.get_node_or_null("Health")
			if h != null and h.has_method("take_damage"):
				var d := self_dmg
				if not self_can_die and "current_health" in h:
					d = minf(d, float(h.current_health) - 1.0)
				if d > 0.0:
					h.take_damage(d)

	func _inside(pos: Vector3) -> bool:
		var d := pos - global_position
		return Vector2(d.x, d.z).length() <= radius and absf(d.y) <= 2.5


# ---------------------------------------------------------------- siklus hidup

func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_parent()
	_font = load("res://font/Rajdhani-Bold.ttf") if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf") else ThemeDB.fallback_font

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 6)
	_row.anchor_left = 0.5
	_row.anchor_right = 0.5
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_bottom = -bottom_margin
	_row.offset_left = shift_x
	_row.offset_right = shift_x
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_row)

	for d in CHIP_DEFS:
		var c := Chip.new()
		c.font = _font
		c.key_text = d.key
		c.label = d.name
		c.custom_minimum_size = Vector2(106, 34)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.visible = false
		_row.add_child(c)
		_chips[d.id] = c


func _get_hud():
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud")
	return _hud


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	var hud = _get_hud()
	var show: bool = hud != null and hud.visible and not hud.intro_mode and not get_tree().paused
	_root.visible = show
	if not show:
		return
	for id in _chips:
		var n: int = Inventory.get_amount(id)
		var c: Chip = _chips[id]
		var ic: Texture2D = null
		var entry = Inventory.find_entry(id)
		if entry != null and entry["data"] != null:          # entry Inventory: {"data": ItemData, "amount": ...}
			ic = entry["data"].icon
		c.set_state(n, ic)
		c.visible = n > 0


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := int(e.physical_keycode)
	if k == int(grenade_key):
		_try_throw(&"grenade")
	elif k == int(molotov_key):
		_try_throw(&"molotov")
	elif debug_keys and k == KEY_HOME:
		_debug_give(&"grenade")
	elif debug_keys and k == KEY_END:
		_debug_give(&"molotov")


# Tes: tambah 3 item ke Inventory. Butuh item_catalog.gd (dicari di beberapa folder umum).
func _debug_give(id: StringName) -> void:
	for p in ["res://item_catalog.gd", "res://inventory/item_catalog.gd", "res://items/item_catalog.gd"]:
		if ResourceLoader.exists(p):
			var cat = load(p)
			var item = cat.get_item(String(id))
			if item != null:
				Inventory.add_item(item, 3)
			return
	push_warning("Throwables: item_catalog.gd tidak ketemu di folder umum, debug_keys tidak bisa menambah item.")


# ---------------------------------------------------------------- lempar

func _blocked() -> bool:
	if _throwing or _cd > 0.0 or get_tree().paused:
		return true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	var hud = _get_hud()
	if hud == null or hud.intro_mode or hud.is_busy:       # is_busy = reload / animasi tembak / ganti senjata
		return true
	var ch = _player.get("_charge")
	if ch != null and bool(ch.get("_charging")):
		return true
	return false


func _try_throw(kind: StringName) -> void:
	if _blocked():
		return
	if not Inventory.has_item(kind):
		return
	_throwing = true
	_cd = cooldown
	var hud = _get_hud()
	hud.is_busy = true                                      # tembak / reload / parry keblok selama animasi lempar

	var gun: AnimatedSprite2D = hud.gun
	var base: Vector2 = gun.get_meta("base_pos", gun.position)
	gun.set_meta("base_pos", base)
	gun.position = base
	var tw := create_tween()
	tw.tween_property(gun, "position", base + Vector2(0, 220), 0.11).set_ease(Tween.EASE_IN)
	await tw.finished

	if Inventory.remove_item(kind, 1):
		_spawn_projectile(kind)
		get_tree().call_group("sfx", "play", "punch_whoosh", -3.0, 0.06)
		if _chips.has(kind):
			var c: Chip = _chips[kind]
			c.flash = 1.0
			create_tween().tween_property(c, "flash", 0.0, 0.3)

	var tw2 := create_tween()
	tw2.tween_property(gun, "position", base, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw2.finished
	hud.is_busy = false
	_throwing = false


func _spawn_projectile(kind: StringName) -> void:
	var scene := get_tree().current_scene
	var cam: Camera3D = _player.camera
	if scene == null or cam == null:
		return
	var b := cam.global_transform.basis
	var fwd: Vector3 = -b.z
	var from := cam.global_position
	var origin := from + fwd * 0.55 + b.x * 0.18 - b.y * 0.18

	# kalau pemain menempel tembok, jangan lahirkan benda di dalam tembok
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, origin)
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	var r := space.intersect_ray(q)
	if not r.is_empty():
		origin = r.position - fwd * 0.08

	var vel := fwd * throw_speed + Vector3.UP * throw_up
	if "velocity" in _player:
		vel += Vector3(_player.velocity.x, 0.0, _player.velocity.z) * 0.6

	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.4
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3 if kind == &"grenade" else 0.05
	pm.friction = 0.8
	body.physics_material_override = pm
	body.angular_damp = 0.4
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.1
	cs.shape = sh
	body.add_child(cs)
	scene.add_child(body)
	body.global_position = origin
	body.add_collision_exception_with(_player)
	body.linear_velocity = vel
	body.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))

	if kind == &"grenade":
		_dress_grenade(body)
		get_tree().create_timer(grenade_fuse).timeout.connect(_explode_grenade.bind(body))
	else:
		_dress_molotov(body)
		body.body_entered.connect(_on_molotov_hit.bind(body))
		get_tree().create_timer(molotov_fuse_max).timeout.connect(_molotov_break.bind(body))


# ---------------------------------------------------------------- tampilan benda yang dilempar

func _dress_grenade(body: RigidBody3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.3, 0.2)
	mat.metallic = 0.3
	mat.roughness = 0.6
	var cm := CapsuleMesh.new()
	cm.radius = 0.055
	cm.height = 0.14
	cm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	body.add_child(mi)

	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(1, 0.1, 0.05)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1, 0.1, 0.05)
	led_mat.emission_energy_multiplier = 0.2
	var sm := SphereMesh.new()
	sm.radius = 0.02
	sm.height = 0.04
	sm.material = led_mat
	var led := MeshInstance3D.new()
	led.mesh = sm
	led.position = Vector3(0, 0.075, 0)
	body.add_child(led)
	var tw := body.create_tween().set_loops()                # LED berkedip, makin cepat mendekati meledak
	tw.tween_property(led_mat, "emission_energy_multiplier", 4.0, 0.08)
	tw.tween_property(led_mat, "emission_energy_multiplier", 0.2, maxf(grenade_fuse * 0.1, 0.1))


func _dress_molotov(body: RigidBody3D) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.4, 0.18, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.2
	var bm := CylinderMesh.new()
	bm.top_radius = 0.045
	bm.bottom_radius = 0.05
	bm.height = 0.2
	bm.material = glass
	var bottle := MeshInstance3D.new()
	bottle.mesh = bm
	body.add_child(bottle)
	var nm := CylinderMesh.new()
	nm.top_radius = 0.018
	nm.bottom_radius = 0.032
	nm.height = 0.1
	nm.material = glass
	var neck := MeshInstance3D.new()
	neck.mesh = nm
	neck.position = Vector3(0, 0.15, 0)
	body.add_child(neck)

	var fl := CPUParticles3D.new()                           # api kecil di mulut botol
	fl.amount = 10
	fl.lifetime = 0.35
	fl.direction = Vector3.UP
	fl.spread = 15.0
	fl.gravity = Vector3.ZERO
	fl.initial_velocity_min = 0.3
	fl.initial_velocity_max = 0.7
	fl.local_coords = false
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 0.0), Color(1.0, 0.6, 0.15, 0.9), Color(0.8, 0.15, 0.05, 0.0)])
	fl.color_ramp = g
	var fq := QuadMesh.new()
	fq.size = Vector2(0.09, 0.09)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.vertex_color_use_as_albedo = true
	fq.material = fm
	fl.mesh = fq
	fl.position = Vector3(0, 0.22, 0)
	body.add_child(fl)


# ---------------------------------------------------------------- grenade meledak

func _explode_grenade(body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	var pos := body.global_position
	body.queue_free()
	_boom(pos)


func _boom(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var center := pos + Vector3(0, 0.3, 0)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for en in get_tree().get_nodes_in_group("enemy"):
		if en is CollisionObject3D:
			ex.append((en as CollisionObject3D).get_rid())
	ex.append(_player.get_rid())

	# --- musuh (tembok menghalangi ledakan)
	for en in get_tree().get_nodes_in_group("enemy"):
		if not (en is Node3D and en.has_method("take_damage")):
			continue
		var tp: Vector3 = (en as Node3D).global_position + Vector3(0, 1.0, 0)
		var dist := tp.distance_to(center)
		if dist > grenade_radius or _wall_between(space, center, tp, ex):
			continue
		en.take_damage(grenade_damage * lerpf(1.0, grenade_edge_scale, dist / grenade_radius))

	# --- pemain
	var near := 0.0
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var tp: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		var d := tp - center
		var dist := d.length()
		near = clampf(1.0 - dist / (grenade_radius * 1.8), 0.0, 1.0)
		if dist <= grenade_radius and not _wall_between(space, center, tp, ex):
			var k := lerpf(1.0, grenade_edge_scale, dist / grenade_radius)
			var h := p.get_node_or_null("Health")
			if h != null and h.has_method("take_damage") and grenade_self_damage > 0.0:
				var dmg := grenade_self_damage * k
				if not self_can_die and "current_health" in h:
					dmg = minf(dmg, float(h.current_health) - 1.0)
				if dmg > 0.0:
					h.take_damage(dmg)
			if grenade_knockback > 0.0 and "velocity" in p:
				var away := d
				away.y = 0.0
				p.velocity += away.normalized() * grenade_knockback * k + Vector3(0, 2.5 * k, 0)

	_boom_fx(pos, near)


func _wall_between(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, ex: Array[RID]) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = ex
	return not space.intersect_ray(q).is_empty()


func _boom_fx(pos: Vector3, near: float) -> void:
	var scene := get_tree().current_scene
	var c := pos + Vector3(0, 0.6, 0)

	_voxel_fireball(c)

	# cincin kubus yang meluncur di lantai (kecepatan dihitung supaya sampai ke tepi radius)
	_voxels(pos + Vector3(0, 0.15, 0), 40, 0.26, grenade_radius / 0.4, grenade_radius / 0.4, 0.4, 180.0, Vector3.ZERO,
		PackedColorArray([Color(1.0, 0.95, 0.8), Color(1.0, 0.78, 0.28), Color(0.93, 0.48, 0.18)]), 1.0)
	# serpihan gelap-oranye terlempar ke atas
	_voxels(c, 22, 0.22, 5.0, 11.0, 1.0, 70.0, Vector3(0, -16.0, 0),
		PackedColorArray([Color(0.93, 0.48, 0.18), Color(0.7, 0.18, 0.08), Color(0.14, 0.1, 0.1)]))
	# percikan kecil terang
	_voxels(c, 30, 0.07, 8.0, 16.0, 0.7, 180.0, Vector3(0, -12.0, 0),
		PackedColorArray([Color(1.0, 0.95, 0.8), Color(1.0, 0.78, 0.28)]))
	# asap kubus naik pelan setelah api mereda
	_voxels(c + Vector3(0, 0.3, 0), 16, 0.5, 0.8, 2.2, 1.5, 40.0, Vector3(0, 1.4, 0),
		PackedColorArray([Color(0.3, 0.26, 0.25), Color(0.18, 0.16, 0.16), Color(0.1, 0.1, 0.1)]), 0.0, 0.0, true, 0.22)

	_scorch(pos)

	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 10.0
	l.omni_range = grenade_radius * 2.8
	l.shadow_enabled = false
	scene.add_child(l)
	l.global_position = c
	var tl := l.create_tween()
	tl.tween_property(l, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tl.tween_callback(l.queue_free)

	get_tree().call_group("sfx", "play", "gun_shot", 6.0, 0.02)
	get_tree().call_group("sfx", "play", "punch_hit", 0.0, 0.05)
	_shake(0.03 + near * 0.12, 0.35)
	if near > 0.05:
		get_tree().call_group("item_effects", "screen_glow", Color(1.0, 0.55, 0.2), 0.3 + near * 0.9)


# Bola api dari kubus: satu MultiMesh, warna dan animasinya diatur BOOM_SHADER.
func _voxel_fireball(center: Vector3) -> void:
	var R := grenade_radius * 0.42
	var cell := 0.46
	var n := int(ceil(R / cell))
	var cells: Array = []
	for x in range(-n, n + 1):
		for y in range(-n, n + 1):
			for z in range(-n, n + 1):
				var p := Vector3(x, y, z) * cell
				if p.length() > R or p.y < -0.45:           # bola, bagian bawah dipotong supaya tidak menembus lantai
					continue
				cells.append(p)
	var sh := Shader.new()
	sh.code = BOOM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * cell * 0.96
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = bm
	mm.instance_count = cells.size()
	for i in cells.size():
		var cp: Vector3 = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, cp))
		mm.set_instance_custom_data(i, Color(cp.length() / R, randf(), 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mmi)
	mmi.global_position = center
	var tw := mmi.create_tween()
	tw.tween_method(_boom_step.bind(mat), 0.0, 1.0, 0.8)
	tw.tween_callback(mmi.queue_free)


func _boom_step(v: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("t", floorf(v * 9.0) / 9.0)      # 9 langkah: patah-patah ala animasi pixel


# Partikel kubus (tanpa transparansi: warna berubah sepanjang umur, lalu mengecil).
func _voxels(pos: Vector3, amount: int, size: float, vmin: float, vmax: float, life: float, spread: float, grav: Vector3,
		cols: PackedColorArray, flat: float = 0.0, damp: float = 0.0, grow: bool = false, delay: float = 0.0) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = spread
	p.flatness = flat
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.damping_min = damp
	p.damping_max = damp
	p.gravity = grav
	var curve := Curve.new()
	if grow:
		curve.add_point(Vector2(0.0, 0.3))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
	else:
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = curve
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / float(maxi(cols.size() - 1, 1)))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	p.color_ramp = g
	p.emitting = false
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_start_emit.bind(p))
	else:
		p.emitting = true
	get_tree().create_timer(life + delay + 0.3).timeout.connect(_free_node.bind(p))


func _start_emit(p: CPUParticles3D) -> void:
	if is_instance_valid(p):
		p.emitting = true


func _free_node(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


# Bekas gosong di lantai: dua kotak gelap (gaya blok), memudar pelan.
func _scorch(pos: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0)
	q.collision_mask = 1
	var r := space.intersect_ray(q)
	if r.is_empty() or float(r.normal.y) < 0.7:
		return
	var yaw := randf() * TAU
	var sizes := [grenade_radius * 0.5, grenade_radius * 0.32]
	var alphas := [0.4, 0.55]
	for i in 2:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.04, 0.03, 0.03, float(alphas[i]))
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var qm := QuadMesh.new()
		qm.size = Vector2(float(sizes[i]), float(sizes[i]))
		qm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(mi)
		mi.global_position = r.position + Vector3(0, 0.02 + 0.005 * float(i), 0)
		mi.rotation = Vector3(-PI * 0.5, 0.0, yaw + float(i) * 0.4)
		var tw := mi.create_tween()
		tw.tween_interval(4.0)
		tw.tween_property(mat, "albedo_color:a", 0.0, 4.0)
		tw.tween_callback(mi.queue_free)


# ---------------------------------------------------------------- molotov pecah

func _on_molotov_hit(_other: Node, body: RigidBody3D) -> void:
	_molotov_break(body)


func _molotov_break(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.has_meta("broken"):
		return
	body.set_meta("broken", true)
	var pos := body.global_position
	body.queue_free()
	var scene := get_tree().current_scene
	if scene == null:
		return

	# api menempel di lantai di bawah titik pecah
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * 3.0)
	q.collision_mask = 1
	var r := space.intersect_ray(q)
	var ground := pos
	if not r.is_empty():
		ground = r.position

	var fz := FireZone.new()
	fz.shader_code = FIRE_SHADER
	fz.radius = fire_radius
	fz.duration = fire_duration
	fz.tick = fire_tick
	fz.dmg = fire_damage
	fz.self_dmg = fire_self_damage
	fz.self_can_die = self_can_die
	scene.add_child(fz)
	fz.global_position = ground

	_particles(ground + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.2), 28, 0.07, 6.0, 0.7, 70.0, -6.0)
	_particles(ground + Vector3(0, 0.2, 0), Color(0.5, 0.75, 0.45), 10, 0.04, 4.0, 0.5, 90.0)   # pecahan kaca
	_ring3d(ground, Color(1.0, 0.6, 0.25, 0.8), fire_radius * 0.8, 0.35, 0.2)
	get_tree().call_group("sfx", "play", "punch_hit", -4.0, 0.08)
	_shake(0.015, 0.2)


# ---------------------------------------------------------------- efek umum

func _fx_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


func _ring3d(pos: Vector3, col: Color, radius: float, time: float, start_scale: float) -> void:
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


func _particles(pos: Vector3, col: Color, amount: int, size: float, speed: float, life: float, spread: float = 180.0, grav: float = -9.8) -> void:
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


# Getar kamera singkat (h_offset / v_offset), mengecil sampai nol.
func _shake(amount: float, time: float) -> void:
	var cam = _player.camera
	if not (cam is Camera3D):
		return
	var tw := create_tween()
	tw.tween_method(_shake_step.bind(cam, amount), 1.0, 0.0, time)
	tw.tween_callback(_shake_step.bind(0.0, cam, 0.0))


func _shake_step(v: float, cam: Camera3D, amount: float) -> void:
	if not is_instance_valid(cam):
		return
	cam.h_offset = randf_range(-1.0, 1.0) * amount * v
	cam.v_offset = randf_range(-1.0, 1.0) * amount * v
