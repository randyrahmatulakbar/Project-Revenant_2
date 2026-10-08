extends Area3D
## Pasang di Area3D "TriggerArea" (anak dari marker "trigger").
## Pas player masuk, asap di marker "pipeleak" nyala.

@export var particles: GPUParticles3D
@export var light: OmniLight3D
@export var sound: AudioStreamPlayer3D
@export var player_group: StringName = &"player"
## Jeda setelah player masuk zona (detik)
@export var delay: float = 0.2
## Berapa lama bocor (detik). 0 = bocor terus.
@export var leak_duration: float = 0.0
## Semburan awal lebih kenceng lalu normal (1.0 = nonaktif)
@export var burst_speed: float = 2.5
@export var light_peak: float = 6.0
@export var light_rest: float = 2.0

var triggered := false


func _ready() -> void:
	if particles:
		particles.emitting = false
		particles.preprocess = 0.0
	if light:
		light.visible = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	var ok := body.is_in_group("player")
	print("player? ", ok, " | triggered: ", triggered, " | particles: ", particles)
	if triggered or not ok:
		return
	triggered = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	print("LEAK START")
	_start_leak()


func _start_leak() -> void:
	if sound:
		sound.play()

	if particles:
		particles.speed_scale = burst_speed
		particles.restart()
		particles.emitting = true
		create_tween().tween_property(particles, "speed_scale", 1.0, 1.2)

	if light:
		light.visible = true
		light.light_energy = 0.0
		var lt := create_tween()
		lt.tween_property(light, "light_energy", light_peak, 0.08)
		lt.tween_property(light, "light_energy", light_rest, 0.8)

	if leak_duration > 0.0:
		await get_tree().create_timer(leak_duration).timeout
		_stop_leak()


func _stop_leak() -> void:
	if particles:
		particles.emitting = false
	if sound:
		sound.stop()
	if light:
		var lt := create_tween()
		lt.tween_property(light, "light_energy", 0.0, 1.0)
		lt.tween_callback(func(): light.visible = false)
