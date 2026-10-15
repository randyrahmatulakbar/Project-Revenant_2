extends CanvasLayer
## Judul game 2 baris (gaya main menu), muncul LANGSUNG tanpa animasi saat pistol diambil.
## Begitu judul hilang, crosshair HUD baru dimunculkan.

@export var pickup_path: NodePath = ^"../PistolPickup"
@export var line1_text := "PROJECT"
@export var line2_text := "REVENANT"
@export var line1_color := Color("eadccf")
@export var line2_color := Color("650005")
@export var font: Font
@export var font_size := 96               # ukuran baris 1
@export var line2_scale := 1.57           # baris 2 sekian kali lebih besar
@export var line2_offset := 2.35          # geser baris 2 ke kanan (x tinggi huruf baris 1)
@export var line_gap := 0.62              # jarak antar baris (x tinggi huruf baris 1)
@export var cap_ratio := 0.7              # tinggi huruf kapital / ukuran font
@export var vertical_pos := 0.5           # 0.5 = blok judul tepat di tengah layar
@export var show_delay := 0.0
@export var hold_time := 3.0              # lama tampil (detik), 0 = tampil terus

var _l1: Label
var _l2: Label
var _showing := false
var _tween: Tween


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS   # supaya bisa disembunyiin saat pause
	_l1 = _make_label(line1_color)
	_l2 = _make_label(line2_color)
	var pickup := get_node_or_null(pickup_path)
	if pickup and pickup.has_signal("picked_up"):
		pickup.picked_up.connect(_on_picked_up)
	else:
		push_warning("TitleCard: PistolPickup atau sinyal picked_up tidak ketemu")


func _process(_delta: float) -> void:
	var on := _showing and not get_tree().paused
	_l1.visible = on
	_l2.visible = on


func _make_label(color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.visible = false
	add_child(l)
	return l


func _layout() -> void:
	var f: Font = font if font else ThemeDB.fallback_font
	var s1 := font_size
	var s2 := int(round(font_size * line2_scale))
	_l1.text = line1_text
	_l2.text = line2_text
	_l1.add_theme_font_size_override("font_size", s1)
	_l2.add_theme_font_size_override("font_size", s2)

	var cap1 := s1 * cap_ratio
	var cap2 := s2 * cap_ratio
	var w1 := f.get_string_size(line1_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x
	var w2 := f.get_string_size(line2_text, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x
	var off := line2_offset * cap1
	var gap := line_gap * cap1

	var block_w := maxf(w1, off + w2)
	var block_h := cap1 + gap + cap2
	var screen := get_viewport().get_visible_rect().size
	var left := screen.x * 0.5 - block_w * 0.5
	var top := screen.y * vertical_pos - block_h * 0.5

	var base1 := top + cap1
	var base2 := top + cap1 + gap + cap2
	_l1.position = Vector2(left, base1 - f.get_ascent(s1))
	_l2.position = Vector2(left + off, base2 - f.get_ascent(s2))


func _on_picked_up() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)   # hitungan berhenti saat pause
	if show_delay > 0.0:
		_tween.tween_interval(show_delay)
	_tween.tween_callback(_show)
	if hold_time > 0.0:
		_tween.tween_interval(hold_time)
		_tween.tween_callback(_hide_title)


func _show() -> void:
	_layout()
	_showing = true
	if hold_time <= 0.0:
		get_tree().call_group("hud", "show_crosshair")


func _hide_title() -> void:
	_showing = false
	get_tree().call_group("hud", "show_crosshair")
