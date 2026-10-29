class_name MenuBtn
extends Control
## Tombol menu miring ala terminal (gambar sendiri lewat _draw).

signal pressed

@export var title := "BUTTON"
@export var subtitle := ""
@export var accent := Color(0.36, 0.52, 0.55)
@export var fill := Color(0.06, 0.1, 0.11, 0.8)
@export var text_color := Color(0.93, 0.93, 0.93)
@export var big := false
@export var disabled := false

var font: Font
var _hover := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _on_enter() -> void:
	_hover = true
	queue_redraw()


func _on_exit() -> void:
	_hover = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		pressed.emit()
		accept_event()


func _draw() -> void:
	var sub_h := 16.0 if subtitle != "" else 0.0
	var h := size.y - sub_h
	var sk := h * 0.32
	var pts := PackedVector2Array([Vector2(sk, 0), Vector2(size.x, 0), Vector2(size.x - sk, h), Vector2(0, h)])
	var hot := (_hover or has_focus()) and not disabled
	var f_col := fill.lightened(0.14) if hot else fill
	var b_col := accent.lightened(0.3) if hot else accent
	if disabled:
		f_col.a *= 0.6
		b_col = b_col.darkened(0.4)
	draw_colored_polygon(pts, f_col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), b_col, 2.0 if big else 1.4)
	var fnt: Font = font if font else ThemeDB.fallback_font
	var fs := 34 if big else 17
	var tc := text_color if not disabled else text_color.darkened(0.45)
	draw_string(fnt, Vector2(sk + 16, h * 0.5 + fs * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	draw_string(fnt, Vector2(size.x - sk - 48, h * 0.5 + fs * 0.3), "///", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.7), b_col)
	if subtitle != "":
		draw_string(fnt, Vector2(sk * 0.4 + 6, size.y - 3), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.72, 0.74, 0.85))
