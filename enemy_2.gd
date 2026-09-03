extends CharacterBody3D

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

	move_and_slide()
