extends Node
# Background music (2026-11-12). One piece at a time, cross-faded: "menu" outside battles, "battle"
# by day and "night" once the gates start to crumble. The battle piece is three loops of the same
# length playing in step (tools/make_music.py): the lute alone in the morning, the drums join at
# noon, the tune at dusk. A win or a loss fades the music out under a short fanfare or lament.
# Drawing and rules never read this node; it only listens to what the game tells it.
const DIR := "res://assets/music/"
const BUS := "Music"
const FADE := 1.6 # seconds for a full cross-fade
const LAYERS := ["battle_lute","battle_drums","battle_tune"]
const QUIET := -60.0

var enabled := true
var wanted := "" # the piece that should be heard now ("" = silence)
var duck := 1.0 # 0..1 extra gain (the pause screen lowers the music)
var players := {} # piece -> AudioStreamPlayer
var gain := {} # piece -> current 0..1
var layer_gain := [1.0,0.0,0.0]
var layer_target := [1.0,0.0,0.0]
var layers: AudioStreamSynchronized
var sting: AudioStreamPlayer

# The Music and SFX buses exist before any player is made, so volumes can be set separately.
static func ensure_buses() -> void:
	for bus: String in [BUS,"SFX"]:
		if AudioServer.get_bus_index(bus) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus)
		AudioServer.set_bus_send(index,"Master")

static func set_bus_volume(bus: String, share: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0: return
	AudioServer.set_bus_mute(index,share <= 0.001)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(share,0.001)))

func looped(piece: String) -> AudioStream:
	var path := DIR+piece+".ogg"
	if not ResourceLoader.exists(path): return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis: stream.loop = true
	return stream

func _ready() -> void:
	ensure_buses()
	for piece: String in ["menu","night"]:
		var stream := looped(piece)
		if stream != null: add_player(piece,stream)
	layers = AudioStreamSynchronized.new()
	layers.stream_count = LAYERS.size()
	var complete := true
	for i: int in range(LAYERS.size()):
		var stream := looped(LAYERS[i])
		if stream == null: complete = false
		else:
			layers.set_sync_stream(i,stream)
			layers.set_sync_stream_volume(i,0.0 if i == 0 else QUIET)
	if complete: add_player("battle",layers)
	sting = AudioStreamPlayer.new()
	sting.bus = BUS
	add_child(sting)

func add_player(piece: String, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = QUIET
	add_child(player)
	players[piece] = player
	gain[piece] = 0.0

# What should be playing: a piece name, and for the battle piece how far the day has come
# (0 morning .. 2 dusk).
func want(piece: String, day: int = 0) -> void:
	wanted = piece if players.has(piece) else ""
	for i: int in range(layer_target.size()): layer_target[i] = 1.0 if i <= day else 0.0

# A one-shot over the fading music: "victory" or "defeat".
func play_sting(piece: String) -> void:
	var path := DIR+piece+".ogg"
	if not enabled or not ResourceLoader.exists(path) or DisplayServer.get_name() == "headless": return
	sting.stream = load(path)
	sting.volume_db = -2.0
	sting.play()

func stop_sting() -> void:
	if sting != null and sting.playing: sting.stop()

func _process(dt: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var step := dt/FADE
	for piece: String in players:
		var player: AudioStreamPlayer = players[piece]
		var target := duck if enabled and piece == wanted else 0.0
		gain[piece] = move_toward(gain[piece],target,step)
		if gain[piece] <= 0.0:
			if player.playing: player.stop()
			continue
		if not player.playing:
			if piece == "battle": # a new battle starts from the lute alone
				layer_gain = [1.0,0.0,0.0]
				for i: int in range(LAYERS.size()): layers.set_sync_stream_volume(i,0.0 if i == 0 else QUIET)
			player.play()
		# Equal-power fade: two pieces crossing never dip or swell.
		player.volume_db = linear_to_db(maxf(sin(gain[piece]*PI*0.5),0.001))
	if players.has("battle") and players.battle.playing:
		for i: int in range(LAYERS.size()):
			layer_gain[i] = move_toward(layer_gain[i],layer_target[i],dt/3.0) # layers ease in over three seconds
			layers.set_sync_stream_volume(i,linear_to_db(maxf(layer_gain[i],0.001)))
