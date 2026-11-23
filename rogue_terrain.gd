extends RefCounted
# 肉鴿模式每個怪的戰場（使用者 2026-11-22：給每個怪設計地形搭配地圖機制，部分怪為精英怪）。
# 一個怪 = 一張地圖範本（MAPS：路數、水、風、巨石）＋ 季節 ＋ 他的招牌機制（FOES 的 mech）。
# 招牌機制只用戰場既有的四種（battle.apply_field_mutator）：
#   ["pre", 卡, [[欄,路],…]]   開局預築他的建築（欄從敵方後排數起，0＝敵方城牆前）
#   ["pulse", 法術, 秒]        每隔幾秒朝我軍（或對自軍增益）施放一次
#   ["grow", 建築, 秒]         每隔幾秒在敵方半場空格冒出一座
#   ["van", 部隊, [路,…]]      開局先派這些路各一名壓境
# ELITES 的怪只在精英格出現（roguelike_catalog.elite_schedule / pick_minion），一般戰鬥不會遇到。
# 肉鴿沒有夜晚，所以不用夏天（夏天的規則是延後入夜）。
const SIX := [0,1,2,3,4,5]

const MAPS := {
	"open":{"name":"平原會戰"},
	"plain6":{"name":"六路大平原","rows":6},
	"trident":{"name":"三岔路","lanes":[1,2,3]},
	"twin":{"name":"雙廊","lanes":[1,3]},
	"gorge":{"name":"單線峽谷","lanes":[2]},
	"four":{"name":"四路關隘","lanes":[0,1,3,4]},
	"highland4":{"name":"四路高地","rows":6,"lanes":[1,2,3,4]},
	"river":{"name":"中央大河","water_cols":[4]},
	"ford":{"name":"單橋渡口","water_cells":[[4,0],[4,1],[4,3],[4,4]]},
	"marsh_flanks":{"name":"兩翼沼澤","water_lanes":[0,4]},
	"causeway":{"name":"三道長堤","water_lanes":[1,3]},
	"ponds":{"name":"池塘地","water_cells":[[3,0],[5,1],[2,3],[6,3],[4,4]]},
	"reeds6":{"name":"蘆葦大澤","rows":6,"water_cells":[[3,0],[4,1],[5,3],[3,4],[4,5],[5,2],[6,4]]},
	"moat":{"name":"敵城護城河","water_cols":[6]},
	"our_moat":{"name":"我城護城河","water_cols":[2]},
	"wind_mid":{"name":"中路順風","wind_lanes":[2],"wind_shift":{"interval":35.0}},
	"wind_flanks":{"name":"兩翼對吹","wind_lanes":[0],"wind_left_lanes":[4],"wind_shift":{"interval":40.0}},
	"gale6":{"name":"狂風高原","rows":6,"wind_lanes":[1],"wind_left_lanes":[4],"wind_shift":{"interval":30.0},"gusts":{"interval":25.0}},
	"rocks":{"name":"亂石坡","blocked":[[3,1],[5,0],[4,3],[6,2],[3,4]]},
	"checker":{"name":"棋盤石陣","blocked":[[3,0],[5,0],[4,1],[3,2],[5,2],[4,3],[3,4],[5,4]]},
	"quarry6":{"name":"採石場","rows":6,"blocked":[[3,0],[4,2],[5,4],[3,5],[5,1]]},
	"pass":{"name":"石門關","lanes":[1,2,3],"blocked":[[4,1],[4,3]]},
	"delta6":{"name":"六路河口","rows":6,"water_cols":[4]},
	"island":{"name":"湖心島","water_cells":[[3,1],[5,1],[3,3],[5,3],[4,0],[4,4]]},
	"lake6":{"name":"湖心雙渠","rows":6,"water_lanes":[2,3]},
	"wide_ford6":{"name":"寬灘","rows":6,"water_cells":[[3,0],[4,1],[5,2],[3,3],[4,4],[5,5]]},
	"volcano":{"name":"火山口","lava_cells":[[4,1],[4,3],[5,2]],"eruption":{"interval":22.0}},
	"uphill":{"name":"攻城坡","slope":{"high":1}},
	"mist":{"name":"墓霧","fog":5,"fog_drift":true},
	"bog":{"name":"泥沼地","mud_cells":[[3,1],[4,2],[5,3],[3,3],[5,1]]},
	"sluice":{"name":"水閘渠","sluice":{"lanes":[1,2,3],"interval":35.0}},
	"rune_hall":{"name":"符文殿","rune_cells":[[2,1],[2,3],[6,1],[6,3]]},
	"portal_maze":{"name":"傳送迷宮","portals":[[[3,0],[5,4]],[[3,4],[5,0]],[[4,2],[6,2]]]},
	"spire_climb":{"name":"高塔長階","rows":6,"slope":{"high":1},"rune_cells":[[2,1],[2,4]],"storm":{"interval":20.0}},
	"storm_peak":{"name":"雷暴山巔","storm":{"interval":14.0},"gusts":{"interval":25.0}},
	"snowfield":{"name":"雪原","blizzard":{"interval":35.0}},
}

const ELITES := [
	"card_enemy_chain_lightning","card_enemy_eyewing_dragon","card_enemy_plague","card_enemy_guard","clock_warden",
	"skeleton_king","card_enemy_thorn_mother","card_enemy_sleepless_belfry","card_enemy_ballista_tower",
	"card_enemy_glutton_nest","card_enemy_mass_grave","card_enemy_rolling_boulder","card_enemy_blink_blade",
	"card_enemy_teleport_trap","card_enemy_arcane_tower","card_enemy_hooknose_flyer","card_enemy_grave","phase_stalker",
	"blood_prior","card_enemy_pouch_beast","shield_sergeant","knight_commander","tower_warden","golem_smith",
	"catapult_engineer","dragon_lord","card_enemy_plague_bishop","card_enemy_powder_barrel","card_enemy_mourning_maid",
	"card_enemy_arquebusier","card_enemy_orrery_walker","card_enemy_imp_bomb_runner","card_enemy_bog_troll",
	"card_enemy_monster_hatchery","card_enemy_warp_beacon","card_enemy_sky_scavenger","card_enemy_dire_hydra","card_enemy_hive_nest",
]

# 精英特性（使用者 2026-11-22：不要異變，也許塞到某些怪的被動效果中）。原本隨機抽的精英異變改成每個精英固定一個，
# 寫在牠的被動效果裡，只在精英戰生效。[名稱, 說明, 敵方 mods, 開局額外金幣]
const ELITE_TRAITS := {
	"iron_hide":["鐵皮重甲","敵軍全體生命 +35%。",{"toughen":{"*":0.35}},0.0],
	"frenzy":["狂暴突襲","敵軍全體移速與攻速 +25%。",{"haste":{"*":0.25}},0.0],
	"swarm":["兵海狂潮","敵方每張部隊卡多出 1 名。",{"swarm":{"*":1}},0.0],
	"muster":["急行徵兵","敵方出牌冷卻速度 +45%、技能充能 +25%，開局額外 +5 金。",{"cd_speed_mult":1.45,"skill_charge_mult":1.25},5.0],
	"bastion":["荊棘堡壘","敵方城牆減傷 25%（近身攻城反傷 40）、產金 +20%、開局 +6 金。",{"gate_armor":0.25,"thorns_gate":40.0,"income_mult":1.2},6.0],
	"treasury":["敵軍金庫","敵方基本產金 +45%，開局額外 +10 金。",{"income_mult":1.45},10.0],
}
const ELITE_TRAIT_OF := {
	"golem_smith":"iron_hide","card_enemy_pouch_beast":"iron_hide","card_enemy_dire_hydra":"iron_hide","card_enemy_grave":"iron_hide",
	"card_enemy_blink_blade":"frenzy","phase_stalker":"frenzy","card_enemy_sky_scavenger":"frenzy","knight_commander":"frenzy",
	"shield_sergeant":"frenzy","card_enemy_bog_troll":"frenzy","card_enemy_mass_grave":"frenzy",
	"skeleton_king":"swarm","card_enemy_monster_hatchery":"swarm","card_enemy_mourning_maid":"swarm","card_enemy_plague":"swarm",
	"clock_warden":"muster","card_enemy_teleport_trap":"muster","card_enemy_warp_beacon":"muster","card_enemy_orrery_walker":"muster",
	"card_enemy_imp_bomb_runner":"muster","card_enemy_eyewing_dragon":"muster","card_enemy_hooknose_flyer":"muster",
	"dragon_lord":"muster","card_enemy_thorn_mother":"muster",
	"tower_warden":"bastion","catapult_engineer":"bastion","card_enemy_arcane_tower":"bastion","card_enemy_ballista_tower":"bastion",
	"card_enemy_arquebusier":"bastion","card_enemy_hive_nest":"bastion","card_enemy_plague_bishop":"bastion",
	"card_enemy_glutton_nest":"treasury","card_enemy_rolling_boulder":"treasury","blood_prior":"treasury",
	"card_enemy_sleepless_belfry":"treasury","card_enemy_powder_barrel":"treasury","card_enemy_chain_lightning":"treasury","card_enemy_guard":"treasury",
}

static func elite_trait(foe: String) -> Array:
	return ELITE_TRAITS.get(ELITE_TRAIT_OF.get(foe,""),[])

# foe: [map, season, mech]
const FOES := {
	# ---- 經典 ----
	"card_enemy_charge_horn":["wind_mid","spring",["pulse","charge_horn",30.0]],
	"card_enemy_levy":["four","autumn",["pre","watchtower",[[1,1],[1,3]]]],
	"card_enemy_watchtower":["ponds","autumn",["pre","watchtower",[[2,2]]]],
	"card_enemy_manor_retainer":["open","autumn",["pre","barricade",[[2,1],[2,3]]]],
	"card_enemy_farmer":["open","spring",["pre","farm",[[1,0],[1,4]]]],
	"card_enemy_harvest":["wind_flanks","autumn",["pulse","harvest",30.0]],
	"card_enemy_scarecrow":["trident","autumn",["pre","scarecrow",[[2,2]]]],
	"card_enemy_spearbow":["highland4","spring",["van","archer",[1,4]]],
	"card_enemy_farm":["ponds","spring",["pre","farm",[[1,1],[1,3]]]],
	"card_enemy_guard":["moat","spring",["van","knight",[1,3]]],
	"card_enemy_mill":["sluice","autumn",["pre","mill",[[1,2]]]],
	"mob_foreman":["wind_mid","spring",["van","militia",[1,3]]],
	"net_poacher":["sluice","autumn",["pre","barricade",[[2,2]]]],
	"field_prior":["trident","spring",["van","shieldguard",[2]]],
	"ram_marshal":["our_moat","autumn",["van","ram",[2]]],
	"militia_captain":["open","spring",["van","militia",[1,2,3]]],
	"hunter_master":["uphill","autumn",["pre","barricade",[[2,0],[2,1],[2,3],[2,4]]]],
	"card_enemy_archer":["trident","spring",["pre","barricade",[[2,2]]]],
	"ox_herder":["wind_flanks","spring",["van","ox",[0,4]]],
	"shield_sergeant":["pass","autumn",["van","shieldguard",[1,2,3]]],
	"drummer_major":["gale6","spring",["van","militia",[2,3]]],
	"knight_commander":["open","autumn",["van","knight",[1,3]]],
	"tower_warden":["uphill","spring",["pre","tower",[[1,1],[1,3]]]],
	"card_enemy_disgraced_lancer":["wind_mid","spring",["van","disgraced_lancer",[2]]],
	"card_enemy_arquebusier":["uphill","spring",["pre","field_smithy",[[1,2]]]],
	"card_enemy_macebreaker":["pass","autumn",["van","macebreaker",[2]]],
	"card_enemy_beekeeper":["wind_flanks","spring",["pre","scarecrow",[[2,2]]]],
	"card_enemy_granary":["sluice","autumn",["pre","granary",[[1,1],[1,3]]]],
	"card_enemy_field_smithy":["pass","spring",["pre","field_smithy",[[1,2]]]],
	"card_enemy_halberdier":["trident","spring",["pre","field_smithy",[[1,2]]]],
	"card_enemy_ballista_tower":["uphill","spring",["pre","ballista_tower",[[1,1],[1,3]]]],
	"card_enemy_supply_depot":["wind_flanks","spring",["pre","supply_depot",[[1,0],[1,4]]]],
	"card_enemy_counter_charge":["trident","autumn",["pulse","counter_charge",40.0]],
	"card_enemy_flaming_pitch":["rocks","autumn",["pulse","flaming_pitch",35.0]],
	# ---- 中立 ----
	"card_enemy_rolling_boulder":["causeway","autumn",["van","catapult",[2]]],
	"card_enemy_barricade":["pass","spring",["pre","barricade",[[2,1],[2,2],[2,3]]]],
	"card_enemy_rain":["open","autumn",["pulse","rain",25.0]],
	"card_enemy_fire":["wind_flanks","autumn",["pulse","fire",35.0]],
	"axe_raider":["rocks","autumn",["van","axe_thrower",[1,3]]],
	"bandit_chief":["reeds6","autumn",["van","bandit",[1,4]]],
	"catapult_engineer":["uphill","winter",["pre","barricade",[[2,1],[2,2],[2,3]]]],
	"card_enemy_mule_cart":["wind_flanks","autumn",["pre","watchtower",[[1,2]]]],
	"card_enemy_hook_collector":["four","autumn",["pulse","charge_horn",35.0]],
	"card_enemy_twin_gambler":["ponds","spring",["pulse","counter_charge",40.0]],
	"card_enemy_gold_monster":["open","spring",["pre","farm",[[1,1],[1,3]]]],
	"card_enemy_gatebreaker":["our_moat","autumn",["van","gatebreaker",[2]]],
	"card_enemy_assassin":["mist","autumn",["van","assassin",[1,4]]],
	"card_enemy_vampire_hunter":["moat","winter",["pre","barricade",[[2,1],[2,3]]]],
	"card_enemy_monster_hunter":["four","autumn",["van","monster_hunter",[1,3]]],
	"card_enemy_spellbreaker":["trident","spring",["van","spellbreaker",[2]]],
	"card_enemy_powder_barrel":["ford","autumn",["pre","powder_barrel",[[3,1],[3,3]]]],
	"card_enemy_old_witch":["ponds","autumn",["pre","barricade",[[2,2]]]],
	"card_enemy_recruit_camp":["open","spring",["pre","recruit_camp",[[1,2]]]],
	# ---- 魔法 ----
	"card_enemy_mana_spring":["open","spring",["pre","crystal",[[1,0],[1,4]]]],
	"card_enemy_chain_lightning":["storm_peak","winter",["pulse","chain_lightning",30.0]],
	"card_enemy_arcane_shield":["trident","spring",["pulse","arcane_shield",25.0]],
	"card_enemy_time_field":["snowfield","winter",["pulse","time_field",30.0]],
	"card_enemy_summon_trap":["checker","spring",["pre","summon_trap",[[3,1],[3,3]]]],
	"card_enemy_chimera":["island","spring",["pre","summon_trap",[[3,2]]]],
	"card_enemy_blink_blade":["twin","winter",["van","blink_blade",[1,3]]],
	"card_enemy_arcane_archer":["rune_hall","spring",["pulse","time_field",35.0]],
	"card_enemy_artificer":["quarry6","winter",["pre","arcane_tower",[[1,2]]]],
	"card_enemy_crystal":["rocks","winter",["pre","crystal",[[1,1],[1,3]]]],
	"card_enemy_teleport_trap":["portal_maze","winter",["grow","teleport_trap",30.0]],
	"card_enemy_arcane_tower":["uphill","winter",["pre","arcane_tower",[[1,1],[1,3]]]],
	"phase_stalker":["portal_maze","winter",["van","phase_rider",[2,3]]],
	"clock_warden":["checker","winter",["pulse","time_field",25.0]],
	"trap_weaver":["checker","spring",["grow","blast_trap",30.0]],
	"golem_smith":["quarry6","winter",["van","arcane_golem",[2,3]]],
	"card_enemy_renegade_artificer":["rocks","winter",["pre","tower",[[1,2]]]],
	"card_enemy_spell_tide_magus":["highland4","winter",["pulse","arcane_shield",30.0]],
	"card_enemy_orrery_walker":["spire_climb","winter",["pre","observatory",[[1,2]]]],
	"card_enemy_seal_bearer":["checker","winter",["grow","blast_trap",35.0]],
	"card_enemy_sigil_weaver":["rune_hall","spring",["pulse","arcane_shield",25.0]],
	"card_enemy_astrolabe_surveyor":["spire_climb","winter",["pre","observatory",[[1,1]]]],
	"card_enemy_observatory":["spire_climb","spring",["pre","observatory",[[1,1],[1,4]]]],
	"card_enemy_rune_workshop":["rune_hall","winter",["pre","rune_workshop",[[1,2]]]],
	"card_enemy_rune_sentinel":["rune_hall","winter",["van","rune_sentinel",[1,3]]],
	"card_enemy_ward_guard":["trident","winter",["van","rune_sentinel",[2]]],
	"card_enemy_ward_phalanx":["pass","winter",["van","rune_sentinel",[1,3]]],
	"card_enemy_prism_mage":["rune_hall","spring",["pre","observatory",[[1,2]]]],
	"card_enemy_aether_hound":["portal_maze","winter",["van","aether_hound",[2,3]]],
	"card_enemy_spell_mirror":["storm_peak","winter",["pulse","chain_lightning",30.0]],
	"card_enemy_mana_battery":["checker","spring",["pre","mana_battery",[[1,1],[1,3]]]],
	"card_enemy_warp_beacon":["quarry6","winter",["pre","warp_beacon",[[1,2]]]],
	"card_enemy_mana_drain":["snowfield","winter",["pulse","time_field",35.0]],
	"card_enemy_phase_shift":["portal_maze","winter",["van","blink_blade",[1,3]]],
	"card_enemy_gravity_well":["storm_peak","winter",["pulse","chain_lightning",35.0]],
	"card_enemy_mirror_clone":["portal_maze","spring",["van","phase_rider",[2]]],
	# ---- 黑暗 ----
	"card_enemy_sacrifice":["rocks","autumn",["van","skeleton",[1,3]]],
	"card_enemy_dread_howl":["snowfield","winter",["van","ghoul",[1,3]]],
	"card_enemy_mass_grave":["plain6","autumn",["grow","mass_grave",35.0]],
	"card_enemy_dark_wizard":["rocks","winter",["grow","grave",40.0]],
	"card_enemy_corpse_giant":["trident","autumn",["van","corpse_giant",[2]]],
	"card_enemy_curse":["rocks","winter",["pulse","curse",30.0]],
	"card_enemy_grave":["plain6","autumn",["grow","grave",40.0]],
	"card_enemy_reaper":["mist","winter",["van","reaper",[2]]],
	"card_enemy_plague":["bog","autumn",["pulse","plague",30.0]],
	"card_enemy_bonewall":["four","winter",["pre","bonewall",[[2,0],[2,4]]]],
	"ghoul_feaster":["bog","autumn",["van","ghoul",[1,3]]],
	"blood_prior":["highland4","autumn",["pre","blood_tower",[[1,2],[1,3]]]],
	"raven_mother":["lake6","autumn",["van","raven",[0,5]]],
	"skeleton_king":["plain6","winter",["grow","grave",35.0]],
	"necro_adept":["twin","winter",["grow","grave",40.0]],
	"card_enemy_seal_altar":["rocks","winter",["pre","grave",[[1,2]]]],
	"card_enemy_plague_bishop":["causeway","winter",["pulse","plague",30.0]],
	"card_enemy_funeral_monk":["trident","autumn",["pre","funeral_cottage",[[1,2]]]],
	"card_enemy_runaway_thrall":["twin","autumn",["pulse","fire",40.0]],
	"card_enemy_pallbearer":["rocks","autumn",["pre","funeral_cottage",[[1,1]]]],
	"card_enemy_mourning_maid":["mist","winter",["van","mourning_maid",[2]]],
	"card_enemy_corpse_stitcher":["plain6","autumn",["pre","ossuary",[[1,2]]]],
	"card_enemy_blood_attendant":["highland4","winter",["pre","blood_altar",[[1,2]]]],
	"card_enemy_funeral_cottage":["trident","autumn",["pre","funeral_cottage",[[1,1],[1,3]]]],
	"card_enemy_sleepless_belfry":["mist","winter",["pre","sleepless_belfry",[[1,0],[1,4]]]],
	"card_enemy_blood_altar":["rocks","autumn",["pre","blood_altar",[[1,2]]]],
	"card_enemy_borrowed_bones":["ponds","winter",["van","skeleton",[1,3]]],
	"card_enemy_grave_exchange":["open","autumn",["pre","grave",[[1,1],[1,3]]]],
	"card_enemy_mourning_shroud":["trident","winter",["van","ghoul",[2]]],
	"card_enemy_sealed_coffin":["twin","winter",["pre","bonewall",[[2,1]]]],
	"card_enemy_funeral_grenadier":["causeway","autumn",["pre","sleepless_belfry",[[1,2]]]],
	"card_enemy_dog_cannon":["gale6","winter",["van","dog_cannon",[1,4]]],
	"card_enemy_bellbearer":["trident","autumn",["van","bellbearer",[2]]],
	"card_enemy_shroud_arbalist":["four","winter",["pre","bonewall",[[2,1],[2,3]]]],
	"card_enemy_ossuary":["rocks","winter",["pre","ossuary",[[1,2]]]],
	"card_enemy_soul_well":["mist","autumn",["pre","soul_well",[[1,2]]]],
	# ---- 魔物 ----
	"card_enemy_glutton_nest":["ponds","autumn",["pre","glutton_nest",[[2,1],[2,3]]]],
	"card_enemy_eyewing_dragon":["gale6","autumn",["van","eyewing_dragon",[2]]],
	"card_enemy_belly_eye":["ponds","autumn",["van","belly_eye",[2]]],
	"card_enemy_hooknose_flyer":["lake6","autumn",["van","hooknose_flyer",[1,4]]],
	"card_enemy_long_dragon":["gorge","autumn",["van","long_dragon",[2]]],
	"card_enemy_pouch_beast":["ford","autumn",["pre","monster_hatchery",[[1,2]]]],
	"fishbeak_boss":["sluice","spring",["van","fishbeak",[1,3]]],
	"imp_thief":["four","autumn",["van","bearded_imp",[0,4]]],
	"dragon_lord":["volcano","autumn",["van","eyewing_dragon",[1,4]]],
	"card_enemy_thorn_mother":["pass","autumn",["pre","bramble_wall",[[2,1],[2,3]]]],
	"card_enemy_oathless_imp":["ponds","spring",["van","oathless_imp",[2]]],
	"card_enemy_imp_bomb_runner":["ponds","autumn",["van","imp_bomb_runner",[1,3]]],
	"card_enemy_bog_troll":["bog","autumn",["van","bog_troll",[2]]],
	"card_enemy_tusk_boar":["wind_mid","autumn",["van","tusk_boar",[2]]],
	"card_enemy_monster_hatchery":["plain6","autumn",["pre","monster_hatchery",[[1,1],[1,4]]]],
	"card_enemy_war_lodge":["volcano","autumn",["pre","war_lodge",[[1,2]]]],
	"card_enemy_parasite_mite":["reeds6","autumn",["van","parasite_mite",[1,4]]],
	"card_enemy_thorn_hound":["twin","autumn",["pre","bramble_wall",[[2,1],[2,3]]]],
	"card_enemy_web_spinner":["bog","autumn",["van","web_spinner",[2]]],
	"card_enemy_sky_scavenger":["lake6","autumn",["van","sky_scavenger",[1,4]]],
	"card_enemy_dire_hydra":["volcano","autumn",["van","dire_hydra",[2]]],
	"card_enemy_mimic_egg":["rocks","autumn",["pre","mimic_egg",[[2,1],[2,3]]]],
	"card_enemy_bramble_wall":["pass","autumn",["pre","bramble_wall",[[2,2]]]],
	"card_enemy_blood_cauldron":["volcano","autumn",["pre","blood_cauldron",[[1,1],[1,3]]]],
	"card_enemy_hive_nest":["gale6","autumn",["pre","hive_nest",[[1,1],[1,4]]]],
	"card_enemy_leech_vine":["bog","autumn",["pre","leech_vine",[[2,2]]]],
	"card_enemy_imp_burrow":["four","autumn",["pre","imp_burrow",[[1,0],[1,4]]]],
	"card_enemy_berserk_blood":["volcano","autumn",["van","pouch_beast",[1,3]]],
	"card_enemy_corrosive_bile":["causeway","autumn",["van","fishbeak",[2]]],
	"card_enemy_pack_ambush":["ponds","autumn",["van","tusk_boar",[1,3]]],
	"card_enemy_devouring_maw":["twin","autumn",["van","pouch_beast",[1,3]]],
	"card_enemy_wing_gust":["gale6","autumn",["van","hooknose_flyer",[2,3]]],
	"card_enemy_feral_mutation":["plain6","autumn",["van","thorn_hound",[2,3]]],
	"card_enemy_swarm_eruption":["reeds6","autumn",["van","parasite_mite",[1,4]]],
}

static func is_elite(foe: String) -> bool:
	return foe in ELITES

# Lanes, season and one battle mutator (terrain + the foe's signature) for this foe; {} for bosses.
static func field(foe: String) -> Dictionary:
	if not FOES.has(foe): return {}
	var entry: Array = FOES[foe]
	var map: Dictionary = MAPS[entry[0]]
	var rows := int(map.get("rows",5))
	var mut := {}
	for key: String in ["water_lanes","water_cols","water_cells","wind_lanes","wind_left_lanes","rune_cells","portals","mud_cells","lava_cells","slope","sluice","eruption","wind_shift","gusts","storm","blizzard"]:
		if map.has(key): mut[key] = map[key].duplicate(true)
	if map.has("fog"): mut.fog = int(map.fog)
	if map.has("fog_drift"): mut.fog_drift = true
	if map.has("blocked"): mut.blocked_cells = map.blocked.duplicate(true)
	var mech: Array = entry[2]
	match String(mech[0]):
		"pre": mut.enemy_buildings = mech[2].map(func(c: Array) -> Array: return [c[0],c[1],mech[1]])
		"pulse": mut.periodic_spell = {"interval":float(mech[2]),"kind":mech[1]}
		"grow": mut.periodic = {"interval":float(mech[2]),"kind":mech[1],"min_col":5,"max_col":7}
		"van": mut.enemy_units = mech[2].map(func(lane: int) -> Array: return [2,lane,mech[1]])
	var lanes: Array = map.get("lanes",range(rows))
	return {"map":entry[0],"name":String(map.name),"rows":rows,"lanes":lanes,"season":String(entry[1]),"mutator":mut,"mech":mech}

# Rules per battle (使用者 2026-11-22：同一關不要疊加太多機制，開戰前要有足夠提示).
# The foe's signature and the slot's own twist always stay; the map's features fill what is left of the
# budget in order of importance, and the season's rule comes last (otherwise the season is scenery only).
const BUDGET := {"battle":2,"elite":3}

# Everything one battle will carry, already trimmed: {"name","rows","lanes","season","season_rule",
# "mutator","rules":[[名稱, 說明], …],"map":id}. {} for a boss (bosses keep their own twist only).
static func plan(foe: String, slot_kind: String = "battle", slot_mut: Dictionary = {}) -> Dictionary:
	var f := field(foe)
	if f.is_empty(): return {}
	var MapMech = preload("res://map_mech.gd")
	var Season = preload("res://season.gd")
	var B = preload("res://balance.gd")
	var budget: int = int(BUDGET.get(slot_kind,2))
	var rules: Array = []
	var mech: Array = f.mech
	var cname := String(B.CARDS.get(mech[1],{}).get("name",mech[1]))
	match String(mech[0]):
		"pre": rules.append(["敵方預築","開局已蓋好 %d 座%s。" % [mech[2].size(),cname]])
		"pulse": rules.append(["定時%s" % cname,"敵方約每 %d 秒施放一次%s。" % [int(mech[2]),cname]])
		"grow": rules.append(["冒出%s" % cname,"敵方半場約每 %d 秒冒出一座%s。" % [int(mech[2]),cname]])
		"van": rules.append(["先行壓境","開局已有%s從 %d 路出發（費用從敵方開局金幣扣除）。" % [cname,mech[2].size()]])
	if not slot_mut.is_empty(): rules.append(["異變：%s" % String(slot_mut.get("name","")),String(slot_mut.get("desc",""))])
	var room: int = maxi(0,budget-rules.size())
	# The slot's twist may already flood or wall the field: those count against the map's features.
	var mut: Dictionary = MapMech.trim(f.mutator,room)
	for g: String in MapMech.groups_in(mut):
		rules.append(MapMech.group_line(mut,g))
	var season_rule: bool = rules.size() < budget and Season.SEASONS.has(String(f.season))
	if season_rule: rules.append(["季節：%s" % Season.label(String(f.season)),Season.rule_text(String(f.season))])
	var out := f.duplicate(true)
	out.mutator = mut
	out.season_rule = season_rule
	out.rules = rules
	out.budget = budget
	return out

# Errors for quick_test: every minion has a field, every map, season and card is real.
static func validate() -> Array[String]:
	var B = preload("res://balance.gd")
	var Rogue = load("res://roguelike_catalog.gd")
	var Season = preload("res://season.gd")
	var errors: Array[String] = []
	for foe: String in Rogue.MINIONS:
		if not FOES.has(foe): errors.append("minion without a battlefield: "+foe)
	for foe: String in FOES:
		if not Rogue.MINIONS.has(foe): errors.append("battlefield for unknown minion: "+foe)
		var e: Array = FOES[foe]
		if not MAPS.has(e[0]): errors.append(foe+": unknown map "+str(e[0]))
		if not Season.valid(String(e[1])) or String(e[1]) == "summer": errors.append(foe+": season must be spring, autumn or winter")
		var mech: Array = e[2]
		var kind := String(mech[1])
		if not B.CARDS.has(kind): errors.append(foe+": unknown card "+kind)
		else:
			var want: String = {"pre":"building","grow":"building","pulse":"spell","van":"unit"}.get(String(mech[0]),"")
			if want.is_empty() or B.CARDS[kind].type != want: errors.append(foe+": %s needs a %s card, got %s" % [mech[0],want,kind])
		var f := field(foe)
		if not f.is_empty() and String(mech[0]) == "van":
			for lane in mech[2]:
				if not lane in f.lanes: errors.append(foe+": vanguard on a closed lane "+str(lane))
		if not f.is_empty() and String(mech[0]) == "pre":
			for c in mech[2]:
				if not c[1] in f.lanes: errors.append(foe+": building on a closed lane "+str(c))
	for foe: String in ELITES:
		if not Rogue.MINIONS.has(foe): errors.append("unknown elite "+foe)
		if elite_trait(foe).is_empty(): errors.append("elite without a trait "+foe)
	for tier: int in [2,3]:
		if ELITES.filter(func(k: String) -> bool: return Rogue.MINIONS.has(k) and Rogue.MINIONS[k].tier == tier).size() < 7: errors.append("too few tier %d elites" % tier)
	return errors
