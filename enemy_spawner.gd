extends Node
## Spawn musuh di titik-titik Marker3D (anak dari node "Points").
## Panggil start() buat mulai, stop() buat berhenti.

@export var enemy_scene: PackedScene
@export var interval: float = 3.0
@export var max_alive: int = 5
@export var first_delay: float = 1.5
@export var first_burst: int = 2

var _alive := 0
var _running := false
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = interval
	_timer.one_shot = false
	_timer.timeout.connect(_spawn)
	add_child(_timer)


func start() -> void:
	if _running:
		return
	_running = true
	if enemy_scene == null:
		push_warning("EnemySpawner: Enemy Scene belum diisi di Inspector")
		return
	await get_tree().create_timer(first_delay).timeout
	if not _running:
		return
	for i in first_burst:
		_spawn()
	_timer.start(interval)


func stop() -> void:
	_running = false
	_timer.stop()


func _spawn() -> void:
	if not _running or enemy_scene == null or _alive >= max_alive:
		return
	var points := get_node("Points").get_children().filter(func(n): return n is Node3D)
	if points.is_empty():
		return

	var enemy: Node3D = enemy_scene.instantiate()
	get_parent().add_child(enemy)
	enemy.global_position = points.pick_random().global_position
	_alive += 1
	enemy.tree_exited.connect(func(): _alive -= 1)
