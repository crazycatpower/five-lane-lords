extends Node
# Background music (2026-11-12; themes, tension and seasons 2026-11-22). One piece at a time,
# cross-faded: "menu" outside battles, a battle theme by day and "night" once the gates start to crumble.
# Each battle theme (one per enemy faction: normal, magic, dark, beast) is four loops of the same length
# playing in step (tools/make_music.py): the lute alone in the morning, the drums join at noon, the
# tune at dusk, and the tension layer whenever the battle turns dangerous or decisive (music_mood.gd).
# The season colours the music bus (winter muffled and cavernous, autumn mellow, spring airy).
# A win or a loss fades the music out under a short fanfare or lament.
# Drawing and rules never read this node; it only listens to what the game tells it.
const DIR := "res://assets/music/"
const BUS := "Music"
const FADE := 1.6 # seconds for a full cross-fade
const FADE_SILENCE := 0.55 # quicker fade out when a match ends for victory/defeat stings
const STING_FADE := 0.30
const THEMES := ["normal","magic","dark","beast","conveyor","charge","duel","crimson"]
const LAYERS := ["lute","drums","tune","tension"]
const TENSION_RISE := 1.2 # seconds for the tension layer to come in fully
const TENSION_FALL := 7.0 # and to leave again once things calm down
const QUIET := -60.0
# Season colouring of the music bus: [low-pass cutoff Hz (0 = open), reverb wet 0..1, reverb room size].
const SEASON_TONE := {"":[0.0,0.0,0.3],"spring":[0.0,0.07,0.45],"summer":[0.0,0.0,0.3],"autumn":[7200.0,0.09,0.55],"winter":[4600.0,0.2,0.85]}

var enabled := true
var wanted := "" # the piece that should be heard now ("" = silence)
var duck := 1.0 # 0..1 extra gain (the pause screen lowers the music)
var pause_duck := 1.0
var event_duck := 1.0 # brief dip for dramatic skills / breaches
var event_duck_hold := 0.0
var event_duck_target := 1.0
var sting_fade_left := 0.0
var players := {} # piece -> AudioStreamPlayer ("menu", "night", "battle:<theme>")
var gain := {} # piece -> current 0..1
var layer_gain := [1.0,0.88,0.85,0.0]
var layer_target := [1.0,0.88,0.85,0.0]
var day := 0
var tension := 0.0 # wanted 0..1
var tension_now := 0.0 # eased
var layers := {} # theme -> AudioStreamSynchronized
var sting: AudioStreamPlayer
var season := ""
var lowpass: AudioEffectLowPassFilter
var reverb: AudioEffectReverb

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
	sting = AudioStreamPlayer.new()
	sting.bus = BUS
	add_child(sting)
	setup_season_effects()

# A theme's four loops are loaded the first time a battle asks for it.
func battle_player(theme: String) -> String:
	if not theme in THEMES: theme = "normal"
	var key := "battle:"+theme
	if players.has(key): return key
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = LAYERS.size()
	for i: int in range(LAYERS.size()):
		var stream := looped("battle_%s_%s" % [theme,LAYERS[i]])
		if stream == null: return "" if theme == "normal" else battle_player("normal")
		sync.set_sync_stream(i,stream)
		sync.set_sync_stream_volume(i,0.0 if i == 0 else QUIET)
	layers[theme] = sync
	add_player(key,sync)
	return key

func add_player(piece: String, stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = QUIET
	add_child(player)
	players[piece] = player
	gain[piece] = 0.0

# What should be playing: a piece name ("menu", "night", "battle" or ""), for the battle how far the
# day has come (0 morning .. 2 dusk) and whose theme it is.
func want(piece: String, day_phase: int = 0, theme: String = "normal") -> void:
	if piece == "battle": piece = battle_player(theme)
	wanted = piece if players.has(piece) else ""
	day = day_phase

# 0..1 from music_mood.gd; outside battles it falls back to calm.
func set_tension(value: float) -> void:
	tension = clampf(value,0.0,1.0)

func setup_season_effects() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0 or DisplayServer.get_name() == "headless": return
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000.0
	reverb = AudioEffectReverb.new()
	reverb.wet = 0.0
	reverb.dry = 1.0
	reverb.damping = 0.6
	AudioServer.add_bus_effect(bus,lowpass)
	AudioServer.add_bus_effect(bus,reverb)
	apply_season()

func set_season(value: String) -> void:
	if value == season: return
	season = value if SEASON_TONE.has(value) else ""
	apply_season()

func apply_season() -> void:
	if lowpass == null: return
	var tone: Array = SEASON_TONE[season]
	var bus := AudioServer.get_bus_index(BUS)
	lowpass.cutoff_hz = float(tone[0]) if float(tone[0]) > 0.0 else 20000.0
	reverb.wet = float(tone[1])
	reverb.room_size = float(tone[2])
	for i: int in range(AudioServer.get_bus_effect_count(bus)):
		var fx := AudioServer.get_bus_effect(bus,i)
		if fx == lowpass: AudioServer.set_bus_effect_enabled(bus,i,float(tone[0]) > 0.0)
		elif fx == reverb: AudioServer.set_bus_effect_enabled(bus,i,float(tone[1]) > 0.0)

# A one-shot over the fading music: "victory" or "defeat".
func play_sting(piece: String) -> void:
	var path := DIR+piece+".ogg"
	if not enabled or not ResourceLoader.exists(path) or DisplayServer.get_name() == "headless": return
	sting_fade_left = 0.0
	sting.stream = load(path)
	sting.volume_db = -2.0
	sting.play()

func stop_sting() -> void:
	if sting != null and sting.playing and sting_fade_left <= 0.0:
		sting_fade_left = STING_FADE

func duck_pulse(level: float = 0.5, duration: float = 0.55) -> void:
	event_duck_target = minf(event_duck_target, clampf(level, 0.15, 1.0))
	event_duck_hold = maxf(event_duck_hold, duration)

func _process(dt: float) -> void:
	if DisplayServer.get_name() == "headless": return
	if sting != null and sting.playing and sting_fade_left > 0.0:
		sting_fade_left = maxf(0.0, sting_fade_left - dt)
		var sk := sting_fade_left / STING_FADE
		sting.volume_db = lerpf(QUIET, -2.0, sk * sk)
		if sting_fade_left <= 0.0:
			sting.stop()
	pause_duck = move_toward(pause_duck, duck, dt * 3.2)
	if event_duck_hold > 0.0:
		event_duck_hold = maxf(0.0, event_duck_hold - dt)
		event_duck = move_toward(event_duck, event_duck_target, dt * 8.0)
	else:
		event_duck_target = 1.0
		event_duck = move_toward(event_duck, 1.0, dt * 1.8)
	var fade_time := FADE_SILENCE if wanted.is_empty() else FADE
	var step := dt/fade_time
	for piece: String in players:
		var player: AudioStreamPlayer = players[piece]
		var target := 1.0 if enabled and piece == wanted else 0.0
		gain[piece] = move_toward(gain[piece],target,step)
		if gain[piece] <= 0.0:
			if player.playing: player.stop()
			continue
		if not player.playing:
			if piece.begins_with("battle:"): # every battle opens with full rhythm and lead melody
				layer_gain = [1.0,0.88,0.85,0.0]
				tension_now = 0.0
				var sync: AudioStreamSynchronized = layers[piece.get_slice(":",1)]
				for i: int in range(LAYERS.size()): sync.set_sync_stream_volume(i,linear_to_db(maxf(sin(layer_gain[i]*PI*0.5),0.001)))
			player.play()
		# Equal-power fade: two pieces crossing never dip or swell, while pause/event ducking stays responsive.
		var cross := sin(gain[piece]*PI*0.5)
		player.volume_db = linear_to_db(maxf(cross * pause_duck * event_duck, 0.001))
	if not wanted.begins_with("battle:"): return
	var playing: AudioStreamPlayer = players[wanted]
	if not playing.playing: return
	tension_now = move_toward(tension_now,tension,dt/(TENSION_RISE if tension > tension_now else TENSION_FALL))
	var t := smoothstep(0.2,0.8,tension_now)
	layer_target = [1.0,1.0 if day >= 1 or t > 0.2 else 0.88,1.0 if day >= 1 or t > 0.25 else 0.85,maxf(t,0.35 if day >= 2 else 0.0)]
	var sync: AudioStreamSynchronized = layers[wanted.get_slice(":",1)]
	for i: int in range(LAYERS.size()):
		layer_gain[i] = move_toward(layer_gain[i],layer_target[i],dt/(1.0 if i == 3 else 3.0)) # layers ease in over three seconds
		sync.set_sync_stream_volume(i,linear_to_db(maxf(sin(layer_gain[i]*PI*0.5),0.001)))
