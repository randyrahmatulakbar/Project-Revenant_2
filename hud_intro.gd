extends CanvasLayer
## HUD awal: cuma tangan kosong + crosshair.
## Punya fungsi update_weapon_animation() yang sama dengan hud.gd,
## jadi dipanggil dari hud.gd selama mode intro.

@onready var fist: AnimatedSprite2D = $FirstPersonFist


func _ready() -> void:
	fist.play("idle")


func update_weapon_animation(is_moving: bool, is_sprinting: bool) -> void:
	var anim := "idle"
	if is_moving:
		anim = "sprint" if is_sprinting else "walk"
	if fist.animation != anim or not fist.is_playing():
		fist.play(anim)
