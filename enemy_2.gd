extends CharacterBody3D

<<<<<<< HEAD
@export var speed: float = 3.0
@export var chase_speed: float = 6.0
@export var wait_time: float = 1.0
@export var waypoint_paths: Array[NodePath] = []

@export_group("Vision")
@export var view_distance: float = 10.0
@export var view_angle: float = 60.0
@export var eye_height: float = 1.5

@export_group("Attack")
@export var attack_range: float = 1.5
@export var damage_per_second: float = 30.0

@export_group("Stuck Detection")
@export var stuck_time_limit: float = 3.0       # lama "gak bisa nyampe" sebelum nyerah
@export var stuck_check_interval: float = 0.5   # tiap berapa detik dicek pergerakannya
@export var stuck_move_threshold: float = 0.3   # minimal jarak gerak biar dianggap "masih maju"
@export var vision_flicker_buffer: float = 0.3

@export_group("Combat")
@export var max_hits: int = 5

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

enum State { PATROL, CHASE }
var state: State = State.PATROL
var flicker_timer: float = 0.0

var waypoints: Array[Node3D] = []
var current_index: int = 0
var waiting: bool = false
var player: Node3D = null

# Stuck detection
var stuck_check_timer: float = 0.0
var stuck_duration: float = 0.0
var position_at_last_check: Vector3 = Vector3.ZERO

# Combat
var current_hits: int = 0
var is_dead: bool = false

func _ready() -> void:
	for path in waypoint_paths:
		var node = get_node(path)
		if node:
			waypoints.append(node)

	await get_tree().physics_frame
	_set_next_target()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_check_vision()

	match state:
		State.PATROL:
			_process_patrol()
		State.CHASE:
			_process_chase(delta)

# ============ COMBAT ============

func take_damage(amount: int = 1) -> void:
	if is_dead:
		return

	current_hits += amount
	print("Musuh kena tembak! (", current_hits, "/", max_hits, ")")

	if current_hits >= max_hits:
		_die()

func _die() -> void:
	is_dead = true
	print("Musuh mati!")
	velocity = Vector3.ZERO
	set_physics_process(false)
	queue_free()

# ============ VISION ============

func _check_vision() -> void:
	if player == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		else:
			return

	var eye_pos: Vector3 = global_position + Vector3.UP * eye_height
	var to_player: Vector3 = player.global_position - eye_pos
	var distance: float = to_player.length()

	var can_see: bool = false

	if state == State.CHASE:
		# Udah ngejar: cukup jarak aja, gak peduli sudut atau tembok
		can_see = distance <= view_distance
	else:
		# Belum ngejar (PATROL): perlu FOV/sudut + line of sight buat "notice" pertama kali
		if distance <= view_distance:
			var forward: Vector3 = -global_transform.basis.z
			var direction_to_player: Vector3 = to_player.normalized()
			var angle: float = rad_to_deg(forward.angle_to(direction_to_player))

			if angle <= view_angle / 2.0:
				can_see = _has_line_of_sight(eye_pos)

	if can_see:
		flicker_timer = vision_flicker_buffer
		if state != State.CHASE:
			state = State.CHASE
			_reset_stuck_tracking()
			print(">>> PLAYER TERLIHAT! Ngejar...")
	else:
		if state == State.CHASE:
			flicker_timer -= get_physics_process_delta_time()
			if flicker_timer <= 0.0:
				_stop_chasing()

func _has_line_of_sight(eye_pos: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(eye_pos, player.global_position + Vector3.UP * 0.5)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result.is_empty() or result.collider == player

func _stop_chasing() -> void:
	state = State.PATROL
	waiting = false
	_set_next_target()
	print("Kehilangan jejak, balik patrol.")

# ============ PATROL ============

func _process_patrol() -> void:
	if waypoints.is_empty() or waiting:
		return

	if nav_agent.is_navigation_finished():
		_go_to_next_waypoint()
		return

	_move_toward_nav_target(speed)

func _go_to_next_waypoint() -> void:
	velocity = Vector3.ZERO
	waiting = true
	await get_tree().create_timer(wait_time).timeout
	if state == State.PATROL:
		current_index = (current_index + 1) % waypoints.size()
		_set_next_target()
	waiting = false

func _set_next_target() -> void:
	if waypoints.is_empty():
		return
	nav_agent.target_position = waypoints[current_index].global_position

# ============ CHASE ============

func _process_chase(delta: float) -> void:
	if player == null:
		state = State.PATROL
		return

	nav_agent.target_position = player.global_position

	var distance_to_player: float = global_position.distance_to(player.global_position)

	if distance_to_player <= attack_range:
		# Udah nempel — berhenti gerak tapi tetap muter badan ngadep player
		velocity.x = 0.0
		velocity.z = 0.0

		var look_dir: Vector3 = player.global_position - global_position
		look_dir.y = 0.0
		if look_dir.length() > 0.01:
			look_at(global_position + look_dir, Vector3.UP)

		move_and_slide()
		_attack_player()
		stuck_duration = 0.0
		return

	_move_toward_nav_target(chase_speed)
	_check_stuck(delta)

func _attack_player() -> void:
	var health_node = player.get_node_or_null("Health")
	if health_node:
		health_node.take_damage(damage_per_second * get_physics_process_delta_time())

# ============ STUCK DETECTION ============

func _reset_stuck_tracking() -> void:
	stuck_duration = 0.0
	stuck_check_timer = 0.0
	position_at_last_check = global_position

func _check_stuck(delta: float) -> void:
	stuck_check_timer += delta
	if stuck_check_timer < stuck_check_interval:
		return

	var moved: float = global_position.distance_to(position_at_last_check)

	if moved < stuck_move_threshold:
		stuck_duration += stuck_check_timer
	else:
		stuck_duration = 0.0

	position_at_last_check = global_position
	stuck_check_timer = 0.0

	if stuck_duration >= stuck_time_limit:
		print("Musuh nggak bisa nyampe ke player, balik patrol.")
		_stop_chasing()

# ============ SHARED MOVEMENT ============

func _move_toward_nav_target(move_speed: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position)
	direction.y = 0.0
	direction = direction.normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)
=======
const SPEED = 2.0

@onready var navigation_agent = $NavigationAgent3D
@onready var waypoint = $"../Waypoint1"


func _ready():
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 1.0

	await get_tree().physics_frame
	await get_tree().physics_frame

	navigation_agent.target_position = waypoint.global_position

	print("=== TEST NAVIGATION ===")
	print("Enemy: ", global_position)
	print("Waypoint: ", waypoint.global_position)
	print("Target: ", navigation_agent.target_position)
	print("Navigation Map: ", navigation_agent.get_navigation_map())
	print("Path length: ", navigation_agent.get_path_length())
	print("Final position: ", navigation_agent.get_final_position())
	print("Target reachable: ", navigation_agent.is_target_reachable())


func _physics_process(delta):
	var next_position = navigation_agent.get_next_path_position()

	print("Next: ", next_position)
	print("Path length: ", navigation_agent.get_path_length())

	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var direction = global_position.direction_to(next_position)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
>>>>>>> 753456d60b4f7b21aa26053926be2ef0644aaf5b

	move_and_slide()
