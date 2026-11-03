extends CanvasLayer
## BURN STATUS: efek terbakar untuk pemain dan musuh.
##   Pemain yang berdiri di api Molotov ikut terbakar: damage tiap 0,5 detik yang terus berjalan beberapa detik
##   setelah keluar dari api (diperpanjang lagi selama masih di dalam api).
##   Indikator: api yang menjilat dari bawah dan tepi layar, kilatan oranye saat pertama kali menyala dan tiap tick kena,
##   getar kamera kecil, notifikasi "Terbakar!", dan baris "Burning" di StatusHUD (status_hud.gd, sama gayanya dengan Adrenaline).
##   Kalau StatusHUD tidak ada di scene, dipakai chip "BURNING" buatan script ini sebagai cadangan.
##   Musuh yang kena api juga terbakar: ada api kecil di badannya dan damage terus berjalan sampai padam.
## Dipasang otomatis oleh player-test.gd (anak dari player). Taruh file ini di res://, sama seperti weapon_manager.gd.
## Dipicu lewat group "burn_status": ignite_player(detik), ignite_enemy(node, detik), extinguish().

@export_group("PEMAIN")
@export var player_burn_time := 4.0        # lama terbakar sejak terakhir kena api (detik)
@export var player_burn_dps := 4.0         # damage per detik (dijatuhkan tiap tick)
@export var tick := 0.5
@export var player_can_die := false        # false = terbakar tidak pernah membunuh pemain (HP minimal 1)

@export_group("MUSUH")
@export var enemy_burn_time := 4.0
@export var enemy_burn_dps := 8.0

@export_group("UI")
@export var chip_bottom := 100.0           # jarak chip dari tepi bawah (di atas panel HP)
@export var chip_left := 36.0

const SCREEN_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform float pulse = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}
void fragment() {
	vec2 uv = UV;
	float n = fbm(vec2(uv.x * 5.0, uv.y * 2.5 - TIME * 1.6));
	float edge = smoothstep(0.30, 0.95, length(uv - 0.5) * 1.55);
	float bottom = smoothstep(0.35, 1.0, uv.y);
	float flame = smoothstep(0.35, 0.85, bottom * 1.25 + n * 0.75 - 0.35 + intensity * 0.25);
	float a = clamp(flame * 0.9 + edge * 0.45, 0.0, 1.0) * intensity;
	a += pulse * edge * 0.35;
	vec3 col = mix(vec3(0.85, 0.08, 0.02), vec3(1.0, 0.72, 0.18), clamp(flame * n * 1.7, 0.0, 1.0));
	COLOR = vec4(col, clamp(a, 0.0, 0.92));
}
"""

var _player
var _hud
var _root: Control
var _overlay: ColorRect
var _mat: ShaderMaterial
var _chip: BurnChip
var _font: Font
var _left := 0.0
var _max_left := 1.0
var _tick_t := 0.0
var _intensity := 0.0
var _pulse := 0.0
var _appear := 0.0
var _time := 0.0
var _enemies := {}                 # Node -> {"left": float, "t": float, "fx": CPUParticles3D}
var _via_hud := false              # true = indikator lewat StatusHUD (group "status"), chip cadangan disembunyikan


# ---------------------------------------------------------------- chip indikator

class BurnChip extends Control:
	const SKEW := 7.0
	const BG := Color(0.13, 0.06, 0.05, 0.93)

	var font: Font
	var ratio := 0.0
	var flash := 0.0
	var t := 0.0

	func _init() -> void:
		font = ThemeDB.fallback_font

	func _flame(c: Vector2, s: float, fl: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(c.x + (fl - 0.5) * 2.5, c.y - s),
			Vector2(c.x + s * 0.55, c.y - s * 0.05),
			Vector2(c.x + s * 0.42, c.y + s * 0.65),
			Vector2(c.x, c.y + s),
			Vector2(c.x - s * 0.42, c.y + s * 0.65),
			Vector2(c.x - s * 0.55, c.y - s * 0.05),
			Vector2(c.x - s * 0.12, c.y - s * 0.4)])

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var fl := 0.5 + 0.5 * sin(t * 14.0)
		var edge := Color(1.0, 0.42 + 0.25 * fl, 0.12)
		var pts := PackedVector2Array([Vector2(SKEW, 0.0), Vector2(w, 0.0), Vector2(w - SKEW, h), Vector2(0.0, h)])
		draw_colored_polygon(pts, BG)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, edge, 2.0, true)
		if flash > 0.0:
			draw_colored_polygon(pts, Color(1.0, 0.5, 0.1, 0.5 * flash))
		var c := Vector2(21.0, h * 0.5)
		var s := 11.0 + 1.5 * fl
		draw_colored_polygon(_flame(c, s, fl), Color(1.0, 0.4, 0.08))
		draw_colored_polygon(_flame(c + Vector2(0.0, 3.0), s * 0.55, 1.0 - fl), Color(1.0, 0.85, 0.35))
		draw_string(font, Vector2(40.0, 17.0), "BURNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.88, 0.72))
		var bx := 40.0
		var bw := w - SKEW - bx - 10.0
		draw_rect(Rect2(bx, h - 11.0, bw, 4.0), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bx, h - 11.0, bw * clampf(ratio, 0.0, 1.0), 4.0), edge)


# ---------------------------------------------------------------- siklus hidup

func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("burn_status")
	_player = get_parent()
	_font = load("res://font/Rajdhani-Bold.ttf") if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf") else ThemeDB.fallback_font

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var sh := Shader.new()
	sh.code = SCREEN_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _mat
	_overlay.visible = false
	_root.add_child(_overlay)

	_chip = BurnChip.new()
	_chip.font = _font
	_chip.custom_minimum_size = Vector2(150, 34)
	_chip.size = Vector2(150, 34)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	_root.add_child(_chip)


func _get_hud():
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud")
	return _hud


# ---------------------------------------------------------------- api

## Pemain terbakar. secs <= 0 = pakai player_burn_time. Dipanggil terus selama pemain berdiri di api.
func ignite_player(secs: float = -1.0) -> void:
	var dur := player_burn_time if secs <= 0.0 else secs
	var fresh := _left <= 0.0
	if dur >= _left:
		_max_left = dur
	_left = maxf(_left, dur)
	_via_hud = _status_hud_present()
	if _via_hud:
		get_tree().call_group("status", "apply_status", "burn", _left)    # StatusHUD menghitung mundur sendiri
	if fresh:
		_tick_t = 0.0
		_pulse = 1.0
		Inventory.message.emit("Terbakar!")
		get_tree().call_group("item_effects", "screen_glow", Color(1.0, 0.45, 0.1), 0.7)
		_shake(0.04, 0.25)


func extinguish() -> void:
	if _left > 0.0:
		_left = 0.0
		if _via_hud:
			get_tree().call_group("status", "cure_status", "burn")
		Inventory.message.emit("Api padam")


func _status_hud_present() -> bool:
	for n in get_tree().get_nodes_in_group("status"):
		if n.has_method("apply_status"):
			return true
	return false


func is_burning() -> bool:
	return _left > 0.0


## Musuh terbakar (api kecil di badannya + damage terus berjalan).
func ignite_enemy(en: Node, secs: float = -1.0) -> void:
	if en == null or not is_instance_valid(en) or not en.has_method("take_damage"):
		return
	var dur := enemy_burn_time if secs <= 0.0 else secs
	if _enemies.has(en):
		_enemies[en]["left"] = maxf(float(_enemies[en]["left"]), dur)
		return
	var fx := _make_enemy_fx()
	en.add_child(fx)
	fx.position = Vector3(0, 0.9, 0)
	_enemies[en] = {"left": dur, "t": 0.0, "fx": fx}
	if en.has_signal("died"):
		en.connect("died", func(_a = null, _b = null): _stop_enemy(en))


# ---------------------------------------------------------------- jalan

func _process(delta: float) -> void:
	if get_tree().paused:
		_root.visible = false
		return
	_time += delta
	_pulse = move_toward(_pulse, 0.0, delta * 2.5)

	# ---- pemain
	if _left > 0.0:
		_left -= delta
		_tick_t += delta
		if _tick_t >= tick:
			_tick_t -= tick
			_tick_player()
	var target := 1.0 if _left > 0.0 else 0.0
	_intensity = move_toward(_intensity, target, delta * (3.0 if target > _intensity else 1.1))
	_appear = move_toward(_appear, target, delta * 5.0)

	var hud = _get_hud()
	var show: bool = hud != null and hud.visible and not hud.intro_mode
	_root.visible = show
	_overlay.visible = _intensity > 0.01
	_mat.set_shader_parameter("intensity", _intensity)
	_mat.set_shader_parameter("pulse", _pulse)
	_chip.visible = _appear > 0.01 and not _via_hud
	if _chip.visible:
		_chip.ratio = _left / maxf(_max_left, 0.01)
		_chip.flash = _pulse
		_chip.t = _time
		_chip.modulate.a = _appear
		_chip.position = Vector2(chip_left, _root.size.y - chip_bottom - _chip.size.y + (1.0 - _appear) * 14.0)
		_chip.queue_redraw()

	# ---- musuh
	for en in _enemies.keys():
		if not is_instance_valid(en) or en.is_queued_for_deletion() or _is_dead(en):
			_stop_enemy(en)
			continue
		var e: Dictionary = _enemies[en]
		e["left"] = float(e["left"]) - delta
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) >= tick:
			e["t"] = float(e["t"]) - tick
			en.take_damage(enemy_burn_dps * tick)
		if float(e["left"]) <= 0.0:
			_stop_enemy(en)


func _tick_player() -> void:
	_pulse = maxf(_pulse, 0.7)
	_shake(0.015, 0.15)
	var h = _player.get_node_or_null("Health")
	if h == null or not h.has_method("take_damage"):
		return
	var d := player_burn_dps * tick
	if not player_can_die and "current_health" in h:
		d = minf(d, float(h.current_health) - 1.0)
	if d > 0.0:
		h.take_damage(d)


func _stop_enemy(en) -> void:
	if not _enemies.has(en):
		return
	var fx = _enemies[en]["fx"]
	if fx != null and is_instance_valid(fx):
		fx.queue_free()
	_enemies.erase(en)


func _is_dead(en: Node) -> bool:
	for k in ["is_dead", "dead", "_dead"]:
		var v = en.get(k)
		if v is bool and v:
			return true
	var hp = en.get("health")
	if hp == null:
		hp = en.get("current_health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		return true
	return not en.is_in_group("enemy")


func _make_enemy_fx() -> CPUParticles3D:
	var fl := CPUParticles3D.new()
	fl.amount = 14
	fl.lifetime = 0.7
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fl.emission_sphere_radius = 0.3
	fl.direction = Vector3.UP
	fl.spread = 20.0
	fl.gravity = Vector3.ZERO
	fl.initial_velocity_min = 0.5
	fl.initial_velocity_max = 1.1
	fl.local_coords = false
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	fl.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.9, 0.4, 0.0), Color(1.0, 0.6, 0.15, 0.95), Color(0.85, 0.2, 0.05, 0.5), Color(0.2, 0.05, 0.02, 0.0)])
	fl.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = m
	fl.mesh = q
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return fl


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
