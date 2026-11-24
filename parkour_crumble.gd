extends Node3D
# Platform rapuh: bergetar begitu diinjak, jatuh, lalu muncul lagi.
# Struktur anak: Slab (CSGBox3D), Trigger (Area3D), dan strip edge / edge2 / edge3 / ... (opsional).
# Semua strip "edge*" ikut bergetar, ikut jatuh bersama Slab, dan balik ke tempatnya saat muncul lagi.

@export var shake_time := 0.55
@export var respawn_time := 3.5

var _busy := false
var _home := Vector3.ZERO
var _parts: Array[Node3D] = []      # strip edge yang ikut Slab
var _homes := {}                    # strip -> posisi awal
@onready var _slab: CSGBox3D = get_node_or_null("Slab") as CSGBox3D
@onready var _trigger: Area3D = get_node_or_null("Trigger") as Area3D


func _ready() -> void:
	# Crumble yang belum lengkap (tanpa Slab / Trigger) dimatikan, bukan bikin crash.
	if _slab == null or _trigger == null:
		push_warning("%s: butuh anak 'Slab' (CSGBox3D) dan 'Trigger' (Area3D), crumble dimatikan" % get_path())
		return
	if _trigger.get_child_count() == 0:
		push_warning("%s: Trigger belum punya CollisionShape3D, platform tidak akan runtuh" % get_path())
	_home = _slab.position
	for c in get_children():
		if c is Node3D and c != _slab and String(c.name).to_lower().begins_with("edge"):
			_parts.append(c)
			_homes[c] = c.position
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
		var off := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.035
		_slab.position = _home + off
		for part in _parts:
			part.position = _homes[part] + off
		await get_tree().process_frame
	_slab.use_collision = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_slab, "position", _home + Vector3(0, -14, 0), 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	for part in _parts:
		tw.tween_property(part, "position", Vector3(_homes[part]) + Vector3(0, -14, 0), 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await get_tree().create_timer(respawn_time).timeout
	_slab.position = _home
	for part in _parts:
		part.position = _homes[part]
	_slab.use_collision = true
	_busy = false
