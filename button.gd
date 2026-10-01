extends StaticBody3D

@onready var enemy = $"../enemy"

func interact():
	print("START!")
	enemy.start_chase()
