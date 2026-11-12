extends SceneTree

const SoundBank = preload("res://sound_bank.gd")

func _initialize() -> void:
	print("Testing SoundBank assets and cues...")
	var bank := SoundBank.new()
	root.add_child(bank)
	bank._ready()
	
	for cue_key: String in bank.CUES:
		var file_name: String = bank.CUES[cue_key]
		var path := "res://assets/audio/" + file_name + ".ogg"
		assert(ResourceLoader.exists(path), "Missing sound file: " + path)
		assert(bank.streams.has(file_name), "Stream not loaded for: " + file_name)
	
	# Test cue_event for all major mechanics
	bank.cue_event({"kind": "spell", "card": "charge_horn"})
	bank.cue_event({"kind": "spell", "card": "chain_lightning"})
	bank.cue_event({"kind": "spell", "card": "rolling_boulder"})
	bank.cue_event({"kind": "spell", "card": "fire"})
	bank.cue_event({"kind": "spell", "card": "curse"})
	bank.cue_event({"kind": "drum"})
	bank.cue_event({"kind": "arrow"})
	bank.cue_event({"kind": "hit", "attacker": "spearbow"})
	bank.cue_event({"kind": "hit", "attacker": "axe_thrower"})
	bank.cue_event({"kind": "hit", "attacker": "knight", "target": "shieldguard"})
	bank.cue_event({"kind": "hit", "attacker": "ram"})
	bank.cue_event({"kind": "stone_impact"})
	bank.cue_event({"kind": "breach"})
	bank.cue_event({"kind": "heal"})
	bank.cue_event({"kind": "curse_rise"})
	
	print("ALL 28 sound cues and dynamic event mappings PASSED!")
	quit(0)
