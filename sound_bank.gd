extends Node
const B = preload("res://balance.gd")

const CUES := {
	"play": "bookFlip1",
	"build": "doorClose_1",
	"ink": "handleCoins",
	"hoe": "chop",
	"cultivate": "chop",
	"hit": "sword_clash",
	"heavy_hit": "heavy_punch",
	"arrow_hit": "arrow_hit",
	"axe_hit": "axe_chop",
	"slash": "knifeSlice",
	"hero_slash": "knifeSlice",
	"wall_hit": "stone_hit",
	"death": "dropLeather",
	"burn": "flame_burst",
	"spell": "bookPlace1",
	"breach": "warhorn",
	"arrow": "bow_shoot",
	"heal": "heal_chime",
	"holy_heal": "holy_heal",
	"overflow": "metalPot1",
	"finish": "metalPot1",
	"ramp": "warhorn",
	"invaded": "warhorn",
	"fail": "dropLeather",
	"skill": "horn",
	"roar": "horn",
	"catapult_fire": "creak1",
	"nest_windup": "creak1",
	"nest_bite": "ram_hit",
	"stone_impact": "stone_crash",
	"trap_blast": "flame_burst",
	"boneburst": "stone_crash",
	"drum": "war_drum",
	"curse_rise": "dark_magic",
	"arcane_impact": "lightning",
	"teleport": "dark_magic",
	"rune_summon": "dark_magic",
	"soul_absorb": "dark_magic",
	"blood_transfer": "dark_magic",
	"spear": "spear_thrust",
	"sword": "sword_clash",
	"shield": "shield_block",
	"boulder": "boulder_rumble",
	"axe": "throwing_axe",
	"lightning": "lightning",
	"ram": "ram_hit",
	"charge_impact": "ram_hit",
	"charge_ready": "drawKnife1",
	"stealth_ready": "drawKnife1",
	"support_pulse": "heal_chime",
	"repair": "stone_hit",
	"blood_gain": "dark_magic",
	"summoned": "dark_magic",
	"nightfall": "bell",
	"dawn": "bell",
	"ui_hover": "ui_tick",
	"ui_click": "ui_tock",
	"page_turn": "bookFlip1",
	"pause": "doorClose_1",
	"card_ready": "ui_tick",
	"skill_ready": "holy_heal",
}

const HIGH_PRIORITY := {
	"breach": true, "skill": true, "hero_slash": true, "nightfall": true,
	"dawn": true, "ramp": true, "invaded": true, "boulder": true,
	"finish": true, "ui_click": true, "fail": true, "skill_ready": true,
	"pause": true, "roar": true, "page_turn": true,
}

const COOLDOWNS := {
	"nest_windup": 250,
	"nest_bite": 200,
	"ink": 180,
	"arrow": 170,
	"arrow_hit": 160,
	"spear": 150,
	"axe": 160,
	"axe_hit": 150,
	"sword": 130,
	"slash": 140,
	"heavy_hit": 140,
	"shield": 140,
	"wall_hit": 160,
	"hit": 120,
	"heal": 420,
	"holy_heal": 360,
	"repair": 380,
	"boulder": 300,
	"lightning": 150,
	"arcane_impact": 180,
	"teleport": 180,
	"drum": 150,
	"charge_impact": 220,
	"charge_ready": 300,
	"stealth_ready": 350,
	"support_pulse": 800,
	"blood_gain": 400,
	"summoned": 200,
	"ui_hover": 45,
	"ui_click": 45,
	"page_turn": 70,
	"card_ready": 240,
	"skill_ready": 500,
}

const VOLUMES := {
	"ink": -10.5,
	"build": -4.0,
	"nest_windup": -9.0,
	"nest_bite": -6.0,
	"arrow": -10.0,
	"arrow_hit": -8.0,
	"axe": -7.0,
	"axe_hit": -5.5,
	"spear": -6.0,
	"sword": -6.0,
	"slash": -6.0,
	"hero_slash": 0.5,
	"heavy_hit": -3.5,
	"shield": -5.0,
	"wall_hit": -7.5,
	"repair": -8.5,
	"hit": -6.0,
	"heal": -5.5,
	"holy_heal": -4.0,
	"ram": -3.0,
	"drum": 2.0,
	"charge_impact": -3.0,
	"charge_ready": -10.0,
	"stealth_ready": -10.5,
	"support_pulse": -13.5,
	"blood_gain": -9.0,
	"summoned": -9.0,
	"arcane_impact": -6.5,
	"teleport": -7.5,
	"rune_summon": -8.0,
	"soul_absorb": -9.0,
	"blood_transfer": -9.5,
	"trap_blast": -2.0,
	"boneburst": -3.5,
	"skill": 1.5,
	"roar": 0.5,
	"breach": 2.0,
	"boulder": 1.0,
	"nightfall": 3.0,
	"dawn": 3.0,
	"ui_hover": -9.0,
	"ui_click": -3.0,
	"page_turn": -7.0,
	"pause": -8.5,
	"card_ready": -11.0,
	"skill_ready": -6.5,
}

const PITCHES := {
	"roar": 0.76,
	"hero_slash": 0.86,
	"boneburst": 0.88,
	"teleport": 1.28,
	"arcane_impact": 1.18,
	"soul_absorb": 1.12,
	"blood_transfer": 1.10,
	"page_turn": 1.08,
	"pause": 1.14,
	"skill_ready": 1.14,
	"card_ready": 1.24,
	"stealth_ready": 1.18,
}

const JITTER := {
	"hit": 0.08,
	"sword": 0.08,
	"spear": 0.07,
	"axe": 0.07,
	"axe_hit": 0.07,
	"slash": 0.07,
	"heavy_hit": 0.06,
	"shield": 0.07,
	"wall_hit": 0.07,
	"arrow": 0.06,
	"arrow_hit": 0.07,
	"ink": 0.06,
	"hoe": 0.07,
	"cultivate": 0.07,
	"death": 0.06,
	"summoned": 0.05,
	"arcane_impact": 0.06,
	"ui_hover": 0.025,
	"ui_click": 0.02,
	"page_turn": 0.03,
	"breach": 0.015,
	"nightfall": 0.01,
	"dawn": 0.01,
}

var enabled := true
var players: Array[AudioStreamPlayer] = []
var priority_players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var last: Dictionary = {}
var cursor := 0
var priority_cursor := 0
var _sfx_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_sfx_rng.randomize()
	for name: String in CUES.values():
		if not streams.has(name):
			var path := "res://assets/audio/" + name + ".ogg"
			if ResourceLoader.exists(path):
				streams[name] = load(path)
	for i: int in range(14):
		players.append(_make_player())
	for i: int in range(4):
		priority_players.append(_make_player())

func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = -11.0
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	add_child(player)
	return player

func _pick_player(high: bool) -> AudioStreamPlayer:
	var pool: Array[AudioStreamPlayer] = priority_players if high else players
	if pool.is_empty():
		return null
	var start: int = priority_cursor if high else cursor
	var chosen: AudioStreamPlayer = pool[start]
	var chosen_idx: int = start
	for offset: int in range(pool.size()):
		var idx: int = (start + offset) % pool.size()
		if not pool[idx].playing:
			chosen = pool[idx]
			chosen_idx = idx
			break
	if high:
		priority_cursor = (chosen_idx + 1) % pool.size()
	else:
		cursor = (chosen_idx + 1) % pool.size()
	return chosen

func cue(kind: String) -> void:
	if not enabled or not CUES.has(kind) or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec()
	var cd: int = COOLDOWNS.get(kind, 60)
	if now - int(last.get(kind, -1000)) < cd:
		return
	last[kind] = now
	var stream: AudioStream = streams.get(CUES[kind])
	if stream == null:
		return
	var player := _pick_player(HIGH_PRIORITY.has(kind))
	if player == null:
		return
	player.volume_db = -11.0 + float(VOLUMES.get(kind, 0.0))
	var base_pitch: float = float(PITCHES.get(kind, 1.0))
	var jit: float = float(JITTER.get(kind, 0.0))
	player.pitch_scale = clampf(base_pitch + (_sfx_rng.randf_range(-jit, jit) if jit > 0.0 else 0.0), 0.55, 1.75)
	player.stream = stream
	player.play()

func cue_event(e: Dictionary) -> void:
	if not enabled or e.get("silent", false) or DisplayServer.get_name() == "headless":
		return
	var k: String = e.get("kind", "")
	if k == "play":
		var card: String = e.get("card", "")
		if B.CARDS.get(card, {}).get("type", "") == "building":
			cue("build")
		else:
			cue("play")
	elif k == "spell":
		var card: String = e.get("card", "")
		if card in ["charge_horn", "wing_gust", "pack_ambush", "counter_charge"]: cue("skill")
		elif card in ["chain_lightning", "mana_drain"]: cue("lightning")
		elif card == "rolling_boulder": cue("boulder")
		elif card in ["fire", "flaming_pitch"]: cue("burn")
		elif card in ["harvest", "arcane_shield", "mana_spring"]: cue("holy_heal")
		elif card == "dread_howl": cue("roar")
		elif card in ["phase_shift", "mirror_clone", "time_field"]: cue("teleport")
		elif card in ["curse", "plague", "gravity_well", "corrosive_bile", "sealed_coffin", "devouring_maw"]: cue("curse_rise")
		elif card in ["feral_mutation", "berserk_blood"]: cue("heal")
		elif card in ["swarm_eruption", "borrowed_bones", "grave_exchange", "levy"]: cue("summoned")
		else: cue("spell")
	elif k == "hit":
		var attacker: String = e.get("attacker", "")
		var target: String = e.get("target", "")
		if target in ["shieldguard", "barricade", "bonewall"]:
			cue("shield")
		elif B.CARDS.get(target, {}).get("type", "") == "building":
			cue("wall_hit")
		elif attacker in ["corpse_giant", "arcane_golem", "bog_troll", "thorn_dragon", "dire_hydra", "tusk_boar", "gold_monster", "thorn_mother", "lord_iron", "lord_beast", "lord_lion", "lord_vampire"]:
			cue("heavy_hit")
		elif attacker in ["hunter", "arcane_archer", "tower", "watchtower", "shroud_arbalist", "vampire_hunter", "ballista_tower"]:
			cue("arrow_hit")
		elif attacker in ["axe_thrower", "macebreaker", "halberdier"]:
			cue("axe_hit")
		elif attacker in ["assassin", "blink_blade", "reaper", "disgraced_lancer"]:
			cue("slash")
		elif attacker == "spearbow":
			cue("spear")
		elif attacker == "ram":
			cue("ram")
		elif attacker in ["knight", "guard", "bandit", "militia", "adventure"]:
			cue("sword")
		else:
			cue("hit")
	elif k == "link":
		match e.get("style", ""):
			"lightning": cue("lightning")
			"heal", "repair": cue("support_pulse")
			"soul", "devour", "curse": cue("blood_gain")
			"summon": cue("summoned")
			"harvest", "mana": cue("heal")
	elif k == "skill":
		var lord: String = e.get("lord", "")
		if lord == "adventure":
			cue("hero_slash")
		elif lord == "harvest":
			cue("holy_heal")
		elif lord == "beast":
			cue("roar")
		elif lord in ["mage", "rune"]:
			cue("lightning")
		elif lord in ["underworld", "vampire"]:
			cue("curse_rise")
		else:
			cue("skill")
	else:
		cue(k)
