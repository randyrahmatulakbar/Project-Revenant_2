extends OmniLight3D
## Lampu pabrik yang berkedip: kadang redup sebentar.

@export var flicker_chance := 0.3
@export var min_factor := 0.15

var _base := 1.0
var _t := 0.0
var _next := 1.0


func _ready() -> void:
	_base = light_energy
	_next = randf_range(0.5, 3.0)


func _process(delta: float) -> void:
	_t += delta
	if _t < _next:
		return
	_t = 0.0
	_next = randf_range(0.8, 4.0)
	if randf() < flicker_chance:
		var tw := create_tween()
		for i in randi_range(2, 5):
			tw.tween_property(self, "light_energy", _base * randf_range(min_factor, 0.7), 0.04)
			tw.tween_property(self, "light_energy", _base, 0.05)
