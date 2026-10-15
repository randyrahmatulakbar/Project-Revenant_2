extends Node
## Bikin sprite HUD (tangan / senjata) ikut gelap-terang sesuai cahaya
## di sekitar kamera. Pakai self_modulate, jadi efek lain yang pakai
## modulate (kilatan, dll) gak keganggu.

@export var target: CanvasItem
## Warna paling gelap (biar sprite gak pernah hitam pekat)
@export var min_color: Color = Color(0.14, 0.11, 0.11)
## Pengali kekuatan cahaya. Kecilin kalau HUD masih kerasa terlalu terang.
@export var strength: float = 0.8
## Kecepatan transisi gelap <-> terang
@export var smooth: float = 6.0

var _lights: Array = []
var _refresh := 0.0
var _env: Environment


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_collect()

	# cahaya ambient + jumlah cahaya omni yang ngenain posisi kamera
	var acc := _ambient()
	var pos := cam.global_position
	for l in _lights:
		if not is_instance_valid(l) or not l.is_visible_in_tree() or l.light_negative:
			continue
		var d: float = pos.distance_to(l.global_position)
		if d >= l.omni_range or l.light_energy <= 0.0:
			continue
		var atten: float = pow(1.0 - d / l.omni_range, l.omni_attenuation)
		acc += l.light_color * (l.light_energy * atten * strength)

	var goal := Color(
		clampf(acc.r, min_color.r, 1.0),
		clampf(acc.g, min_color.g, 1.0),
		clampf(acc.b, min_color.b, 1.0), 1.0)
	target.self_modulate = target.self_modulate.lerp(goal, 1.0 - exp(-smooth * delta))


func _collect() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_lights = root.find_children("*", "OmniLight3D", true, false)
	if _env == null:
		var we := root.find_child("WorldEnvironment", true, false)
		if we is WorldEnvironment:
			_env = we.environment


func _ambient() -> Color:
	if _env and _env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR:
		var c := _env.ambient_light_color * _env.ambient_light_energy
		return Color(c.r, c.g, c.b, 1.0)
	return Color(0.05, 0.05, 0.05, 1.0)
