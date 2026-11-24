extends RigidBody3D
## GRANAT YANG DILEMPAR. Dibuat oleh grenade_hand.gd (tidak perlu dipasang manual).
## Meledak setelah fuse detik, atau langsung saat mengenai musuh. Ledakan melukai musuh DAN pemain (self_damage).

# Gaya ledakan (dipakai juga oleh Ember Core): peach / krem / teal gelap, bergerak per frame
const EXPLO_FPS := 12.0
const GLOW_COL := Color(0.87, 0.65, 0.54)          # peach UI (kilatan layar & cahaya)
const COL_CREAM := Color(1.0, 0.92, 0.8)
const COL_PEACH := Color(0.87, 0.65, 0.54)
const COL_EMBER := Color(0.9, 0.33, 0.24)           # merah bar HP
const COL_SMOKE := Color(0.82, 0.79, 0.8)
const COL_SPARK := Color(1.0, 0.85, 0.45)
const VOX_N := 5                                    # radius kubah dalam jumlah kotak

var fuse := 2.0
var radius := 5.0
var damage_enemy := 12.0
var self_damage := 15.0
var can_kill_player := false
var knockback := 7.0
var impact_on_enemy := true
var shake := true

var _t := 0.0
var _blink: MeshInstance3D
var _done := false


func _ready() -> void:
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.4
	pm.friction = 0.7
	physics_material_override = pm
	linear_damp = 0.1
	angular_damp = 0.8
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.1
	cs.shape = sph
	add_child(cs)
	# tampilan: badan hijau zaitun + tutup baja + lampu kecil berkedip
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.3, 0.38, 0.17)
	bm.roughness = 0.9
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sm.material = bm
	body.mesh = sm
	body.scale = Vector3(1.0, 1.25, 1.0)
	add_child(body)
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.07, 0.05, 0.07)
	var capm := StandardMaterial3D.new()
	capm.albedo_color = Color(0.36, 0.48, 0.46)
	cm.material = capm
	cap.mesh = cm
	cap.position = Vector3(0, 0.15, 0)
	add_child(cap)
	_blink = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.025
	bs.height = 0.05
	var blm := StandardMaterial3D.new()
	blm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blm.albedo_color = Color(1.0, 0.3, 0.2)
	bs.material = blm
	_blink.mesh = bs
	_blink.position = Vector3(0, 0.2, 0.05)
	add_child(_blink)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	var rate := lerpf(4.0, 22.0, clampf(_t / fuse, 0.0, 1.0))      # makin dekat meledak makin cepat berkedip
	_blink.visible = fmod(_t * rate, 1.0) < 0.5


func _physics_process(_delta: float) -> void:
	if not _done and _t >= fuse:
		_explode()


func _on_body(b: Node) -> void:
	if impact_on_enemy and not _done and b.is_in_group("enemy"):
		_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	var tree := get_tree()
	var pos := global_position
	for en in tree.get_nodes_in_group("enemy"):
		if en is Node3D and en.has_method("take_damage"):
			var d := ((en as Node3D).global_position + Vector3(0, 1.0, 0)).distance_to(pos)
			if d <= radius:
				en.take_damage(damage_enemy * lerpf(1.0, 0.4, d / radius))
	var near := 0.0
	var p := tree.get_first_node_in_group("player") as Node3D
	if p != null:
		var v := (p.global_position + Vector3(0, 1.0, 0)) - pos
		var dist := v.length()
		near = clampf(1.0 - dist / (radius * 1.8), 0.0, 1.0)
		if dist <= radius:
			var h := p.get_node_or_null("Health")
			var dmg := self_damage * lerpf(1.0, 0.4, dist / radius)
			if h != null and h.has_method("take_damage"):
				if not can_kill_player and "current_health" in h:
					dmg = minf(dmg, float(h.current_health) - 1.0)
				if dmg > 0.0:
					h.take_damage(dmg)
			if knockback > 0.0 and "velocity" in p:
				var away := v
				away.y = 0.0
				p.velocity += away.normalized() * knockback + Vector3(0, 2.5, 0)
	_fx(pos)
	if near > 0.05:
		tree.call_group("item_effects", "screen_glow", GLOW_COL, near)
		if shake:
			_shake(near)
	queue_free()


func _shake(power: float) -> void:
	shake_camera(get_viewport(), power)


static func shake_camera(vp: Viewport, power: float) -> void:
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var tw := cam.create_tween()
	for i in 7:
		var k := 1.0 - float(i) / 7.0
		tw.tween_property(cam, "h_offset", randf_range(-1.0, 1.0) * 0.18 * power * k, 0.035)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-1.0, 1.0) * 0.14 * power * k, 0.035)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)


# ---------- efek 3D ----------
static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


static func _particles(root: Node, pos: Vector3, col: Color, amount: int, size: float, speed: float, life: float, spread: float = 180.0, grav: float = -9.8) -> void:
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
	p.fixed_fps = int(EXPLO_FPS)                       # simulasi partikel per frame
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func _fx(pos: Vector3) -> void:
	explosion_fx(get_tree().current_scene, pos, radius)


## Ledakan voxel (granat & Ember Core): kubah kotak-kotak krem -> kuning -> peach -> abu muda, lalu pecah jadi
## gumpalan asap kotak yang naik dan menyusut. Semua per frame (EXPLO_FPS). pos = titik di LANTAI.
static func explosion_fx(root: Node, pos: Vector3, rad: float) -> void:
	if root == null:
		return
	pos = _floor_pos(root, pos)
	var dt := 1.0 / EXPLO_FPS
	var vs := rad * 0.45 / (VOX_N + 0.5)              # ukuran satu kotak (m)
	# --- kisi kotak setengah bola dengan tepi bergerigi
	var cp := PackedVector3Array()
	var cd := PackedFloat32Array()
	var cr := PackedFloat32Array()
	for ix in range(-VOX_N, VOX_N + 1):
		for iz in range(-VOX_N, VOX_N + 1):
			for iy in range(0, VOX_N + 1):
				var c := Vector3(ix, iy + 0.5, iz)
				var d := c.length() / (VOX_N + 0.5) + randf_range(-0.12, 0.12)
				if d <= 1.0:
					cp.append(c)
					cd.append(clampf(d, 0.0, 1.0))
					cr.append(randf())
	# --- kotak asap: dari bagian atas kubah
	var sp := PackedVector3Array()
	var sl := PackedInt32Array()
	for k in 24:
		sp.append(Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 4.5), randf_range(-2.0, 2.0)))
		sl.append(4 + randi() % 7)
	var nc := cp.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	bx.material = mat
	mm.mesh = bx
	mm.instance_count = nc + sp.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	mmi.global_position = pos
	var st := {"cp": cp, "cd": cd, "cr": cr, "sp": sp, "sl": sl, "vs": vs, "nc": nc}
	var frames := 15
	var tw := mmi.create_tween()
	for f in frames:
		tw.tween_callback(_vox_frame.bind(mmi, st, f))
		tw.tween_interval(dt)
	tw.tween_callback(mmi.queue_free)
	# --- cahaya hangat, turun per frame
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 6.0
	l.omni_range = rad * 2.0
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos + Vector3(0, rad * 0.2, 0)
	var le: Array[float] = [6.0, 6.0, 5.0, 3.0, 1.5, 0.6, 0.0]
	var tl := l.create_tween()
	for i in le.size():
		tl.tween_callback(_light_frame.bind(l, le[i]))
		tl.tween_interval(dt)
	tl.tween_callback(l.queue_free)
	# --- percikan kecil (kotak mungil, per frame)
	_particles(root, pos + Vector3(0, vs * 2.0, 0), COL_SPARK, 26, 0.05, 7.0, 0.8)
	_particles(root, pos + Vector3(0, vs * 2.0, 0), COL_CREAM, 12, 0.04, 9.0, 0.5)


# Cari lantai di bawah titik ledakan (kubah menempel di lantai, bukan melayang).
static func _floor_pos(root: Node, pos: Vector3) -> Vector3:
	if root is Node3D:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 4.0)
		q.collision_mask = 1
		var r: Dictionary = (root as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty() and not (r.collider is CharacterBody3D):
			return r.position
	return pos


static func _vox_frame(mmi: MultiMeshInstance3D, st: Dictionary, f: int) -> void:
	if not is_instance_valid(mmi):
		return
	var mm := mmi.multimesh
	var cp: PackedVector3Array = st["cp"]
	var cd: PackedFloat32Array = st["cd"]
	var cr: PackedFloat32Array = st["cr"]
	var sp: PackedVector3Array = st["sp"]
	var sl: PackedInt32Array = st["sl"]
	var vs: float = st["vs"]
	var nc: int = st["nc"]
	var reach: Array[float] = [0.35, 0.6, 0.85, 1.0, 1.05, 1.05]
	var dens: Array[float] = [1.0, 1.0, 1.0, 0.97, 0.88, 0.7]
	var alp: Array[float] = [1.0, 1.0, 1.0, 0.95, 0.8, 0.5]
	var base: Array[Color] = [Color(1.0, 0.93, 0.65), Color(1.0, 0.95, 0.72), Color(1.0, 0.9, 0.62),
		Color(1.0, 0.72, 0.45), Color(0.93, 0.62, 0.52), Color(0.78, 0.58, 0.58)]
	var off := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var hide_c := Color(0, 0, 0, 0)
	# kubah
	for i in nc:
		var vis := false
		var col := hide_c
		if f < reach.size():
			var c := cp[i]
			var ok := cd[i] <= reach[f] and cr[i] <= dens[f]
			if f == 0 and Vector2(c.x, c.z).length() > 1.3:
				ok = false
			if ok:
				vis = true
				col = base[f]
				if f >= 3:
					col = col.lerp(COL_EMBER, clampf(cd[i] - 0.4, 0.0, 1.0) * 0.35)
				var j := (cr[i] - 0.5) * 0.14
				col = Color(clampf(col.r + j, 0.0, 1.0), clampf(col.g + j, 0.0, 1.0), clampf(col.b + j, 0.0, 1.0), alp[f])
		if vis:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * vs), cp[i] * vs))
			mm.set_instance_color(i, col)
		else:
			mm.set_instance_transform(i, off)
			mm.set_instance_color(i, hide_c)
	# asap kotak: muncul saat kubah memudar, naik dan menyusut
	var k := f - 5
	for s in sp.size():
		var idx := nc + s
		if k >= 0 and k < sl[s]:
			var y := sp[s].y * vs + vs * 0.45 * float(k)
			var sz := vs * maxf(1.15 - 0.09 * float(k), 0.3)
			mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * sz), Vector3(sp[s].x * vs, y, sp[s].z * vs)))
			mm.set_instance_color(idx, Color(COL_SMOKE, 1.0 if k < sl[s] - 1 else 0.6))
		else:
			mm.set_instance_transform(idx, off)
			mm.set_instance_color(idx, hide_c)


static func _light_frame(l: OmniLight3D, e: float) -> void:
	if is_instance_valid(l):
		l.light_energy = e
