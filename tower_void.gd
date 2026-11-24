extends Area3D
## TOWER VOID: jatuh ke void di dasar tower = kena damage, layar menggelap sebentar, lalu pemain dikembalikan
## ke awal ruangan tower (Marker3D "ruangan ini").
## Zona jatuh = ukuran CollisionShape3D (BoxShape3D) anak node ini; atur posisi / ukurannya di editor.
## Deteksinya memeriksa posisi pemain langsung (group "player"), jadi tidak tergantung collision layer / mask.

@export var fall_damage := 15.0
@export var can_kill := false              # false = jatuh tidak pernah membunuh (HP minimal 1)
@export var respawn_marker: NodePath = NodePath("../ruangan ini")
@export var fade_out := 0.18
@export var fade_in := 0.4
@export var cooldown := 0.8

var _busy := false
var _half := Vector3(14.5, 1.25, 16.5)
var _center := Vector3.ZERO
var _fade: ColorRect


func _ready() -> void:
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			_half = ((c as CollisionShape3D).shape as BoxShape3D).size * 0.5
			_center = (c as CollisionShape3D).position
			break
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _physics_process(_delta: float) -> void:
	if _busy:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var l := to_local(p.global_position) - _center
	if absf(l.x) <= _half.x and absf(l.y) <= _half.y and absf(l.z) <= _half.z:
		_fall(p)


func _fall(p: Node3D) -> void:
	_busy = true
	var dmg := fall_damage
	var h = p.get_node_or_null("Health")
	if h != null and h.has_method("take_damage"):
		if not can_kill and "current_health" in h:
			dmg = minf(dmg, float(h.current_health) - 1.0)
		if dmg > 0.0:
			h.take_damage(dmg)
		if "current_health" in h and float(h.current_health) <= 0.0:
			return                                          # mati karena jatuh: death screen yang mengurus
	get_tree().call_group("sfx", "play", "punch_hit", 0.0, 0.05)
	get_tree().call_group("item_effects", "screen_glow", Color(0.7, 0.08, 0.05), 0.9)
	if dmg > 0.0:
		Inventory.message.emit("Jatuh!  -%d HP" % int(round(dmg)))
	else:
		Inventory.message.emit("Jatuh!")

	await _fade_to(1.0, fade_out)
	_teleport(p)
	await _fade_to(0.0, fade_in)
	await get_tree().create_timer(cooldown).timeout
	_busy = false


func _fade_to(a: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, t)
	await tw.finished


func _teleport(p: Node3D) -> void:
	var m := get_node_or_null(respawn_marker) as Node3D
	if m == null and get_parent() != null:
		m = get_parent().find_child("ruangan ini", true, false) as Node3D
	if m == null:
		push_warning("TowerVoid: Marker3D 'ruangan ini' tidak ketemu, pemain tidak dipindahkan.")
		return
	p.global_position = m.global_position
	if "velocity" in p:
		p.velocity = Vector3.ZERO
	var head = p.get("head")
	if head is Node3D:
		(head as Node3D).rotation.y = m.global_rotation.y   # menghadap arah marker
	if "_wall_hops" in p:
		p._wall_hops = 0
	if p.has_method("reset_physics_interpolation"):
		p.reset_physics_interpolation()
