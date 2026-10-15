extends Node
## AUTOLOAD (nama: UiSound). Suara hover + klik otomatis untuk SEMUA tombol, checkbox,
## dan slider di game (main menu, settings, credit, pause) tanpa perlu edit tombolnya satu-satu.
## Tetap bunyi saat game di-pause dan tidak terputus saat pindah scene.

const CLICK_PATH := "res://sfx/click.mp3" 
const CLICK_DB := -4.0
const HOVER_DB := -16.0
const HOVER_PITCH := 1.4
const HOVER_SOUND := true                   # false = tanpa suara hover
const BUS := "SFX"

var _click_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stream: AudioStream = null
	if ResourceLoader.exists(CLICK_PATH):
		stream = load(CLICK_PATH)
	else:
		push_warning("UiSound: file tidak ditemukan di %s" % CLICK_PATH)

	_click_player = _make_player(stream, CLICK_DB, 1.0)
	_hover_player = _make_player(stream, HOVER_DB, HOVER_PITCH)

	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)


func _make_player(stream: AudioStream, db: float, pitch: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	return p


func _scan(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_scan(c)


func _on_node_added(n: Node) -> void:
	if n.has_meta("ui_sound"):
		return
	if n is BaseButton:
		n.set_meta("ui_sound", true)
		n.pressed.connect(_play.bind(_click_player))
		if HOVER_SOUND:
			n.mouse_entered.connect(_on_hover.bind(n))
	elif n is Slider:
		n.set_meta("ui_sound", true)
		n.drag_ended.connect(func(_changed: bool): _play(_click_player))


func _on_hover(b: BaseButton) -> void:
	if not b.disabled:
		_play(_hover_player)


func _play(p: AudioStreamPlayer) -> void:
	if p.stream == null:
		return
	p.bus = BUS if AudioServer.get_bus_index(BUS) != -1 else "Master"
	p.play()
