extends Node
## Racun yang menempel di player: kurangi Health tiap 0.4 detik sampai waktunya habis.
## Dipasang otomatis sebagai anak player lewat PoisonDot.apply(...)

var dps: float = 3.0
var time_left: float = 3.0
var _tick: float = 0.0
var _health: Node


func _ready() -> void:
	_health = get_parent().get_node_or_null("Health")


func _process(delta: float) -> void:
	time_left -= delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.4
		if _health:
			_health.take_damage(dps * 0.4)
	if time_left <= 0.0:
		queue_free()


static func apply(target: Node, dps_value: float, time_value: float) -> void:
	var d := target.get_node_or_null("PoisonDot")
	if d == null:
		d = load("res://poison_dot.gd").new()
		d.name = "PoisonDot"
		target.add_child(d)
	d.dps = maxf(d.dps, dps_value)
	d.time_left = maxf(d.time_left, time_value)
