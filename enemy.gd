extends CharacterBody3D

const SPEED = 3.0

var can_chase = false

@onready var navigation_agent = $NavigationAgent3D
@onready var player = $"../subject"


func _ready():
	await get_tree().physics_frame
	print("PLAYER: ", player)
	print("NAV AGENT: ", navigation_agent)


func _physics_process(delta):
	if not can_chase:
		velocity = Vector3.ZERO
		return

	if player == null:
		return

	navigation_agent.target_position = player.global_position

	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var next_position = navigation_agent.get_next_path_position()

	var direction = global_position.direction_to(next_position)
	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	move_and_slide()
	
	if player == null:
		return

	navigation_agent.target_position = player.global_position

	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	move_and_slide()
	
func start_chase():
	can_chase = true
