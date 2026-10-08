extends StaticBody3D
## Pistol melayang. Diambil lewat sistem interaksi player:
## player-test.gd nembak raycast dari crosshair, kalau kena objek yang punya
## fungsi interact() dan tombol "interact" ditekan -> interact() dipanggil.
## Prompt (interek.gd) juga diurus player, jadi di sini gak perlu.

signal picked_up

const PICK_MASK := 1 << 19   # collision layer 20, cuma buat raycast

@export var prompt_text: String = "AMBIL"
@export var max_distance: float = 3.0
@export var bob_height: float = 0.12
@export var bob_speed: float = 1.5

@onready var sprite: Sprite3D = $Sprite3D
@onready var light: OmniLight3D = $OmniLight3D

var _prompt: Control
var _prev_text := ""
var _base_y := 0.0
var _base_scale := Vector3.ONE
var _base_energy := 1.5
var _time := 0.0
var _taken := false
var _looking := false
var _hl_tween: Tween


func _ready() -> void:
	_prompt = get_node_or_null("../CanvasLayer/interek")
	_base_y = position.y
	_base_scale = sprite.scale
	_base_energy = light.light_energy


# dipanggil player pas tombol interact ditekan dan crosshair ngarah ke sini
func interact() -> void:
	if _taken:
		return
	_pickup()


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height
	light.light_energy = _base_energy * (0.8 + 0.2 * sin(_time * 7.0) + 0.1 * sin(_time * 13.0))


# cuma buat efek "disorot" + ganti teks prompt jadi AMBIL
func _physics_process(_delta: float) -> void:
	if _taken:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * max_distance
	var q := PhysicsRayQueryParameters3D.create(from, to, PICK_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_set_looking(not hit.is_empty() and hit.collider == self)


func _set_looking(on: bool) -> void:
	if on == _looking:
		return
	_looking = on

	if _prompt and "action_text" in _prompt:
		if on:
			_prev_text = _prompt.action_text
			_prompt.action_text = prompt_text
		else:
			_prompt.action_text = _prev_text

	if _hl_tween:
		_hl_tween.kill()
	_hl_tween = create_tween().set_parallel(true)
	_hl_tween.tween_property(sprite, "scale", _base_scale * (1.15 if on else 1.0), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hl_tween.tween_property(sprite, "modulate",
		Color(1.6, 1.5, 1.35) if on else Color(1.2, 1.15, 1.1), 0.15)


func _pickup() -> void:
	_taken = true
	if _looking and _prompt and "action_text" in _prompt:
		_prompt.action_text = _prev_text
	set_deferred("collision_layer", 0)   # prompt langsung ilang
	picked_up.emit()

	# pistol "ketarik" ke kamera sambil mengecil, cahayanya menyala
	var cam := get_viewport().get_camera_3d()
	var target := cam.global_position - cam.global_transform.basis.z * 0.5 + Vector3.DOWN * 0.25
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", target, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(sprite, "scale", _base_scale * 0.15, 0.28)
	tw.tween_property(light, "light_energy", 8.0, 0.14)
	await tw.finished
	queue_free()
