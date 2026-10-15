extends CanvasLayer
## HUD awal: cuma tangan kosong + crosshair.
## Punya fungsi update_weapon_animation() yang sama dengan hud.gd,
## jadi dipanggil dari hud.gd selama mode intro.

const LightTint := preload("res://hud_light_tint.gd")

## Dasar frame tangan (tempat lengan "kepotong") ditaruh sekian px DI BAWAH
## tepi layar, jadi potongan lengan gak pernah kelihatan. Gedein kalau masih keliatan.
@export var bottom_margin := 24.0

@onready var fist: AnimatedSprite2D = $FirstPersonFist


func _ready() -> void:
	fist.play("idle")
	# tangan ikut gelap/terang sesuai cahaya di sekitar player
	var tint = LightTint.new()
	tint.target = fist
	add_child(tint)

	_fit_to_bottom()
	get_viewport().size_changed.connect(_fit_to_bottom)


# Semua frame tangan dipotong rata di dasar frame, jadi dasar frame
# dipaksa selalu ada di bawah layar (berapapun ukuran window).
func _fit_to_bottom() -> void:
	if fist.sprite_frames == null:
		return
	var tex := fist.sprite_frames.get_frame_texture("idle", 0)
	if tex == null:
		return
	var half_h := tex.get_height() * fist.scale.y * 0.5
	var screen_h := get_viewport().get_visible_rect().size.y
	fist.position.y = screen_h - half_h + bottom_margin


func update_weapon_animation(is_moving: bool, is_sprinting: bool) -> void:
	var anim := "idle"
	if is_moving:
		anim = "sprint" if is_sprinting else "walk"
	if fist.animation != anim or not fist.is_playing():
		fist.play(anim)
