extends Node3D
## Tumpukan loot di lantai (dibuat LootManager). items = [{"item": ItemData, "amount": int}, ...]
##
## Tampilan:
##   - ikon item melayang (kalau item punya icon; kalau tidak, permata kecil yang berputar) + halo cahaya di belakangnya
##   - cincin cahaya di lantai dengan gelombang yang memancar keluar
##   - berkas cahaya tipis ke atas (lebih tinggi dan terang untuk artefak / senjata, kelihatan dari jauh)
##   - beberapa butir debu cahaya yang naik pelan
##   - makin terang saat pemain mendekat, berkedip sebelum hilang (kalau lifetime > 0)
## Semuanya shader / partikel, tanpa OmniLight, jadi ringan walau banyak tumpukan di lantai.

const Catalog = preload("item_catalog.gd")

const HOVER := 0.45              # tinggi ikon di atas lantai (m)
const ICON_SIZE := 0.42          # ukuran ikon di dunia (m)
const NEAR_DIST := 3.5           # jarak pemain yang bikin tumpukan menyala lebih terang
const BLINK_TIME := 6.0          # berkedip selama sekian detik terakhir sebelum hilang

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float phase = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float glow = pow(smoothstep(1.0, 0.0, r), 2.2) * 0.5;
	float pulse = 0.5 + 0.5 * sin(TIME * 2.4 + phase);
	float ring = smoothstep(0.06, 0.0, abs(r - 0.82)) * (0.65 + 0.35 * pulse);
	float k = fract(TIME * 0.55 + phase);
	float wave = smoothstep(0.05, 0.0, abs(r - mix(0.25, 0.85, k))) * (1.0 - k) * 0.7;
	float a = (glow + ring + wave) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = col.rgb;
	ALPHA = clamp(a * energy, 0.0, 1.0);
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float height = 1.0;
uniform float phase = 0.0;
varying float hgt;
void vertex() {
	hgt = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}
void fragment() {
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	float fade = pow(1.0 - hgt, 1.4);
	float flick = 0.85 + 0.15 * sin(TIME * 3.0 + phase + hgt * 7.0);
	ALBEDO = col.rgb;
	ALPHA = clamp(edge * fade * flick * 0.55 * energy, 0.0, 1.0);
}
"""

var items: Array = []
var lifetime := 0.0            # 0 = tidak pernah hilang
var _t := 0.0
var _phase := randf() * 10.0
var _col := Color(0.9, 0.85, 0.8)
var _unique := false
var _ground := -0.1            # tinggi lantai relatif ke node ini (dicari dengan raycast, cadangan -0.1)
var _near := 0.0
var _player: Node3D

var _vis: Node3D
var _float: Node3D
var _gem: MeshInstance3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _motes: CPUParticles3D
var _ring_mat: ShaderMaterial
var _beam_mat: ShaderMaterial
var _halo_mat: StandardMaterial3D
var _gem_mat: StandardMaterial3D
var _beam_h := 1.1


func _ready() -> void:
	add_to_group("loot_drop")
	_build()
	_find_ground()
	scale = Vector3.ONE * 0.1
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- data tumpukan

func _pile_color() -> Color:
	var best := Color(0.9, 0.85, 0.8)
	for it in items:
		var item: ItemData = it.item
		if Catalog.is_unique(item):
			return Catalog.color_of(item)              # ada artefak / senjata -> paling menonjol
		best = Catalog.color_of(item)
	return best


func _has_unique_item() -> bool:
	for it in items:
		if Catalog.is_unique(it.item):
			return true
	return false


# Item yang jadi "wajah" tumpukan: artefak / senjata dulu, kalau tidak ada yang pertama.
func _primary_item() -> ItemData:
	for it in items:
		if Catalog.is_unique(it.item):
			return it.item
	if items.is_empty():
		return null
	return items[0].item


# ---------------------------------------------------------------- bangun visual

func _build() -> void:
	_col = _pile_color()
	_unique = _has_unique_item()
	_beam_h = 2.8 if _unique else 1.1

	_vis = Node3D.new()
	add_child(_vis)

	# cincin di lantai
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _make_shader(RING_SHADER)
	_ring_mat.set_shader_parameter("col", _col.lightened(0.1))
	_ring_mat.set_shader_parameter("phase", _phase)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.7)
	_ring = MeshInstance3D.new()
	_ring.mesh = qm
	_ring.material_override = _ring_mat
	_ring.rotation_degrees.x = -90.0
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(_ring)

	# berkas cahaya
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = _make_shader(BEAM_SHADER)
	_beam_mat.set_shader_parameter("col", _col.lightened(0.15))
	_beam_mat.set_shader_parameter("height", _beam_h)
	_beam_mat.set_shader_parameter("phase", _phase)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.17 if _unique else 0.12
	cm.height = _beam_h
	cm.radial_segments = 14
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.mesh = cm
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(_beam)

	# bagian yang melayang: halo + ikon / permata
	_float = Node3D.new()
	_vis.add_child(_float)

	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_halo_mat.albedo_texture = _halo_texture()
	_halo_mat.albedo_color = Color(_col, 0.5)
	var hq := QuadMesh.new()
	hq.size = Vector2(1.0, 1.0)
	var halo := MeshInstance3D.new()
	halo.mesh = hq
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float.add_child(halo)

	var item := _primary_item()
	if item != null and item.icon != null:
		var tex: Texture2D = item.icon
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = ICON_SIZE / maxf(float(maxi(tex.get_width(), tex.get_height())), 1.0)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false
		sp.double_sided = true
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_float.add_child(sp)
		_gem = null
	else:
		_gem_mat = StandardMaterial3D.new()
		_gem_mat.albedo_color = _col.darkened(0.5)
		_gem_mat.emission_enabled = true
		_gem_mat.emission = _col
		_gem_mat.emission_energy_multiplier = 1.8
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.2, 0.2)
		bm.material = _gem_mat
		_gem = MeshInstance3D.new()
		_gem.mesh = bm
		_gem.rotation_degrees = Vector3(35.0, 0.0, 35.0)
		_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_float.add_child(_gem)

	# debu cahaya
	_motes = CPUParticles3D.new()
	_motes.amount = 9 if _unique else 6
	_motes.lifetime = 1.8
	_motes.preprocess = 1.8
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 0.3
	_motes.direction = Vector3.UP
	_motes.spread = 22.0
	_motes.gravity = Vector3.ZERO
	_motes.initial_velocity_min = 0.15
	_motes.initial_velocity_max = 0.4
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.1
	_motes.color = _col.lightened(0.2)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_motes.color_ramp = g
	var mq := QuadMesh.new()
	mq.size = Vector2(0.045, 0.045)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.vertex_color_use_as_albedo = true
	mm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mq.material = mm
	_motes.mesh = mq
	_vis.add_child(_motes)
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_layout()


func _make_shader(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code
	return sh


# Lingkaran lembut (terang di tengah, transparan di tepi) untuk halo.
func _halo_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


# Tinggi lantai: raycast ke bawah (hanya layer dunia; bangkai musuh / CharacterBody diabaikan).
func _find_ground() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var from := global_position + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0)
	q.collision_mask = 1
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty() and not (r.collider is CharacterBody3D):
		_ground = float(r.position.y) - global_position.y
		_layout()


func _layout() -> void:
	if _ring != null:
		_ring.position.y = _ground + 0.03
	if _beam != null:
		_beam.position.y = _ground + _beam_h * 0.5
	if _motes != null:
		_motes.position.y = _ground + 0.15


# ---------------------------------------------------------------- jalan

func _process(delta: float) -> void:
	_t += delta
	var tt := _t + _phase

	# melayang pelan
	if _float != null:
		_float.position.y = _ground + HOVER + 0.07 * sin(tt * 2.2)
	if _gem != null:
		_gem.rotation.y += delta * 1.4

	# makin terang saat pemain dekat
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var target := 0.0
	if _player != null and global_position.distance_to(_player.global_position) < NEAR_DIST:
		target = 1.0
	_near = move_toward(_near, target, delta * 3.0)

	# berkedip sebelum hilang
	var flick := 1.0
	if lifetime > 0.0:
		var left := lifetime - _t
		if left < BLINK_TIME:
			flick = 0.3 + 0.7 * absf(sin(_t * 9.0))
		if left <= 0.0:
			queue_free()
			return

	var base := (1.35 if _unique else 1.0) * flick
	if _ring_mat != null:
		_ring_mat.set_shader_parameter("energy", (0.8 + 0.7 * _near) * base)
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("energy", (0.75 + 0.55 * _near) * base)
	if _halo_mat != null:
		var pulse := 0.5 + 0.5 * sin(tt * 3.0)
		_halo_mat.albedo_color = Color(_col, (0.35 + 0.25 * pulse + 0.25 * _near) * flick)
	if _gem_mat != null:
		_gem_mat.emission_energy_multiplier = (1.6 + 1.2 * _near) * flick


## Gabungkan loot baru ke tumpukan ini (item yang sama dijumlah). Dipakai saat dua drop berdekatan.
func add_items(extra: Array) -> void:
	for e in extra:
		var found := false
		if e.has("rounds"):                            # magazine dengan isi sendiri tidak digabung
			items.append(e)
			continue
		for it in items:
			if it.item.id == e.item.id and not it.has("rounds"):
				it.amount = int(it.amount) + int(e.amount)
				found = true
				break
		if not found:
			items.append({"item": e.item, "amount": int(e.amount)})
	_t = 0.0
	if _vis != null:                                   # warna / ikon utama bisa berubah: bangun ulang visual
		remove_child(_vis)
		_vis.queue_free()
	_build()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.25, 0.1)
	tw.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func has_unique(id: StringName) -> bool:
	for it in items:
		if it.item.id == id:
			return true
	return false
