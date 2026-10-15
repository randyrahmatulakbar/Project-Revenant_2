extends Area3D
## Genangan racun di lantai. Player yang berdiri di dalamnya kena racun.

const PoisonDot := preload("res://poison_dot.gd")

var radius: float = 1.5
var lifetime: float = 4.0
var dps: float = 5.0
var _mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	# taruh di lantai di bawahnya
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -4.0, 0))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position + Vector3(0, 0.03, 0)

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.6, 0)
	add_child(cs)

	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	disc.radial_segments = 10
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.45, 1.0, 0.25, 0.65)
	disc.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.3)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = Vector3(0, 0.5, 0)
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			PoisonDot.apply(b, dps, 1.5)
	var fade := clampf((lifetime - _t) / 1.0, 0.0, 1.0)
	if _mat:
		_mat.albedo_color.a = 0.65 * fade * (0.8 + 0.2 * sin(_t * 8.0))
	if _t >= lifetime:
		queue_free()
