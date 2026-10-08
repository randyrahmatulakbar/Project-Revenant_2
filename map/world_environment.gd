@tool
extends WorldEnvironment

func _ready():
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.01, 0.01)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.6, 0.5)
	env.ambient_light_energy = 0.35

	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.04, 0.03)
	env.fog_density = 0.03

	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.95

	environment = env
