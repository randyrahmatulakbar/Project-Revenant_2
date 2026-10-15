extends Panel
## Pasang di node "CreditPanel" (klik CreditPanel -> Attach Script).
## - Tombol Back dipindah ke pojok kanan atas.
## - Jarak antara judul "CREDITS" dan "PROJECT REVENANT" dirapatkan.

## Jarak tombol Back dari tepi kanan dan atas layar (px)
@export var back_margin_right: float = 64.0
@export var back_margin_top: float = 22.0

## Jarak antara garis di bawah "CREDITS" dan baris "PROJECT REVENANT" (px).
## Sebelumnya 80. Kecilin lagi kalau masih kejauhan.
@export var content_top_margin: int = 18

@onready var back: Control = get_node_or_null("Back")
@onready var margin: MarginContainer = get_node_or_null("CreditViewport/MarginContainer")


func _ready() -> void:
	if margin:
		margin.add_theme_constant_override("margin_top", content_top_margin)

	_place_back()
	# script lain bisa saja menaruh ulang tombol pas panel dibuka, jadi taruh lagi
	visibility_changed.connect(func(): call_deferred("_place_back"))


func _place_back() -> void:
	if back == null:
		return
	# nempel di pojok kanan atas, ukuran tombol dibiarkan seperti sekarang
	var w := maxf(back.size.x, back.custom_minimum_size.x)
	var h := maxf(back.size.y, back.custom_minimum_size.y)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	back.grow_vertical = Control.GROW_DIRECTION_END
	back.offset_right = -back_margin_right
	back.offset_left = -back_margin_right - w
	back.offset_top = back_margin_top
	back.offset_bottom = back_margin_top + h
