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
	"collapse": "stone_crash",
	"witch_curse": "dark_magic",
	"big_death": "heavy_punch",
	"bolt_shot": "bow_shoot",
	"gun_shot": "musket",
	"magic_shot": "dark_magic",
	"dark_shot": "dark_magic",
}

const HIGH_PRIORITY := {
	"breach": true, "skill": true, "hero_slash": true, "nightfall": true,
	"dawn": true, "ramp": true, "invaded": true, "boulder": true,
	"finish": true, "ui_click": true, "fail": true, "skill_ready": true,
	"pause": true, "roar": true, "page_turn": true, "collapse": true,
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
	"collapse": 200,
	"witch_curse": 250,
	"big_death": 250,
	"bolt_shot": 180,
	"gun_shot": 140,
	"magic_shot": 200,
	"dark_shot": 220,
}

const VOLUMES := {
	"ink": -10.5,
	"build": -4.0,
	"nest_windup": -9.0,
	"nest_bite": -6.0,
	"arrow": -2.5, # bow_shoot.ogg peaks at -13 dB: shots sat 15 dB under the melee hits
	"arrow_hit": -1.0,
	"axe": -7.0,
	"axe_hit": -5.5,
	"spear": 2.0, # spear_thrust.ogg peaks at -13 dB
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
	"charge_ready": 8.0, # drawKnife1.ogg peaks at -24 dB: inaudible before
	"stealth_ready": 7.5,
	"support_pulse": -13.5,
	"blood_gain": -9.0,
	"summoned": -9.0,
	"arcane_impact": -6.5,
	"teleport": -7.5,
	"rune_summon": -8.0,
	"soul_absorb": -9.0,
	"blood_transfer": -9.5,
	"trap_blast": -2.0,
	"boneburst": 8.0, # stone_crash.ogg peaks at -15 dB
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
	"stone_impact": 11.0, # catapult shells: stone_crash.ogg peaks at -15 dB
	"collapse": 9.0,
	"witch_curse": -8.0,
	"big_death": -4.0,
	"death": -3.0,
	"play": 2.0, # bookFlip1.ogg is long and soft (mean -30 dB)
	"bolt_shot": 1.0,
	"gun_shot": -9.0,
	"magic_shot": -12.0,
	"dark_shot": -13.0,
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
	"collapse": 0.78,
	"big_death": 0.72,
	"witch_curse": 0.9,
	"bolt_shot": 0.78,
	"gun_shot": 1.0,
	"magic_shot": 1.45,
	"dark_shot": 0.85,
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
	"collapse": 0.05,
	"big_death": 0.06,
	"stone_impact": 0.06,
	"burn": 0.05,
	"play": 0.03,
	"build": 0.04,
	"bolt_shot": 0.05,
	"gun_shot": 0.08,
	"magic_shot": 0.08,
	"dark_shot": 0.06,
}

var enabled := true
var players: Array[AudioStreamPlayer] = []
var priority_players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var last: Dictionary = {}
var cursor := 0
var priority_cursor := 0
var _sfx_rng := RandomNumberGenerator.new()
# Battle sounds sit where they happen, left to right (2026-11-22): five buses with a panner each, chosen
# by the event's x on screen. Kept gentle so a fight at one gate never sounds one-eared.
const PAN_BUSES := ["SFX_L2","SFX_L1","SFX","SFX_R1","SFX_R2"]
const PAN_AMOUNT := [-0.55,-0.27,0.0,0.27,0.55]
# Shots by shooter: crossbow towers twang deeper, the arquebus cracks, casters hum (2026-11-22).
const SHOT_SOUND := {
	"tower":"bolt", "watchtower":"bolt", "shroud_arbalist":"bolt", "vampire_hunter":"bolt",
	"arquebusier":"gun",
	"prism_mage":"magic", "sigil_weaver":"magic", "spell_mirror":"magic", "spell_tide_magus":"magic", "astrolabe_surveyor":"magic", "seal_bearer":"magic", "arcane_archer":"magic",
	"necromancer":"dark", "funeral_monk":"dark", "mourning_maid":"dark", "dark_wizard":"dark", "old_witch":"dark",
	"beekeeper":"none", "bellbearer":"none",
	"boss_bomb":"lob", "boss_pierce":"bolt", "boss_curse":"dark",
}
const BIG_UNITS := ["corpse_giant","arcane_golem","bog_troll","thorn_dragon","dire_hydra","tusk_boar","gold_monster","thorn_mother","knight","ram","catapult"]

static func ensure_pan_buses() -> void:
	if AudioServer.get_bus_index("SFX") < 0: return
	for i: int in range(PAN_BUSES.size()):
		var bus: String = PAN_BUSES[i]
		if bus == "SFX" or AudioServer.get_bus_index(bus) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus)
		AudioServer.set_bus_send(index,"SFX")
		var panner := AudioEffectPanner.new()
		panner.pan = PAN_AMOUNT[i]
		AudioServer.add_bus_effect(index,panner)

# Screen x (0..1600) -> the bus for that fifth of the page.
static func pan_bus(x: float) -> String:
	if x < 0.0: return "SFX"
	return PAN_BUSES[clampi(int(x/1600.0*5.0),0,4)]

func _ready() -> void:
	_sfx_rng.randomize()
	ensure_pan_buses()
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

func cue(kind: String, screen_x: float = -1.0) -> void:
	if not enabled or not CUES.has(kind) or DisplayServer.get_name() == "headless":
		return
	var now := int(get_parent().clock*1000.0) if get_parent() != null and "clock" in get_parent() else Time.get_ticks_msec() # game time, so recordings throttle like live play
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
	player.bus = pan_bus(screen_x) if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	player.play()

func cue_event(e: Dictionary) -> void:
	if not enabled or e.get("silent", false) or DisplayServer.get_name() == "headless":
		return
	var k: String = e.get("kind", "")
	var x := screen_x_of(e)
	if k == "death":
		var dead: String = e.get("card", "")
		if B.CARDS.get(dead, {}).get("type", "") == "building": cue("collapse", x)
		elif dead in BIG_UNITS or B.CARDS.get(dead, {}).get("giant", false) or B.CARDS.get(dead, {}).get("attack_style", "") == "heavy": cue("big_death", x)
		else: cue("death", x)
		return
	if k == "arrow":
		match String(SHOT_SOUND.get(String(e.get("card", "")), "arrow")):
			"bolt": cue("bolt_shot", x)
			"gun": cue("gun_shot", x)
			"magic": cue("magic_shot", x)
			"dark": cue("dark_shot", x)
			"lob": cue("catapult_fire", x)
			"none": pass
			_: cue("arrow", x)
		return
	if k == "play":
		var card: String = e.get("card", "")
		if B.CARDS.get(card, {}).get("type", "") == "building":
			cue("build", x)
		else:
			cue("play", x)
	elif k == "spell":
		var card: String = e.get("card", "")
		if card in ["charge_horn", "wing_gust", "pack_ambush", "counter_charge"]: cue("skill", x)
		elif card in ["chain_lightning", "mana_drain"]: cue("lightning", x)
		elif card == "rolling_boulder": cue("boulder", x)
		elif card in ["fire", "flaming_pitch"]: cue("burn", x)
		elif card in ["harvest", "arcane_shield", "mana_spring"]: cue("holy_heal", x)
		elif card == "dread_howl": cue("roar", x)
		elif card in ["phase_shift", "mirror_clone", "time_field"]: cue("teleport", x)
		elif card in ["curse", "plague", "gravity_well", "corrosive_bile", "sealed_coffin", "devouring_maw"]: cue("curse_rise", x)
		elif card in ["feral_mutation", "berserk_blood"]: cue("heal", x)
		elif card in ["swarm_eruption", "borrowed_bones", "grave_exchange", "levy"]: cue("summoned", x)
		else: cue("spell", x)
	elif k == "hit":
		var attacker: String = e.get("attacker", "")
		var target: String = e.get("target", "")
		if target in ["shieldguard", "barricade", "bonewall"]:
			cue("shield", x)
		elif B.CARDS.get(target, {}).get("type", "") == "building":
			cue("wall_hit", x)
		elif attacker.begins_with("giant_") or attacker in ["corpse_giant", "arcane_golem", "bog_troll", "thorn_dragon", "dire_hydra", "tusk_boar", "gold_monster", "thorn_mother", "lord_iron", "lord_beast", "lord_lion", "lord_vampire"]:
			cue("heavy_hit", x)
		elif attacker in ["hunter", "archer", "arcane_archer", "tower", "watchtower", "shroud_arbalist", "vampire_hunter", "ballista_tower"]:
			cue("arrow_hit", x)
		elif attacker in ["axe_thrower", "macebreaker", "halberdier"]:
			cue("axe_hit", x)
		elif attacker in ["assassin", "blink_blade", "reaper", "disgraced_lancer"]:
			cue("slash", x)
		elif attacker == "spearbow":
			cue("spear", x)
		elif attacker == "ram":
			cue("ram", x)
		elif attacker in ["knight", "guard", "bandit", "militia", "adventure"]:
			cue("sword", x)
		else:
			cue("hit", x)
	elif k == "link":
		match e.get("style", ""):
			"lightning": cue("lightning", x)
			"heal", "repair": cue("support_pulse", x)
			"soul", "devour", "curse": cue("blood_gain", x)
			"summon": cue("summoned", x)
			"harvest", "mana": cue("heal", x)
	elif k == "skill":
		var lord: String = e.get("lord", "")
		if lord == "adventure":
			cue("hero_slash", x)
		elif lord == "harvest":
			cue("holy_heal", x)
		elif lord == "beast":
			cue("roar", x)
		elif lord in ["mage", "rune"]:
			cue("lightning", x)
		elif lord in ["underworld", "vampire"]:
			cue("curse_rise", x)
		else:
			cue("skill", x)
	else:
		cue(k, x)

# Where on the page an event happened (the field may be mirrored or zoomed by the camera).
func screen_x_of(e: Dictionary) -> float:
	var pos = e.get("pos")
	if not pos is Vector2: return -1.0
	var g := get_parent()
	if g == null or not "cinematic" in g or g.cinematic == null: return pos.x
	return (g.cinematic.field_transform(g)*pos).x
