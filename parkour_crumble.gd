extends Node3D
# Platform rapuh: bergetar begitu diinjak, jatuh, lalu muncul lagi.
# Struktur anak: Slab (CSGBox3D) dan Trigger (Area3D).

@export var shake_time := 0.55
@export var respawn_time := 3.5

var _busy := false
var _home := Vector3.ZERO
@onready var _slab: CSGBox3D = $Slab
@onready var _trigger: Area3D = $Trigger


func _ready() -> void:
	_home = _slab.position
	_trigger.body_entered.connect(_on_enter)


func _on_enter(body: Node) -> void:
	if _busy or not (body is CharacterBody3D):
		return
	_busy = true
	_run()


func _run() -> void:
	get_tree().call_group("sfx", "play", "crumble")
	var t := 0.0
	while t < shake_time:
		var d := get_process_delta_time()
		t += d
		_slab.position = _home + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.035
		await get_tree().process_frame
	_slab.use_collision = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_slab, "position", _home + Vector3(0, -14, 0), 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await get_tree().create_timer(respawn_time).timeout
	_slab.position = _home
	_slab.use_collision = true
	_busy = false
