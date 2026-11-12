extends Node

const CUES := {
	"play":"bookFlip1",
	"ink":"dropLeather",
	"hoe":"chop",
	"cultivate":"chop",
	"hit":"sword_clash",
	"death":"dropLeather",
	"burn":"flame_burst",
	"spell":"bookPlace1",
	"breach":"warhorn",
	"arrow":"bow_shoot",
	"heal":"holy_heal",
	"overflow":"metalPot1",
	"finish":"metalPot1",
	"ramp":"warhorn",
	"invaded":"warhorn",
	"fail":"dropLeather",
	"skill":"horn",
	"catapult_fire":"creak1",
	"stone_impact":"stone_crash",
	"drum":"war_drum",
	"curse_rise":"dark_magic",
	"spear":"spear_thrust",
	"sword":"sword_clash",
	"shield":"shield_block",
	"boulder":"boulder_rumble",
	"axe":"throwing_axe",
	"lightning":"lightning",
	"ram":"ram_hit",
	"nightfall":"bell",
	"dawn":"bell",
	"ui_hover":"ui_tick",
	"ui_click":"ui_tock"
}

const COOLDOWNS := {
	"arrow": 180,
	"spear": 150,
	"axe": 160,
	"sword": 130,
	"shield": 140,
	"hit": 120,
	"boulder": 300,
	"lightning": 150,
	"drum": 150,
	"ui_hover": 45,
	"ui_click": 45
}

const VOLUMES := {
	"arrow": -10.0,
	"axe": -7.0,
	"spear": -6.0,
	"sword": -6.0,
	"shield": -5.0,
	"hit": -6.0,
	"ram": -3.0,
	"drum": 2.0,
	"skill": 1.5,
	"breach": 2.0,
	"boulder": 1.0,
	"nightfall": 3.0,
	"dawn": 3.0,
	"ui_hover": -9.0,
	"ui_click": -3.0
}

var enabled := true
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var last: Dictionary = {}
var cursor := 0

func _ready() -> void:
	for name: String in CUES.values():
		if not streams.has(name):
			var path := "res://assets/audio/" + name + ".ogg"
			if ResourceLoader.exists(path):
				streams[name] = load(path)
	for i: int in range(12):
		var player := AudioStreamPlayer.new()
		player.volume_db = -11.0
		if AudioServer.get_bus_index("SFX") >= 0: player.bus = "SFX"
		add_child(player)
		players.append(player)

func cue(kind: String) -> void:
	if not enabled or not CUES.has(kind) or DisplayServer.get_name() == "headless": return
	var now := Time.get_ticks_msec()
	var cd: int = COOLDOWNS.get(kind, 60)
	if now - int(last.get(kind, -1000)) < cd: return
	last[kind] = now
	var player := players[cursor]
	cursor = (cursor + 1) % players.size()
	player.volume_db = -11.0 + VOLUMES.get(kind, 0.0)
	player.stream = streams.get(CUES[kind])
	if player.stream != null:
		player.play()

func cue_event(e: Dictionary) -> void:
	if not enabled or DisplayServer.get_name() == "headless": return
	var k: String = e.get("kind", "")
	if k == "spell":
		var card: String = e.get("card", "")
		if card == "charge_horn": cue("skill")
		elif card == "chain_lightning": cue("lightning")
		elif card == "rolling_boulder": cue("boulder")
		elif card == "fire": cue("burn")
		elif card in ["curse", "plague"]: cue("curse_rise")
		elif card == "harvest": cue("heal")
		else: cue("spell")
	elif k == "hit":
		var attacker: String = e.get("attacker", "")
		var target: String = e.get("target", "")
		if target == "shieldguard":
			cue("shield")
		elif attacker == "spearbow":
			cue("spear")
		elif attacker == "axe_thrower":
			cue("axe")
		elif attacker == "ram":
			cue("ram")
		elif attacker in ["knight", "guard", "bandit", "militia", "adventure"]:
			cue("sword")
		else:
			cue("hit")
	elif k == "arrow":
		cue("arrow")
	elif k == "drum":
		cue("drum")
	elif k == "link" and e.get("style", "") == "lightning":
		cue("lightning")
	elif k == "skill":
		var lord: String = e.get("lord", "")
		if lord == "lion":
			cue("skill")
		elif lord == "adventure":
			cue("sword")
		elif lord in ["underworld", "vampire"]:
			cue("curse_rise")
		else:
			cue("skill")
	else:
		cue(k)

