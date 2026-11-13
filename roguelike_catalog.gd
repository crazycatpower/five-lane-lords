extends RefCounted
# 肉鴿模式 content (2026-11-06). Authoring data only: no battle, UI or save files.
# A run is 8 battles: floors 1-7 against 小怪領主 (B.MINION_LORDS) of rising tier, floor 8 against a
# normal lord as the boss. One loss ends the run. Each win offers 3 cards; the player swaps one in.
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")

const FLOORS := 8
const FLOOR_TIER := [1,1,2,2,2,3,3] # floors 1-7; floor 8 is the boss
const AI_LEVEL := [0,0,1,1,1,2,2,1] # 簡單／普通／困難 per floor; the boss plays 普通 with its full deck (10-run test, 2026-11-07)
const OFFER_SIZE := 3
# A roguelike battle still undecided after this many seconds goes to the side whose gates have more
# health left; a tie counts as a loss (producer 2026-11-07: stalemates must end).
const TIME_LIMIT := 480.0
# Shop (producer 2026-11-07): gold for each win by the floor's tier; card upgrades (card_upgrades.gd)
# and relics are bought with it and last for the run.
const GOLD_BY_TIER := {1:100,2:200,3:300}
const RELIC_PRICES := [200,400,600]
# Relics use the same passive keys as the 內政 lords (B.MINION_LORDS) and stack with them.
const RELICS := {
	"coin_purse":{"name":"錢袋","price":200,"mods":{"start_ink":10.0}},
	"hourglass":{"name":"沙漏","price":200,"mods":{"cycle_speed":{"*":1.15}}},
	"mid_stakes":{"name":"中路拒馬","price":200,"mods":{"start_buildings":[[2,2,"barricade"]]}},
	"gold_chest":{"name":"藏金箱","price":400,"mods":{"income_mult":1.25}},
	"deft_gloves":{"name":"巧手手套","price":400,"mods":{"cycle_speed":{"*":1.3}}},
	"twin_towers":{"name":"雙哨塔","price":400,"mods":{"start_buildings":[[0,0,"watchtower"],[0,4,"watchtower"]]}},
	"war_banner":{"name":"戰旗","price":600,"mods":{"haste":["*"]}},
	"muster_horn":{"name":"集結號","price":600,"mods":{"swarm":{"*":1}}},
	"holy_grail":{"name":"聖杯","price":600,"mods":{"toughen":["*"]}},
}
# Path choice (2026-11-09): before each of floors 1-7 the player may pick an elite instead, a 小怪
# from the next tier up (tier 3 stays tier 3) opening with more gold, for 1.5x the gold reward.
const ELITE_START_INK := 20.0
const ELITE_GOLD_MULT := 1.5
const REROLL_PRICE := 50 # shop: draw a fresh set of relics
# Our gates and lord keep their wounds from battle to battle (2026-11-09); the shop mends them.
const GATE_HP_PER_GOLD := 50.0
const LORD_HP_PER_GOLD := 10.0
const FALLEN_LORD_SHARE := 0.25 # a lord who is down when the battle is won starts the next at 25%
const ENEMY_START_INK := 10.0 # every roguelike foe, boss included, opens with 10 gold (producer 2026-11-06)

# Two lords lead a run (producer 2026-11-07). The 內政領主 stays home: it gives the side a passive
# rule (same keys as B.MINION_LORDS) and the ranged troops. The 戰鬥領主 takes the field: its
# fighting stats and skill, its home card (the starting economy buildings), and the melee troops. Starting deck, 3 + 3 + 1 + 1: the
# 內政 faction's ranged troop and the 戰鬥 faction's melee troop three times each, then one card from
# each lord. Every lord of one faction brings the same troop (one melee, one ranged per faction).
const STARTER_CORE := {
	"normal":["ox","net_hunter"],
	"magic":["arcane_golem","arcane_archer"],
	"dark":["skeleton","dark_wizard"],
	"beast":["fishbeak","long_dragon"],
}
# Every 內政 passive must help whoever fights (the home card now comes from the 戰鬥 lord); duo test
# 2026-11-07: a farm-only or skeleton-only passive did nothing for half the pairs.
const LORD_ROLES := {
	"adventure":{"domestic":{"card":"farmer","passive":{"start_ink":10.0}},"combat":{"card":"knight"}},
	"lion":{"domestic":{"card":"charge_horn","passive":{"income_mult":1.25}},"combat":{"card":"mob"}},
	"iron":{"domestic":{"card":"watchtower","passive":{"start_buildings":[[1,1,"barricade"],[1,2,"barricade"],[1,3,"barricade"]]}},"combat":{"card":"manor_retainer"}},
	"harvest":{"domestic":{"card":"harvest","passive":{"income_mult":1.25,"farm_mult":1.25}},"combat":{"card":"levy"}},
	"mage":{"domestic":{"card":"teleport_trap","passive":{"cycle_speed":{"*":1.25}}},"combat":{"card":"blink_blade"}},
	"rune":{"domestic":{"card":"artificer","passive":{"start_buildings":[[2,1,"teleport_trap"],[2,3,"teleport_trap"]]}},"combat":{"card":"summon_trap"}},
	"underworld":{"domestic":{"card":"bonewall","passive":{"toughen":["dark_wizard"]}},"combat":{"card":"ghoul"}},
	"beast":{"domestic":{"card":"bearded_imp","passive":{"haste":["long_dragon"]}},"combat":{"card":"thorn_dragon"}},
	"vampire":{"domestic":{"card":"blood_tower","passive":{"start_ink":10.0,"haste":["dark_wizard"]}},"combat":{"card":"reaper"}},
}

static func starter_deck(domestic: String, combat: String) -> Array:
	var ranged: String = STARTER_CORE[B.lord_faction(domestic)][1]
	var melee: String = STARTER_CORE[B.lord_faction(combat)][0]
	return [ranged,ranged,ranged,melee,melee,melee,LORD_ROLES[domestic].domestic.card,LORD_ROLES[combat].combat.card]

static func passive(domestic: String) -> Dictionary:
	return LORD_ROLES[domestic].domestic.passive

# Cards either lord's faction may use (plus neutral ones); the home card stays in its own slot.
static func card_pool(domestic: String, combat: String) -> Array:
	var result: Array = DeckStore.pool(domestic)
	for k: String in DeckStore.pool(combat):
		if not k in result: result.append(k)
	return result.filter(func(k: String) -> bool: return k != B.home_card(combat))

static func deck_allowed(deck: Array, domestic: String, combat: String) -> bool:
	if deck.size() != 8: return false
	var pool := card_pool(domestic,combat)
	return deck.all(func(k) -> bool: return k is String and k in pool)

# Each 小怪領主's tier (which floors it may appear on) and its deck. Repeats are the point: the
# deck leans on the card the lord is named after.
const MINIONS := {
	"card_enemy_glutton_nest":{"tier":3,"deck":["fishbeak","fishbeak","bearded_imp","bearded_imp","belly_eye","hooknose_flyer","long_dragon","thorn_dragon"],"enabled":false},
	"card_enemy_mana_spring":{"tier":1,"deck":["mana_spring","mana_spring","arcane_golem","artificer","arcane_archer","militia","militia","arcane_shield"]},
	"card_enemy_chain_lightning":{"tier":2,"deck":["chain_lightning","chain_lightning","chronomancer","arcane_archer","arcane_archer","arcane_golem","shieldguard","artificer"]},
	"card_enemy_arcane_shield":{"tier":1,"deck":["arcane_shield","arcane_shield","arcane_golem","blink_blade","militia","militia","artificer","hunter"]},
	"card_enemy_time_field":{"tier":3,"deck":["time_field","time_field","arcane_archer","arcane_archer","chronomancer","shieldguard","shieldguard","hunter"]},
	"card_enemy_charge_horn":{"tier":1,"deck":["charge_horn","charge_horn","ox","ox","mob","mob","knight","drummer"]},
	"card_enemy_levy":{"tier":2,"deck":["levy","levy","militia","militia","hunter","hunter","manor_retainer","watchtower"]},
	"card_enemy_watchtower":{"tier":1,"deck":["watchtower","watchtower","hunter","hunter","net_hunter","net_hunter","militia","militia"]},
	"card_enemy_sacrifice":{"tier":3,"deck":["sacrifice","sacrifice","skeleton","skeleton","skeleton","ghoul","mass_grave","dark_wizard"]},
	"card_enemy_dread_howl":{"tier":2,"deck":["dread_howl","dread_howl","reaper","ghoul","ghoul","skeleton","raven","hunter"]},
	"card_enemy_mass_grave":{"tier":3,"deck":["mass_grave","mass_grave","skeleton","skeleton","necromancer","ghoul","dark_wizard","curse"]},
	"card_enemy_manor_retainer":{"tier":2,"deck":["manor_retainer","manor_retainer","manor_retainer","hunter","hunter","watchtower","farmer","levy"]},
	"card_enemy_rolling_boulder":{"tier":3,"deck":["rolling_boulder","rolling_boulder","catapult","catapult","hunter","hunter","barricade","shieldguard"]},
	"card_enemy_dark_wizard":{"tier":1,"deck":["dark_wizard","dark_wizard","skeleton","skeleton","skeleton","mass_grave","ghoul","curse"]},
	"card_enemy_summon_trap":{"tier":1,"deck":["summon_trap","summon_trap","arcane_golem","artificer","hunter","hunter","militia","arcane_shield"]},
	"card_enemy_chimera":{"tier":1,"deck":["summon_trap","summon_trap","arcane_golem","artificer","arcane_shield","hunter","hunter","militia"]},
	"card_enemy_blink_blade":{"tier":1,"deck":["blink_blade","blink_blade","blink_blade","phase_rider","arcane_shield","hunter","hunter","time_field"]},
	"card_enemy_arcane_archer":{"tier":3,"deck":["arcane_archer","arcane_archer","arcane_archer","shieldguard","shieldguard","time_field","artificer","arcane_golem"]},
	"card_enemy_artificer":{"tier":2,"deck":["artificer","artificer","arcane_golem","arcane_golem","arcane_tower","arcane_shield","militia","hunter"]},
	"card_enemy_crystal":{"tier":2,"deck":["artificer","artificer","arcane_golem","mana_spring","mana_spring","arcane_archer","militia","militia"]},
	"card_enemy_teleport_trap":{"tier":3,"deck":["teleport_trap","teleport_trap","teleport_trap","arcane_archer","hunter","hunter","militia","time_field"]},
	"card_enemy_arcane_tower":{"tier":3,"deck":["arcane_tower","arcane_tower","artificer","artificer","arcane_golem","shieldguard","hunter","chain_lightning"]},
	"card_enemy_eyewing_dragon":{"tier":2,"deck":["eyewing_dragon","eyewing_dragon","eyewing_dragon","fishbeak","fishbeak","hooknose_flyer","dread_howl","belly_eye"]},
	"card_enemy_belly_eye":{"tier":1,"deck":["belly_eye","belly_eye","belly_eye","net_hunter","net_hunter","hunter","hunter","fishbeak"]},
	"card_enemy_hooknose_flyer":{"tier":1,"deck":["hooknose_flyer","hooknose_flyer","hooknose_flyer","raven","raven","fishbeak","militia","rain"]},
	"card_enemy_long_dragon":{"tier":3,"deck":["long_dragon","long_dragon","long_dragon","belly_eye","belly_eye","fishbeak","chronomancer","time_field"]},
	"card_enemy_barricade":{"tier":3,"deck":["barricade","barricade","hunter","hunter","hunter","militia","militia","net_hunter"]},
	"card_enemy_corpse_giant":{"tier":1,"deck":["corpse_giant","corpse_giant","necromancer","skeleton","skeleton","ghoul","blood_tower","plague"]},
	"card_enemy_curse":{"tier":1,"deck":["curse","ghoul","dark_wizard","dark_wizard","skeleton","skeleton","reaper","plague"]},
	"card_enemy_grave":{"tier":1,"deck":["skeleton","skeleton","skeleton","necromancer","ghoul","ghoul","mass_grave","curse"]},
	"card_enemy_reaper":{"tier":1,"deck":["reaper","reaper","reaper","skeleton","skeleton","ghoul","dread_howl","plague"]},
	"card_enemy_plague":{"tier":2,"deck":["plague","plague","corpse_giant","skeleton","skeleton","ghoul","ghoul","bonewall"]},
	"card_enemy_bonewall":{"tier":1,"deck":["bonewall","bonewall","necromancer","necromancer","skeleton","skeleton","hunter","curse"]},
	"card_enemy_farmer":{"tier":3,"deck":["farmer","farmer","militia","militia","militia","hunter","hunter","ox"]},
	"card_enemy_harvest":{"tier":1,"deck":["harvest","farmer","farmer","militia","militia","hunter","ox","knight"]},
	"card_enemy_scarecrow":{"tier":1,"deck":["scarecrow","scarecrow","farmer","farmer","hunter","hunter","militia","militia"]},
	"card_enemy_spearbow":{"tier":2,"deck":["spearbow","spearbow","spearbow","drummer","healer","hunter","militia","levy"]},
	"card_enemy_farm":{"tier":2,"deck":["farmer","militia","militia","militia","hunter","hunter","spearbow","scarecrow"]},
	"card_enemy_rain":{"tier":2,"deck":["rain","rain","hunter","hunter","spearbow","shieldguard","militia","watchtower"]},
	"card_enemy_fire":{"tier":1,"deck":["fire","fire","bandit","bandit","raven","raven","shieldguard","hunter"]},
	"card_enemy_guard":{"tier":1,"deck":["guard","guard","guard","knight","healer","shieldguard","hunter","charge_horn"]},
	"card_enemy_mill":{"tier":1,"deck":["mill","mill","farmer","farmer","ox","militia","hunter","spearbow"]},
	"mob_foreman":{"tier":2,"deck":["mob","mob","mob","militia","militia","hunter","hunter","drummer"]},
	"net_poacher":{"tier":2,"deck":["net_hunter","net_hunter","net_hunter","hunter","bandit","bandit","militia","barricade"]},
	"field_prior":{"tier":3,"deck":["healer","healer","militia","militia","militia","shieldguard","shieldguard","hunter"]},
	"axe_raider":{"tier":3,"deck":["axe_thrower","axe_thrower","axe_thrower","shieldguard","shieldguard","bandit","drummer","rain"]},
	"phase_stalker":{"tier":3,"deck":["phase_rider","phase_rider","phase_rider","blink_blade","bandit","bandit","arcane_shield","time_field"]},
	"ghoul_feaster":{"tier":2,"deck":["ghoul","ghoul","ghoul","skeleton","skeleton","skeleton","mass_grave","plague"]},
	"blood_prior":{"tier":2,"deck":["blood_tower","ghoul","ghoul","dark_wizard","skeleton","skeleton","reaper","corpse_giant"]},
	"clock_warden":{"tier":3,"deck":["chronomancer","chronomancer","chronomancer","arcane_archer","arcane_golem","time_field","teleport_trap","arcane_shield"]},
	"ram_marshal":{"tier":2,"deck":["ram","ram","ram","shieldguard","shieldguard","healer","net_hunter","charge_horn"]},
	"bandit_chief":{"tier":3,"deck":["bandit","bandit","bandit","bandit","militia","militia","hunter","hunter"]},
	"militia_captain":{"tier":3,"deck":["militia","militia","militia","militia","militia","hunter","hunter","rain"]},
	"hunter_master":{"tier":3,"deck":["hunter","hunter","hunter","hunter","militia","militia","barricade","barricade"]},
	"raven_mother":{"tier":3,"deck":["raven","raven","raven","bandit","bandit","bandit","skeleton","skeleton"]},
	"fishbeak_boss":{"tier":3,"deck":["fishbeak","fishbeak","fishbeak","fishbeak","bearded_imp","bearded_imp","militia","militia"]},
	"ox_herder":{"tier":2,"deck":["ox","ox","ox","farmer","farmer","militia","militia","militia"]},
	"shield_sergeant":{"tier":3,"deck":["shieldguard","shieldguard","shieldguard","shieldguard","hunter","hunter","drummer","drummer"]},
	"drummer_major":{"tier":2,"deck":["drummer","drummer","mob","mob","militia","militia","bandit","bandit"]},
	"skeleton_king":{"tier":2,"deck":["skeleton","skeleton","skeleton","skeleton","ghoul","ghoul","bonewall","plague"]},
	"trap_weaver":{"tier":2,"deck":["blast_trap","blast_trap","teleport_trap","teleport_trap","hunter","hunter","militia","militia"]},
	"imp_thief":{"tier":3,"deck":["bearded_imp","bearded_imp","bearded_imp","bearded_imp","hooknose_flyer","hooknose_flyer","barricade","barricade"]},
	"knight_commander":{"tier":1,"deck":["knight","knight","knight","healer","healer","shieldguard","shieldguard","shieldguard"]},
	"tower_warden":{"tier":2,"deck":["hunter","hunter","hunter","tower","barricade","barricade","militia","militia"]},
	"necro_adept":{"tier":2,"deck":["necromancer","necromancer","skeleton","skeleton","skeleton","bonewall","curse","ghoul"]},
	"golem_smith":{"tier":1,"deck":["arcane_golem","arcane_golem","artificer","artificer","arcane_shield","arcane_shield","militia","militia"]},
	"catapult_engineer":{"tier":3,"deck":["catapult","catapult","shieldguard","shieldguard","shieldguard","barricade","barricade","barricade"]},
	"dragon_lord":{"tier":1,"deck":["thorn_dragon","thorn_dragon","eyewing_dragon","eyewing_dragon","belly_eye","belly_eye","long_dragon","long_dragon"]},
	"card_enemy_mule_cart":{"tier":1,"deck":["mule_cart","mule_cart","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_hook_collector":{"tier":2,"deck":["hook_collector","hook_collector","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_twin_gambler":{"tier":1,"deck":["twin_gambler","twin_gambler","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_gatebreaker":{"tier":3,"deck":["gatebreaker","gatebreaker","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_disgraced_lancer":{"tier":2,"deck":["disgraced_lancer","disgraced_lancer","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_runaway_thrall":{"tier":1,"deck":["runaway_thrall","runaway_thrall","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_renegade_artificer":{"tier":2,"deck":["renegade_artificer","renegade_artificer","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_oathless_imp":{"tier":1,"deck":["oathless_imp","oathless_imp","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_assassin":{"tier":2,"deck":["assassin","assassin","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_vampire_hunter":{"tier":2,"deck":["vampire_hunter","vampire_hunter","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_monster_hunter":{"tier":2,"deck":["monster_hunter","monster_hunter","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_spellbreaker":{"tier":2,"deck":["spellbreaker","spellbreaker","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_powder_barrel":{"tier":1,"deck":["powder_barrel","powder_barrel","militia","hunter","shieldguard","spearbow","rain","bandit"]},
	"card_enemy_pallbearer":{"tier":2,"deck":["pallbearer","pallbearer","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_mourning_maid":{"tier":1,"deck":["mourning_maid","mourning_maid","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_corpse_stitcher":{"tier":2,"deck":["corpse_stitcher","corpse_stitcher","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_blood_attendant":{"tier":2,"deck":["blood_attendant","blood_attendant","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_funeral_cottage":{"tier":1,"deck":["funeral_cottage","funeral_cottage","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_sleepless_belfry":{"tier":2,"deck":["sleepless_belfry","sleepless_belfry","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_blood_altar":{"tier":1,"deck":["blood_altar","blood_altar","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_borrowed_bones":{"tier":1,"deck":["borrowed_bones","borrowed_bones","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_grave_exchange":{"tier":1,"deck":["grave_exchange","grave_exchange","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_mourning_shroud":{"tier":1,"deck":["mourning_shroud","mourning_shroud","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_sealed_coffin":{"tier":1,"deck":["sealed_coffin","sealed_coffin","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_arquebusier":{"tier":2,"deck":["arquebusier","arquebusier","militia","hunter","knight","shieldguard","ox","farmer"]},
	"card_enemy_funeral_grenadier":{"tier":2,"deck":["funeral_grenadier","funeral_grenadier","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_dog_cannon":{"tier":3,"deck":["dog_cannon","dog_cannon","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_orrery_walker":{"tier":3,"deck":["orrery_walker","orrery_walker","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_seal_bearer":{"tier":3,"deck":["seal_bearer","seal_bearer","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_imp_bomb_runner":{"tier":1,"deck":["imp_bomb_runner","imp_bomb_runner","fishbeak","bearded_imp","belly_eye","hooknose_flyer","tusk_boar","bog_troll"]},
	"card_enemy_macebreaker":{"tier":2,"deck":["macebreaker","macebreaker","militia","hunter","knight","shieldguard","ox","farmer"]},
	"card_enemy_beekeeper":{"tier":1,"deck":["beekeeper","beekeeper","militia","hunter","knight","shieldguard","ox","farmer"]},
	"card_enemy_bellbearer":{"tier":2,"deck":["bellbearer","bellbearer","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_shroud_arbalist":{"tier":2,"deck":["shroud_arbalist","shroud_arbalist","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_sigil_weaver":{"tier":2,"deck":["sigil_weaver","sigil_weaver","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_astrolabe_surveyor":{"tier":1,"deck":["astrolabe_surveyor","astrolabe_surveyor","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_bog_troll":{"tier":3,"deck":["bog_troll","bog_troll","fishbeak","bearded_imp","belly_eye","hooknose_flyer","tusk_boar","militia"]},
	"card_enemy_tusk_boar":{"tier":3,"deck":["tusk_boar","tusk_boar","fishbeak","bearded_imp","belly_eye","hooknose_flyer","bog_troll","militia"]},
	"card_enemy_granary":{"tier":2,"deck":["granary","granary","militia","hunter","knight","shieldguard","ox","farmer"]},
	"card_enemy_field_smithy":{"tier":2,"deck":["field_smithy","field_smithy","militia","hunter","knight","shieldguard","ox","farmer"]},
	"card_enemy_ossuary":{"tier":3,"deck":["ossuary","ossuary","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_soul_well":{"tier":2,"deck":["soul_well","soul_well","skeleton","ghoul","necromancer","dark_wizard","reaper","curse"]},
	"card_enemy_observatory":{"tier":2,"deck":["observatory","observatory","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_rune_workshop":{"tier":2,"deck":["rune_workshop","rune_workshop","arcane_golem","arcane_archer","artificer","blink_blade","chronomancer","militia"]},
	"card_enemy_monster_hatchery":{"tier":3,"deck":["monster_hatchery","monster_hatchery","fishbeak","bearded_imp","belly_eye","hooknose_flyer","tusk_boar","bog_troll"]},
	"card_enemy_war_lodge":{"tier":2,"deck":["war_lodge","war_lodge","fishbeak","bearded_imp","belly_eye","hooknose_flyer","tusk_boar","bog_troll"]},
}

# Floor 8: a normal lord with a full-strength, fighting deck (league test 2026-11-07: the old
# farming presets for 鐵壁／豐收／紅獅 won only 10-21%).
const BOSSES := {
	"adventure":["knight","hunter","militia","ram","rain","healer","tower","spearbow"],
	"lion":["knight","mob","ox","charge_horn","militia","hunter","spearbow","ram"],
	"iron":["knight","shieldguard","hunter","tower","manor_retainer","rain","spearbow","healer"],
	"harvest":["farmer","knight","mob","hunter","spearbow","rain","healer","ox"],
	"mage":["arcane_golem","bandit","chronomancer","blast_trap","blink_blade","arcane_archer","rolling_boulder","teleport_trap"],
	"rune":["arcane_tower","blast_trap","teleport_trap","summon_trap","artificer","seal_bearer","chronomancer","arcane_archer"],
	"underworld":["skeleton","ghoul","necromancer","reaper","bonewall","plague","raven","shroud_arbalist"],
	"vampire":["ghoul","dark_wizard","blood_tower","corpse_giant","skeleton","curse","sacrifice","blood_attendant"],
	"beast":["fishbeak","bearded_imp","hooknose_flyer","long_dragon","thorn_dragon","eyewing_dragon","belly_eye","tusk_boar"],
}

# Seven 小怪領主 for floors 1-7 (no repeats) and a boss for floor 8, fixed by the run's seed.
static func schedule(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	for tier: int in FLOOR_TIER:
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier and not k in result)
		result.append(choices[rng.randi_range(0,choices.size()-1)])
	var bosses: Array = BOSSES.keys()
	result.append(bosses[rng.randi_range(0,bosses.size()-1)])
	return result

static func elite_tier(floor_index: int) -> int:
	return mini(3,FLOOR_TIER[floor_index]+1)

# One elite per floor 1-7, never one of the run's normal foes and never twice; fixed by the seed.
static func elite_schedule(seed_value: int, foes: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*17+5
	var result: Array = []
	for i: int in range(FLOOR_TIER.size()):
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == elite_tier(i) and not k in foes and not k in result)
		choices.sort()
		result.append(choices[rng.randi_range(0,choices.size()-1)])
	return result

static func foe_deck(foe: String) -> Array:
	return (MINIONS[foe].deck if MINIONS.has(foe) else BOSSES[foe]).duplicate()

# Three different cards the two lords may use, fixed by the run's seed and floor.
static func offer(domestic: String, combat: String, seed_value: int, floor_index: int, deck: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*31+floor_index*977
	var pool: Array = card_pool(domestic,combat)
	var result: Array = []
	var groups: Array = []
	# Prefer unseen cards, then unrepresented roles; seeded choices remain stable on reload.
	while result.size() < OFFER_SIZE and not pool.is_empty():
		var fresh: Array = pool.filter(func(k: String) -> bool: return not k in deck)
		var candidates: Array = fresh if not fresh.is_empty() else pool
		var diverse: Array = candidates.filter(func(k: String) -> bool: return not B.card_group(k) in groups)
		if not diverse.is_empty(): candidates = diverse
		var chosen: String = candidates[rng.randi_range(0,candidates.size()-1)]
		result.append(chosen)
		groups.append(B.card_group(chosen))
		pool.erase(chosen)
	return result

static func gold_for(floor_index: int) -> int:
	return GOLD_BY_TIER[FLOOR_TIER[floor_index]] if floor_index < FLOOR_TIER.size() else 0

# One relic of each price the run does not own yet, fixed by seed and floor.
static func relic_offer(seed_value: int, floor_index: int, owned: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*53+floor_index*389
	var result: Array = []
	for price: int in RELIC_PRICES:
		var choices: Array = RELICS.keys().filter(func(k: String) -> bool: return RELICS[k].price == price and not k in owned)
		choices.sort()
		if not choices.is_empty(): result.append(choices[rng.randi_range(0,choices.size()-1)])
	return result

# Stack passive rule sets: multipliers multiply, gold adds, lists join, start buildings skip taken cells.
static func merge_mods(base: Dictionary, extra: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key: String in extra:
		var value = extra[key]
		if not result.has(key): result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
		elif key.ends_with("_mult"): result[key] *= value
		elif key == "start_ink": result[key] += value
		elif key == "cycle_speed":
			for k: String in value: result[key][k] = result[key].get(k,1.0)*value[k]
		elif key == "swarm":
			for k: String in value: result[key][k] = result[key].get(k,0)+value[k]
		elif key in ["toughen","haste"]:
			for k in value:
				if not k in result[key]: result[key].append(k)
		elif key == "start_buildings":
			for b: Array in value:
				if not result[key].any(func(o: Array) -> bool: return o[0] == b[0] and o[1] == b[1]): result[key].append(b)
	return result

static func side_mods(domestic: String, relics: Array) -> Dictionary:
	var mods: Dictionary = passive(domestic)
	for r: String in relics: mods = merge_mods(mods,RELICS[r].mods)
	return mods

# Everything wrong with the tables ([] = fine). quick_test fails on any problem.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	for lord: String in B.LORDS:
		if not LORD_ROLES.has(lord): problems.append("no roguelike roles for "+lord)
		if not BOSSES.has(lord): problems.append("no boss deck for "+lord)
	for lord: String in LORD_ROLES:
		var roles: Dictionary = LORD_ROLES[lord]
		if not STARTER_CORE.has(B.lord_faction(lord)): problems.append("no starter troops for %s's faction" % lord)
		for role: String in ["domestic","combat"]:
			var card: String = roles.get(role,{}).get("card","")
			if not B.CARDS.has(card) or B.card_faction(card) != B.lord_faction(lord): problems.append("%s %s card must be its own faction's card" % [lord,role])
			for faction: String in STARTER_CORE:
				if card in STARTER_CORE[faction]: problems.append("%s %s card repeats a starter troop" % [lord,role])
		var mods: Dictionary = roles.get("domestic",{}).get("passive",{})
		if mods.is_empty() or B.passive_text(mods).length() < 3: problems.append("%s has no 內政 passive" % lord)
		# The passive must work with any 戰鬥 partner: troop boosts only for cards this lord brings.
		if STARTER_CORE.has(B.lord_faction(lord)):
			var own: Array = [STARTER_CORE[B.lord_faction(lord)][1],roles.domestic.card]
			for group: String in ["toughen","haste"]:
				for k in mods.get(group,[]):
					if k != "*" and not k in own: problems.append("%s 內政 %s %s only helps some partners" % [lord,group,str(k)])
			if mods.has("farm_mult") and mods.size() == 1: problems.append("%s 內政 passive only helps farm lords" % lord)
	for domestic: String in LORD_ROLES:
		for combat: String in LORD_ROLES:
			if domestic == combat or not STARTER_CORE.has(B.lord_faction(domestic)) or not STARTER_CORE.has(B.lord_faction(combat)): continue
			var cards := starter_deck(domestic,combat)
			var counts := {}
			for k: String in cards: counts[k] = counts.get(k,0)+1
			var shape: Array = counts.values()
			shape.sort()
			if shape != [1,1,3,3]: problems.append("starter %s+%s is not 3+3+1+1" % [domestic,combat])
			if not deck_allowed(cards,domestic,combat): problems.append("starter %s+%s holds a card neither lord may use" % [domestic,combat])
	for faction: String in STARTER_CORE:
		for k: String in STARTER_CORE[faction]:
			if B.card_faction(k) != faction: problems.append("starter core %s: %s is not that faction's card" % [faction,k])
		if B.card_group(STARTER_CORE[faction][0]) != 0 or B.card_group(STARTER_CORE[faction][1]) != 1: problems.append("starter core %s must be one melee then one ranged troop" % faction)
	for foe: String in MINIONS:
		if not B.MINION_LORDS.has(foe): problems.append("minion deck for unknown lord "+foe)
		if not DeckStore.valid(MINIONS[foe].deck,"",true): problems.append("minion %s deck is not legal" % foe)
		if B.home_card(foe) in MINIONS[foe].deck: problems.append("minion %s deck holds its home card" % foe)
	for foe: String in B.MINION_LORDS:
		if not MINIONS.has(foe): problems.append("minion lord %s has no deck" % foe)
	for tier: int in [1,2,3]:
		var need: int = FLOOR_TIER.count(tier)
		if MINIONS.values().filter(func(d: Dictionary) -> bool: return d.get("enabled",true) and d.tier == tier).size() < need: problems.append("not enough tier %d minions" % tier)
	for lord: String in BOSSES:
		if not DeckStore.valid(BOSSES[lord],lord): problems.append("boss deck %s is not legal" % lord)
	for tier: int in [1,2,3]:
		var need: int = FLOOR_TIER.count(tier)+range(FLOOR_TIER.size()).filter(func(i: int) -> bool: return elite_tier(i) == tier).size()
		if MINIONS.values().filter(func(d: Dictionary) -> bool: return d.get("enabled",true) and d.tier == tier).size() < need: problems.append("not enough tier %d 小怪 for normal foes plus elites" % tier)
	for r: String in RELICS:
		if not RELICS[r].price in RELIC_PRICES: problems.append("relic %s has an off-list price" % r)
		if B.passive_text(RELICS[r].mods).length() < 3: problems.append("relic %s has no effect" % r)
	for price: int in RELIC_PRICES:
		if RELICS.values().filter(func(d: Dictionary) -> bool: return d.price == price).size() < 2: problems.append("fewer than two relics at %d" % price)
	for card: String in B.CARDS:
		var matching: Array = MINIONS.keys().filter(func(k: String) -> bool: return B.MINION_LORDS.has(k) and B.MINION_LORDS[k].card == card)
		if matching.size() != 1: problems.append("card needs exactly one enemy: "+card)
		elif B.CARDS[card].get("unreleased",false) and MINIONS[matching[0]].get("enabled",true): problems.append("unreleased enemy must stay disabled: "+card)
	return problems
