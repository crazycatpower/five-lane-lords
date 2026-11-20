extends RefCounted
const L = preload("res://layout.gd")
const START_INK := 25.0 # producer 2026-10-29 (was 10)
const MAX_INK := 50.0
# 金幣怪物 stages: [min gold, bodies, hp, damage, interval, speed], all on TIERS. Each row is the tier
# combination whose cost-model value (docs/數值檔次.md) is closest to 100% of the gold paid; one more coin
# never lowers a stat except when it adds a body.
const GOLD_MONSTER_STAGES := [
	[1,1,130.0,36.0,1.9,36.0],[2,1,210.0,36.0,1.9,36.0],[3,1,350.0,36.0,1.9,36.0],[4,1,350.0,50.0,1.9,36.0],
	[5,1,560.0,50.0,1.9,36.0],[6,1,560.0,50.0,1.9,50.0],[7,1,560.0,50.0,1.9,65.0],[8,1,560.0,50.0,1.9,90.0],
	[9,1,560.0,50.0,1.4,90.0],[10,1,560.0,50.0,1.1,90.0],[11,1,560.0,50.0,0.85,90.0],[12,1,560.0,50.0,0.65,90.0],
	[13,1,560.0,70.0,0.65,90.0],[14,1,560.0,95.0,0.65,90.0],
	[16,2,900.0,70.0,1.4,36.0],[17,2,900.0,70.0,1.1,36.0],[19,2,900.0,70.0,0.85,36.0],[21,2,900.0,95.0,0.85,36.0],
	[24,2,900.0,95.0,0.85,50.0],[27,2,900.0,95.0,0.85,65.0],[30,2,900.0,95.0,0.65,65.0],
	[32,3,900.0,130.0,1.4,50.0],[35,3,900.0,130.0,1.4,65.0],[38,3,900.0,130.0,1.1,65.0],
	[41,4,900.0,130.0,1.4,50.0],[43,5,900.0,70.0,1.9,90.0],[46,5,900.0,95.0,1.9,90.0],[50,5,900.0,95.0,1.4,90.0],
]
const BASE_INTERVAL := 2.0 # +1 ink every 2 s = 0.5 ink per second
const FARM_INTERVAL := 20.0
const FARM_START := 3.0
const FARM_DROP := 4.0 # a farm gives +4 every 20 s (every 10 s while cultivated)
const FARMER_HEAL := 100.0 # each cultivation also repairs the farm by this much
const START_FARMS := [Vector2i(0,1),Vector2i(0,3)] # both sides begin with these two farms (lanes II and IV, back column; mirrored for blue)
const CULTIVATE_TIME := 1.5
const BOOST_TIME := 15.0
const PLACE_JITTER := 16.0 # units are drawn up to this many px above/below their lane line (looks only)
const MELEE_RANGE := 118.0 # 1 cell: anything that reaches no further is melee (no anti-air, full gate damage)
const RANGED_MIN := 236.0 # 2 cells: thrown, sprayed and shot attacks start here
const CELL_WIDTH := 118.0 # ranges are counted in cells of this width
const UNIT_BODY_RADIUS := 12.0 # baseline collision radius; attack range extends from body edge to target edge
const BUILDING_BODY_RADIUS := 20.0
const LORD_BODY_RADIUS := 22.0
const GATE_HP := 900.0 # hp tier A in every mode (lowered two tiers from SS 3000)
const GATE_ARMOR := 0.0 # flat gate armor removed; gates rely on troops, buildings, lords (and ranged hits still deal 50%)
# Broken walls permit immediate passage; kept at zero for legacy readers.
const RUBBLE_TIME := 0.0
# No crowns, castle HP or time limit: the first enemy soldier to walk through a broken gate wins.
# Ink speeds up over time so matches still end (starts at x1.5).
const START_GOLD := 1.5
const RAMP_1 := 180.0 # 正午 starts at 3:00 (gold and cooldowns x2.0)
const NOON_GOLD := 2.0
const RAMP_2 := 270.0 # 黃昏 starts at 4:30 (gold and cooldowns x2.5)
const DUSK_GOLD := 2.5
# 一日戰役: 白天 3 分鐘 (x1.5) -> 正午 1.5 分鐘 (x2) -> 黃昏 1.5 分鐘 (x2.5) -> 夜晚 3 分鐘 (x3，城門持續掉血) -> 天亮 (9:00).
# gates (3000) two AIs could trade blows for twenty minutes without one gate falling, so at
# nightfall every standing gate on both sides starts to crumble, twice as fast each minute:
# untouched gates are gone 2:05 into the night and every match ends in a storming.
const NIGHT_START := 360.0 # night falls at 6:00
const NIGHT_GOLD := 3.0 # gold and card cooldowns x3 at night (after x1.5, x2 and x2.5): the last push outgrows the defence
const NIGHT_DECAY := 15.0 # gate hp lost per second during the first minute of night
const NIGHT_STEP := 60.0 # the decay doubles every this many seconds
# Two turtling decks could still hold five open gateways for good, so the day has an end: at dawn
# the side holding more land (territory cells) wins; level means a draw.
const DAWN := 540.0 # 9:00
# Gates never shoot back (producer decision 2026-10-29): defence is the lord, troops, buildings and spells.
const ARROW_TIME := 0.35
const AI_SPELL_LEAD := 24.0 # Fixed lead; no target tracking or velocity estimation.
const SPELL_DELAY := 0.4
const LORD_RANGE := 177.0 # 1.5 cells: melee lords reach half a cell past a long weapon (2026-11-19)
const LORD_RANGED_RANGE_MED := 295.0 # 2.5 cells (tier B), casters and skirmishers
const LORD_RANGED_RANGE_FAR := 413.0 # 3.5 cells (tier S): 法師領主 (and ranged 小怪領主 whose card shoots 2.5+ cells)
# Lords stay behind the farms (producer 2026-10-29): they only move within this many px of the
# grid's back edge (the back farm column is centred 59 px in), so raids on farms are not free to stop.
const LORD_ZONE_DEPTH := 40.0
const LORD_INTERVAL := 0.65 # interval tier B (was 0.6, off the tier table; 2026-11-09)
const LORD_RANGED_INTERVAL := 1.1 # interval tier D for all ranged lords (E 1.4 -> D 1.1 on 2026-11-19)
const LORD_REGEN_DELAY := 6.0
const LORD_REGEN := 5.0 # +2 base regen/s for all lords (was 3.0)
const LORD_RETREAT_BELOW := 0.25 # retreat to the castle under this share of HP...
const LORD_RETURN_ABOVE := 0.45 # ...and come back above this one (unless a gate is being stormed)
const LORD_RESPAWN := 12.0
const AI_TICK := 0.5
const LORD_HYSTERESIS := 1.5
# Costs run 1..30 (producer decision 2026-10-29). "role" is the card's job, shown on the card face.
# Buildings never expire on their own (producer decision 2026-10-29); they stay until destroyed.
# Speeds differ too: mob 60 (rush) ... knight and ram 22; legion members keep their own speeds.
# Troop counts vary widely on purpose (1 to 12) so headcount itself sets a card apart.
# Most troop cards are bulk buys (producer 2026-10-29): costlier, but more troops, so each troop is a bit cheaper.
# Unit cards may carry "members" ([kind, count, px behind the front]) to field a mixed legion,
# and "spread": true to deploy "count" troops in each of three adjacent lanes.
# "cooldown": seconds a card must wait after it enters the hand before it can be played (0..60).
const CARDS := {
	"mule_cart":{"name":"騾馬貨車","role":"運貨·經濟","type":"unit","cost":5,"cooldown":10.0,"count":1,"hp":350.0,"damage":20.0,"interval":1.9,"range":0.0,"speed":27.0,"expansion":true,"shuttle":true,"shuttle_base":1.0,"shuttle_step":2.0,"shuttle_rest":3.0,"shuttle_loot":3.0,"ai":["no_defend"]},
	"hook_collector":{"name":"鉤鐮收債人","role":"收債·近戰","type":"unit","cost":9,"cooldown":15.0,"count":2,"hp":210.0,"damage":70.0,"interval":1.1,"range":118.0,"speed":50.0,"expansion":true,"kill_income":1.0,"attack_style":"heavy"},
	"twin_gambler":{"name":"雙刃賭徒","role":"賭命·騷擾","type":"unit","cost":6,"cooldown":10.0,"count":2,"hp":130.0,"damage":36.0,"interval":0.65,"range":59.0,"speed":65.0,"expansion":true,"damage_roll":["E","A"]},
	# Faction core payoffs (2026-11-18, core_cards.gd).
	"spell_tide_magus":{"name":"咒潮法師","role":"施法·成長","faction":"magic","series":"magic","type":"unit","footprint":[2,1],"members":[["spell_tide_magus",1,45.0],["ward_guard",1,0.0]],"art":["spell_tide_magus","ward_guard"],"cost":14,"cooldown":15.0,"count":1,"hp":560.0,"damage":70.0,"interval":1.4,"range":354.0,"speed":36.0,"projectile":true,"attack_style":"cast","spell_stacks":5},
	"thorn_mother":{"name":"荊棘母獸","role":"反傷·光環","faction":"beast","series":"beast","type":"unit","footprint":[2,3],"formation":"t_front","members":[["thorn_mother",1,45.0],["pouch_beast",3,0.0]],"art":["thorn_mother","pouch_beast"],"cost":14,"cooldown":25.0,"count":1,"hp":1500.0,"damage":70.0,"interval":1.4,"range":59.0,"speed":36.0,"body_radius":28.0,"attack_style":"heavy","thorns":70.0,"thorns_aura":36.0,"radius":150.0},
	# 金幣怪物 (2026-11-17): "pay_all" spends the whole purse; the stats below are the 1-coin stage,
	# GOLD_MONSTER_STAGES gives every other amount (gold_monster.gd).
	"gold_monster":{"name":"金幣怪物","role":"傾囊·成長","type":"unit","cost":1,"cooldown":15.0,"count":1,"hp":130.0,"damage":36.0,"interval":1.9,"range":59.0,"speed":36.0,"pay_all":true},
	"gatebreaker":{"name":"破門錘手","role":"破門·攻城","type":"unit","cost":7,"cooldown":15.0,"count":1,"hp":560.0,"damage":95.0,"interval":1.4,"range":59.0,"speed":36.0,"expansion":true,"structure_mult":3.0,"attack_style":"heavy"},
	"disgraced_lancer":{"name":"叛逃槍騎","faction":"normal","role":"衝刺·近戰","type":"unit","footprint":[1,2],"cost":12,"cooldown":15.0,"count":2,"hp":350.0,"damage":70.0,"interval":1.1,"range":118.0,"speed":65.0,"expansion":true,"charge":true},
	"runaway_thrall":{"name":"逃亡血奴","faction":"dark","role":"弒主·騷擾","type":"unit","footprint":[2,3],"formation":"v_wide","cost":5,"cooldown":10.0,"count":3,"hp":130.0,"damage":36.0,"interval":0.85,"range":59.0,"speed":65.0,"expansion":true,"bonus_vs":{"dark":2.0}},
	"renegade_artificer":{"name":"叛逃工匠","faction":"magic","role":"重拳·暈眩","type":"unit","cost":7,"cooldown":15.0,"count":1,"hp":350.0,"damage":140.0,"interval":1.4,"range":59.0,"speed":36.0,"expansion":true,"area_damage":140.0,"radius":37.0,"blast":"cell","stun_on_hit":0.5,"attack_style":"heavy"},
	"oathless_imp":{"name":"無誓鬼","faction":"beast","role":"死撐·騷擾","type":"unit","cost":5,"cooldown":10.0,"count":2,"hp":350.0,"damage":50.0,"interval":0.85,"range":59.0,"speed":65.0,"expansion":true,"last_stand":true},
	"assassin":{"name":"刺客","role":"潛行·衝鋒","type":"unit","cost":3,"cooldown":20.0,"count":1,"hp":130.0,"damage":130.0,"interval":0.85,"range":59.0,"speed":90.0,"expansion":true,"stealth":true,"hits":"units","charge":true},
	"vampire_hunter":{"name":"吸血鬼獵人","role":"獵殺·亡者","type":"unit","footprint":[2,1],"cost":14,"cooldown":10.0,"count":2,"hp":210.0,"damage":50.0,"interval":1.1,"range":354.0,"speed":36.0,"expansion":true,"projectile":true,"bonus_vs":{"dark":2.0},"attack_style":"bow"},
	"old_witch":{"name":"老巫婆","role":"毒蝕·範圍","type":"unit","cost":4,"cooldown":10.0,"count":1,"hp":210.0,"damage":20.0,"area_damage":20.0,"radius":75.0,"blast":"cross","interval":1.9,"range":236.0,"speed":36.0,"expansion":true,"projectile":true,"dot_damage":20.0,"dot_interval":1.0,"dot_ticks":2,"attack_style":"cast","ai":["no_defend","hold"]},
	"monster_hunter":{"name":"怪物獵人","role":"獵殺·魔物","type":"unit","cost":12,"cooldown":15.0,"count":2,"hp":350.0,"damage":70.0,"interval":1.1,"range":118.0,"speed":50.0,"expansion":true,"bonus_vs":{"beast":2.0}},
	"spellbreaker":{"name":"破法者","role":"抗法·獵殺","type":"unit","cost":8,"cooldown":15.0,"count":2,"hp":350.0,"damage":50.0,"interval":1.1,"range":59.0,"speed":50.0,"expansion":true,"spell_resist":0.5,"bonus_vs":{"magic":2.0},"attack_style":"heavy"},
	"powder_barrel":{"name":"炸藥桶","role":"陷阱·爆破","type":"building","ai":["defend_building"],"cost":7,"cooldown":15.0,"hp":80.0,"expires":-1.0,"trap":"blast","charges":1,"trigger_radius":26.0,"radius":100.0,"blast":"square","explosion_damage":600.0},
	"pallbearer":{"name":"抬棺僕","role":"抬棺·開棺","faction":"dark","series":"dark","type":"unit","footprint":[2,3],"formation":"t_back","members":[["pallbearer",1,0.0],["skeleton",3,45.0]],"art":["pallbearer","skeleton"],"cost":8,"cooldown":15.0,"count":1,"hp":560.0,"damage":36.0,"interval":1.1,"range":59.0,"speed":36.0,"expansion":true,"on_death_spawn":["skeleton",3],"attack_style":"heavy"},
	"mourning_maid":{"name":"喪鐘侍女","role":"鐘聲·遲緩","faction":"dark","series":"dark","type":"unit","cost":2,"cooldown":10.0,"count":1,"hp":210.0,"damage":36.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"support":"slow","radius":100.0,"period":3.0,"duration":3.0,"attack_style":"cast","ai":["no_defend"]},
	"corpse_stitcher":{"name":"縫屍匠","role":"斂屍·召喚","faction":"dark","series":"dark","type":"unit","footprint":[2,3],"formation":"t_front","members":[["corpse_stitcher",1,45.0],["skeleton",3,0.0]],"art":["corpse_stitcher","skeleton"],"cost":11,"cooldown":15.0,"count":1,"hp":560.0,"damage":50.0,"interval":1.4,"range":236.0,"speed":50.0,"expansion":true,"ally_death_spawn":"skeleton","stitch_any_team":true,"stitch_count":2,"stitch_heal":50.0,"radius":150.0,"stitch_cooldown":1.5},
	"blood_attendant":{"name":"血誓侍從","role":"吸血·近戰","faction":"dark","series":"dark","type":"unit","cost":9,"cooldown":15.0,"count":2,"hp":350.0,"damage":70.0,"interval":1.1,"range":59.0,"speed":50.0,"expansion":true,"lifesteal":0.3},
	"funeral_cottage":{"name":"殯儀小屋","role":"送葬·經濟","faction":"dark","series":"dark","type":"building","cost":1,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"death_income":1.0,"death_charge":2.0,"period":1.5,"radius":290.0},
	"sleepless_belfry":{"name":"不眠鐘樓","role":"驚醒·淨化","faction":"dark","series":"dark","type":"building","cost":2,"cooldown":20.0,"hp":900.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"support":"cleanse","duration":2.4,"support_amount":50.0,"on_death_spawn":["skeleton",3],"radius":210.0,"period":2.4},
	"blood_altar":{"name":"血誓祭壇","role":"獻血·戰祭","faction":"dark","series":"dark","type":"building","cost":14,"cooldown":25.0,"hp":1500.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"support":"tithe","radius":150.0,"tithe_dps":20.0,"tithe_goal":100.0,"tithe_gold":6.0,"tithe_buff_sec":4.0},
	"borrowed_bones":{"name":"借骨","role":"借屍·骨爆","faction":"dark","series":"dark","type":"spell","cost":5,"cooldown":10.0,"radius":100.0,"shape":[2,2],"summon_count":4,"summon_life":20.0,"return_blast":55.0,"blast":"cross"},
	"grave_exchange":{"name":"掘墓換金","role":"掘墓·換金","faction":"dark","series":"dark","type":"spell","cost":6,"cooldown":10.0,"radius":100.0,"shape":[2,2],"refund":0.5,"skeletons":2},
	"mourning_shroud":{"name":"喪禮披風","role":"護命·支援","faction":"dark","series":"dark","type":"spell","cost":1,"cooldown":15.0,"radius":100.0,"shape":[2,2],"duration":10.0},
	"sealed_coffin":{"name":"封棺","role":"封棺·控場","faction":"dark","series":"dark","type":"spell","cost":2,"cooldown":10.0,"radius":100.0,"shape":[2,2],"root":8.0},
	"arquebusier":{"name":"行軍火繩槍兵","role":"火槍·遠程","faction":"normal","type":"unit","footprint":[2,1],"cost":18,"cooldown":15.0,"count":2,"hp":210.0,"damage":130.0,"interval":2.4,"range":413.0,"speed":36.0,"expansion":true,"projectile":true,"attack_style":"bow"},
	"funeral_grenadier":{"name":"喪鐘擲彈使","role":"擲彈·範圍","faction":"dark","series":"dark","type":"unit","cost":10,"cooldown":15.0,"count":1,"hp":210.0,"damage":90.0,"area_damage":90.0,"radius":75.0,"blast":"cross","interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"lob":true,"flight_time":0.8,"attack_style":"throw"},
	"dog_cannon":{"name":"骷髏狗扛砲","role":"集群·砲擊","faction":"dark","series":"dark","type":"unit","footprint":[1,2],"cost":10,"cooldown":25.0,"count":4,"hp":80.0,"damage":35.0,"area_damage":35.0,"radius":52.0,"blast":"row2","interval":1.9,"range":354.0,"speed":90.0,"expansion":true,"lob":true,"flight_time":0.9,"attack_style":"throw"},
	"orrery_walker":{"name":"星儀行砲","role":"光束·貫穿","faction":"magic","series":"magic","type":"unit","footprint":[2,2],"formation":"v_front","members":[["orrery_walker",1,45.0],["ward_guard",2,0.0]],"art":["orrery_walker","ward_guard"],"cost":30,"cooldown":25.0,"count":1,"hp":350.0,"damage":95.0,"interval":1.4,"range":413.0,"speed":36.0,"expansion":true,"mechanical":true,"projectile":true,"pierce":true,"pierce_range_multiplier":1.5,"attack_style":"cast"},
	"seal_bearer":{"name":"符印輪轂師","role":"扇射·三路","faction":"magic","series":"magic","type":"unit","footprint":[2,1],"members":[["seal_bearer",1,45.0],["ward_guard",1,0.0]],"art":["seal_bearer","ward_guard"],"cost":14,"cooldown":15.0,"count":1,"hp":210.0,"damage":50.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"splash":"column","attack_style":"cast"},
	"imp_bomb_runner":{"name":"小鬼炸彈兵","role":"自爆·拆建","faction":"beast","type":"unit","cost":8,"cooldown":10.0,"count":2,"hp":210.0,"damage":370.0,"area_damage":370.0,"radius":100.0,"blast":"square","interval":1.1,"range":0.0,"speed":90.0,"expansion":true,"suicide_blast":true},
	"macebreaker":{"name":"釘錘破甲兵","role":"破甲·近戰","faction":"normal","type":"unit","footprint":[1,2],"cost":8,"cooldown":15.0,"count":2,"hp":350.0,"damage":70.0,"interval":1.1,"range":59.0,"speed":36.0,"expansion":true,"ignore_armor":true,"attack_style":"heavy"},
	"beekeeper":{"name":"養蜂人","role":"蜂群·毒遲","faction":"normal","type":"unit","cost":5,"cooldown":10.0,"count":1,"hp":210.0,"damage":26.0,"interval":1.9,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"net_slow":2.0,"dot_damage":20.0,"dot_interval":1.0,"dot_ticks":2,"attack_style":"throw"},
	"bellbearer":{"name":"送葬鐘使","role":"療傷·支援","faction":"dark","type":"unit","cost":2,"cooldown":15.0,"count":1,"hp":210.0,"damage":26.0,"interval":1.9,"range":236.0,"speed":36.0,"expansion":true,"projectile":true,"support":"heal","support_amount":26.0,"radius":100.0,"period":2.4,"attack_style":"cast"},
	"shroud_arbalist":{"name":"裹屍弩手","role":"重弩·遠程","faction":"dark","type":"unit","footprint":[2,1],"cost":9,"cooldown":15.0,"count":2,"hp":130.0,"damage":95.0,"interval":1.9,"range":354.0,"speed":36.0,"expansion":true,"projectile":true,"attack_style":"bow"},
	"sigil_weaver":{"name":"符印織師","role":"護盾·支援","faction":"magic","type":"unit","cost":5,"cooldown":10.0,"count":1,"hp":210.0,"damage":36.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"support":"shield","support_amount":70.0,"duration":4.0,"radius":100.0,"period":3.0,"attack_style":"cast"},
	"astrolabe_surveyor":{"name":"星盤測繪師","role":"偵察·遠程","faction":"magic","type":"unit","cost":4,"cooldown":10.0,"count":1,"hp":210.0,"damage":36.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"reveal_radius":210.0,"attack_style":"cast"},
	"bog_troll":{"name":"沼澤巨魔","role":"重裝·再生","faction":"beast","type":"unit","cost":15,"cooldown":25.0,"count":1,"hp":1500.0,"damage":95.0,"interval":1.4,"range":59.0,"speed":36.0,"body_radius":28.0,"expansion":true,"regen_amount":70.0,"period":2.4,"attack_style":"heavy"},
	"tusk_boar":{"name":"獠牙野豬人","role":"衝鋒·破陣","faction":"beast","type":"unit","cost":9,"cooldown":15.0,"count":1,"hp":900.0,"damage":130.0,"interval":1.1,"range":0.0,"speed":65.0,"body_radius":22.0,"expansion":true,"charge":true,"attack_style":"ram"},
	"granary":{"name":"糧倉","role":"儲備·經濟","faction":"normal","type":"building","cost":11,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"store_per_farm":1.0,"store_max":10.0},
	"field_smithy":{"name":"野戰鐵匠鋪","role":"護甲·支援","faction":"normal","type":"building","cost":5,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"support":"armor","support_amount":26.0,"radius":150.0,"period":2.4,"duration":3.0},
	"ossuary":{"name":"藏骨禮拜堂","role":"亡者·召集","faction":"dark","type":"building","cost":1,"cooldown":25.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"spawn_on_build":true,"spawn_kind":"skeleton","spawn_count":2,"period":15.0,"on_death_spawn":["skeleton",4]},
	"soul_well":{"name":"引魂井","role":"治癒·加速","faction":"dark","type":"building","cost":2,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"well_heal_full":true,"radius":150.0,"duration":6.0},
	"observatory":{"name":"星象觀測所","role":"偵察·增程","faction":"magic","type":"building","cost":1,"cooldown":10.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"reveal_radius":210.0,"support":"range","radius":150.0,"period":2.4,"duration":3.0},
	"rune_workshop":{"name":"符文工坊","role":"建築·修復","faction":"magic","type":"building","cost":6,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"support":"repair","support_amount":50.0,"radius":150.0,"period":2.4},
	"monster_hatchery":{"name":"巨獸孵巢","role":"孵育·產兵","faction":"beast","type":"building","cost":8,"cooldown":40.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"spawn_kind":"pouch_beast","spawn_count":1,"period":20.0},
		"glutton_nest":{"name":"貪食巢穴","role":"吞噬·經濟","faction":"beast","series":"beast","type":"building","cost":4,"cooldown":25.0,"hp":350.0,"expires":-1.0,"trigger_radius":26.0,"radius":150.0,"windup":1.0,"bite_duration":0.5,"digest_time":10.0,"digest_per_gold":3.0,"gold_first":60.0,"gold_step":12.0,"gold_bonus":2,"ally_feed_mult":2.0,"chew_period":2.4,"chew_heal":20.0,"bite_cap":900.0,"bite_max":4},
	"war_lodge":{"name":"獠牙戰寨","role":"集結·加速","faction":"beast","type":"building","cost":5,"cooldown":20.0,"hp":900.0,"expires":-1.0,"body_radius":24.0,"expansion":true,"ai":["defend_building"],"support":"haste","radius":150.0,"period":2.4,"duration":3.0},
	"halberdier":{"name":"長戟兵","role":"長柄·列陣","faction":"normal","type":"unit","footprint":[1,2],"cost":15,"cooldown":10.0,"count":4,"hp":350.0,"damage":50.0,"interval":1.1,"range":118.0,"speed":50.0,"expansion":true,"art":"militia"},
	"ballista_tower":{"name":"重弩塔","role":"直線·破甲","faction":"normal","type":"building","cost":21,"cooldown":20.0,"hp":900.0,"expires":-1.0,"expansion":true,"ai":["guard","defend_building","obstacle"],"range":472.0,"damage":70.0,"interval":1.4,"ignore_armor":true,"lane_shooter":true,"bolt_speed":540.0,"reach":{"lane":4}},
	"supply_depot":{"name":"軍需補給站","role":"減費·後勤","faction":"normal","type":"building","cost":2,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"depot_refund":1.0},
	"counter_charge":{"name":"反衝號令","role":"震退·反攻","faction":"normal","type":"spell","cost":11,"cooldown":15.0,"radius":290.0,"shape":[3,3],"expansion":true,"expansion_spell":true,"enemy_damage":140.0,"knockback":90.0,"stun_on_hit":1.0,"rally_haste_sec":6.0,"grant_charge":true,"charge_stun":0.5,"ai":["defend_spell","wave_spell"]},
	"flaming_pitch":{"name":"燃燒火油","role":"火海·持續","faction":"normal","type":"spell","cost":10,"cooldown":15.0,"radius":100.0,"shape":[2,2],"expansion":true,"expansion_spell":true,"duration":8.0,"tick_damage":35.0,"ai":["defend_spell","wave_spell"]},
	"rune_sentinel":{"name":"符文哨衛","role":"巡邏·抗魔","faction":"magic","type":"unit","footprint":[1,2],"cost":3,"cooldown":15.0,"count":2,"hp":560.0,"damage":50.0,"interval":1.4,"range":59.0,"speed":36.0,"expansion":true,"patrol":true,"spell_resist":0.5,"art":"arcane_golem"},
	"ward_guard":{"name":"結界護衛","role":"護衛·抗魔","faction":"magic","series":"magic","type":"unit","summon_only":true,"cost":2,"cooldown":0.0,"count":1,"hp":900.0,"damage":50.0,"interval":1.4,"range":59.0,"speed":36.0,"expansion":true,"construct":true,"ward_share":0.5,"ward_radius":100.0},
	"ward_phalanx":{"name":"結界方陣","role":"軍陣·散射","faction":"magic","series":"magic","type":"unit","footprint":[2,3],"formation":"u_five","members":[["ward_guard",3,0.0],["prism_mage",2,45.0]],"art":["ward_guard","prism_mage"],"cost":21,"cooldown":20.0},
	"prism_mage":{"name":"稜鏡法師","role":"散射·偵查","faction":"magic","type":"unit","cost":7,"cooldown":15.0,"count":1,"hp":210.0,"damage":55.0,"area_damage":55.0,"radius":75.0,"blast":"cross","interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"reveal_radius":210.0,"attack_style":"cast","art":"astrolabe_surveyor"},
	"aether_hound":{"name":"乙太獵犬","role":"集群·獵法","faction":"magic","type":"unit","footprint":[1,2],"cost":7,"cooldown":10.0,"count":6,"hp":80.0,"damage":26.0,"interval":0.85,"range":59.0,"speed":90.0,"expansion":true,"phase":true,"bonus_vs":{"magic":1.5},"ai":["raid"],"art":"chimera"},
	"spell_mirror":{"name":"魔鏡術士","role":"反彈·遠程","faction":"magic","type":"unit","cost":3,"cooldown":15.0,"count":1,"hp":210.0,"damage":36.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"reflect_damage":50.0,"attack_style":"cast"},
	"mana_battery":{"name":"蓄能魔池","role":"蓄能·爆金","faction":"magic","type":"building","cost":3,"cooldown":20.0,"hp":350.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"max_charges":5,"gold_per_charge":2.0,"radius":100.0,"blast":"square","area_damage":90.0},
	"warp_beacon":{"name":"折躍信標","role":"脈衝·推敵","faction":"magic","type":"building","cost":1,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building","obstacle"],"range":236.0,"period":6.0,"pushback":177.0,"area_damage":55.0,"pulse_stun":1.0},
	"mana_drain":{"name":"魔力吸取","role":"電擊·抽金","faction":"magic","type":"spell","cost":6,"cooldown":15.0,"radius":150.0,"shape":[1,5],"expansion":true,"expansion_spell":true,"enemy_damage":90.0,"drain_gold_per_hit":1.0,"drain_gold_max":5.0,"ai":["defend_spell","wave_spell"]},
	"phase_shift":{"name":"相位轉移","role":"突進·折躍","faction":"magic","type":"spell","cost":2,"cooldown":10.0,"radius":100.0,"shape":[2,2],"expansion":true,"expansion_spell":true,"phase_shift":40.0,"ai":["wave_spell"]},
	"gravity_well":{"name":"重力井","role":"聚敵·暈眩","faction":"magic","type":"spell","cost":2,"cooldown":15.0,"radius":150.0,"shape":[3,2],"expansion":true,"expansion_spell":true,"pull_center":true,"enemy_damage":90.0,"stun_on_hit":1.0,"ai":["defend_spell","wave_spell"]},
	"mirror_clone":{"name":"鏡像複製","role":"分身·複製","faction":"magic","type":"spell","cost":3,"cooldown":15.0,"radius":100.0,"shape":[2,2],"expansion":true,"expansion_spell":true,"duration":15.0,"ai":["wave_spell"]},
	"parasite_mite":{"name":"寄生蟲群","role":"擊殺·分裂","faction":"beast","type":"unit","footprint":[2,3],"formation":"u_front","cost":6,"cooldown":5.0,"count":3,"hp":130.0,"damage":26.0,"interval":0.85,"range":0.0,"speed":65.0,"expansion":true,"split_on_kill":true},
	"thorn_hound":{"name":"棘刺獵犬","role":"疾跑·反傷","faction":"beast","type":"unit","cost":8,"cooldown":10.0,"count":2,"hp":350.0,"damage":50.0,"interval":0.85,"range":59.0,"speed":90.0,"expansion":true,"thorns":36.0,"art":"tusk_boar"},
	"web_spinner":{"name":"織網畸怪","role":"定身·遠程","faction":"beast","type":"unit","cost":4,"cooldown":10.0,"count":1,"hp":560.0,"damage":50.0,"interval":1.4,"range":295.0,"speed":36.0,"expansion":true,"projectile":true,"root_on_hit":1.5,"attack_style":"cast"},
	"sky_scavenger":{"name":"食腐禿鷲","role":"飛行·食腐","faction":"beast","type":"unit","cost":9,"cooldown":10.0,"count":1,"hp":560.0,"damage":50.0,"interval":1.1,"range":59.0,"speed":120.0,"expansion":true,"flying":true,"scavenger":true,"scavenger_heal":50.0,"radius":150.0},
	"dire_hydra":{"name":"三頭狂蜥","role":"三連·三路","faction":"beast","type":"unit","cost":27,"cooldown":25.0,"count":1,"hp":3000.0,"damage":70.0,"interval":2.4,"range":59.0,"speed":36.0,"body_radius":42.0,"expansion":true,"regen_amount":36.0,"period":2.4,"splash":"column","strikes":3,"three_lane_target":true,"attack_style":"heavy","art":"long_dragon"},
	"mimic_egg":{"name":"擬態怪卵","role":"孵化·爆裂","faction":"beast","type":"building","cost":6,"cooldown":10.0,"hp":350.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"hatch_time":15.0,"ambush_hatch":true,"spawn_kind":"pouch_beast","spawn_count":2,"radius":100.0,"blast":"square","area_damage":140.0},
	"bramble_wall":{"name":"荊棘高牆","role":"阻擋·反傷","faction":"beast","type":"building","cost":7,"cooldown":30.0,"hp":1500.0,"expires":-1.0,"body_radius":26.0,"expansion":true,"ai":["defend_building","obstacle"],"thorns":36.0,"art":"thorn_dragon"},
	"blood_cauldron":{"name":"沸血魔鍋","role":"暴擊·增益","faction":"beast","type":"building","cost":4,"cooldown":20.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"period":4.0,"radius":150.0,"crit_mult":1.5,"support_amount":36.0},
	"hive_nest":{"name":"飛魔巢穴","role":"飛行·產兵","faction":"beast","type":"building","cost":17,"cooldown":25.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"spawn_kind":"hooknose_flyer","spawn_count":1,"period":16.0},
	"leech_vine":{"name":"吸血蔓藤","role":"吸血·防守","faction":"beast","type":"building","cost":7,"cooldown":15.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["guard","defend_building"],"range":236.0,"damage":50.0,"interval":1.4,"lifesteal":0.5,"net_slow":1.5,"reach":{"ahead":[1,2],"rows":1}},
	"imp_burrow":{"name":"小鬼地洞","role":"偷金·產兵","faction":"beast","type":"building","cost":16,"cooldown":30.0,"hp":560.0,"expires":-1.0,"expansion":true,"ai":["defend_building"],"spawn_kind":"bearded_imp","spawn_count":1,"period":20.0,"art":"monster_hatchery"},
	"berserk_blood":{"name":"狂血激發","role":"換血·狂暴","faction":"beast","type":"spell","cost":1,"cooldown":5.0,"radius":210.0,"shape":[3,3],"expansion":true,"expansion_spell":true,"hp_cost_share":0.20,"ai":["wave_spell"]},
	"corrosive_bile":{"name":"腐蝕酸雨","role":"破防·拆建","faction":"beast","type":"spell","cost":6,"cooldown":15.0,"radius":210.0,"shape":[4,4],"expansion":true,"expansion_spell":true,"enemy_damage":90.0,"strip_defences":true,"ai":["defend_spell","wave_spell"]},
	"pack_ambush":{"name":"獸群突襲","role":"衝鋒·伏兵","faction":"beast","type":"spell","cost":4,"cooldown":15.0,"radius":150.0,"shape":[4,1],"expansion":true,"expansion_spell":true,"grant_charge":true,"charge_stun":0.5,"ambush_spawn":["pouch_beast",2],"ai":["wave_spell"]},
	"devouring_maw":{"name":"吞噬巨口","role":"斬首·破陣","faction":"beast","type":"spell","cost":6,"cooldown":15.0,"radius":100.0,"shape":[2,2],"expansion":true,"expansion_spell":true,"maw_targets":4,"maw_damage":1200.0,"ai":["defend_spell","wave_spell"]},
	"wing_gust":{"name":"狂風振翼","role":"擊退·解圍","faction":"beast","type":"spell","cost":2,"cooldown":10.0,"radius":150.0,"shape":[4,3],"expansion":true,"expansion_spell":true,"knockback":236.0,"enemy_damage":55.0,"stun_on_hit":1.0,"anti_air_mult":2.0,"rally_haste_sec":4.0,"ai":["defend_spell","wave_spell"]},
	"feral_mutation":{"name":"野性畸變","role":"膨脹·強化","faction":"beast","type":"spell","cost":5,"cooldown":15.0,"radius":100.0,"shape":[2,2],"expansion":true,"expansion_spell":true,"upgrade_hp":true,"ai":["wave_spell"]},
	"swarm_eruption":{"name":"蟲群爆發","role":"爆裂·寄生","faction":"beast","type":"spell","cost":7,"cooldown":20.0,"radius":150.0,"shape":[3,3],"expansion":true,"expansion_spell":true,"enemy_damage":140.0,"spawn_on_kill":"parasite_mite","spawn_life":12.0,"ai":["defend_spell","wave_spell"]},
	"mana_spring":{"name":"法力湧泉","role":"水晶·湧泉","faction":"magic","series":"magic","type":"spell","cost":7,"cooldown":15.0,"radius":100.0,"shape":[2,2],"heal_fraction":1.0},
	"chain_lightning":{"name":"連鎖閃電","role":"連鎖·彈跳","faction":"magic","series":"magic","type":"spell","cost":8,"cooldown":15.0,"radius":150.0,"shape":[2,2],"bolt_damage":360.0,"hop_radius":150.0,"hops":4},
	"arcane_shield":{"name":"奧術護盾","role":"護盾·支援","faction":"magic","series":"magic","type":"spell","cost":3,"cooldown":10.0,"radius":100.0,"shape":[2,2],"shield":180.0},
	"time_field":{"name":"時空力場","role":"力場·遲緩","faction":"magic","series":"magic","type":"spell","cost":3,"cooldown":10.0,"radius":290.0,"shape":[3,3],"duration":8.0},
	"charge_horn":{"name":"衝鋒號令","role":"號角·衝鋒","faction":"normal","type":"spell","cost":3,"cooldown":5.0,"radius":100.0,"shape":[9,1],"duration":15.0},
	"levy":{"name":"緊急徵召","role":"徵召·守土","faction":"normal","type":"spell","cost":8,"cooldown":5.0,"radius":100.0,"shape":[3,1]},
	"net_hunter":{"name":"投網獵人","role":"投網·纏足","faction":"normal","type":"unit","projectile":true,"cost":6,"cooldown":5.0,"count":2,"hp":130.0,"damage":26.0,"interval":0.85,"range":236.0,"speed":36.0,"net_slow":3.0},
	"watchtower":{"name":"瞭望塔","role":"偵查·增程","faction":"normal","type":"building","cost":3,"cooldown":5.0,"hp":560.0,"expires":-1.0,"radius":290.0},
	"sacrifice":{"name":"獻祭","role":"犧牲·充能","faction":"dark","series":"dark","type":"spell","cost":1,"cooldown":5.0,"radius":100.0,"shape":[2,2],"bite_cap":500.0,"gold_first":30.0,"gold_step":6.0,"charge_per_hp":0.2,"blast_share":0.5,"blast_min":90.0,"blast_max":600.0,"slow_duration":2.0},
	"dread_howl":{"name":"恐懼嚎叫","role":"恐懼·破膽","faction":"dark","series":"dark","type":"spell","cost":2,"cooldown":5.0,"radius":150.0,"shape":[3,2],"duration":5.0,"terror_mult":1.5,"enemy_damage":55.0},
	"mass_grave":{"name":"亂葬坑","role":"死亡·產兵","faction":"dark","series":"dark","type":"building","cost":8,"cooldown":30.0,"hp":350.0,"expires":-1.0,"period":40.0,"spawn_count":3,"death_advance":5.0},
	"blood_tower":{"name":"鮮血塔","role":"儲血·治療","faction":"dark","series":"dark","type":"building","cost":3,"cooldown":30.0,"hp":350.0,"expires":-1.0,"blood_rate":5.0,"blood_per_death":50.0,"heal_rate":50.0,"restart_at":50.0,"blood_max":500.0},
	# 封印祭壇 (2026-11-18): one per side, souls from every troop death, three seals; the last one
	# releases 瘟疫主教 and his 送葬修士 (seal_altar.gd).
	"seal_altar":{"name":"封印祭壇","role":"收魂·封印","faction":"dark","series":"dark","type":"building","cost":1,"cooldown":50.0,"hp":900.0,"expires":-1.0,"unique":true,"no_opening":true,"hold_cooldown":true,"radius":150.0,"soul_per_death":1.0,"seals":[20,40,60],"seal_fear":2.0,"summon":"plague_bishop","escort":["funeral_monk",4]},
	"plague_bishop":{"name":"瘟疫主教","role":"鐘聲·腐土","faction":"dark","series":"dark","type":"unit","summon_only":true,"cost":1,"cooldown":0.0,"count":1,"hp":3000.0,"damage":130.0,"interval":1.4,"range":59.0,"speed":27.0,"body_radius":28.0,"attack_style":"heavy","expansion":true,"support":"slow","radius":150.0,"period":3.0,"duration":3.0,"roar_fear":2.0,"rot_period":2.0,"rot_radius":75.0,"rot_duration":8.0},
	"funeral_monk":{"name":"送葬修士","role":"隨行·治療","faction":"dark","series":"dark","type":"unit","summon_only":true,"cost":1,"cooldown":0.0,"count":1,"hp":210.0,"damage":26.0,"interval":1.9,"range":236.0,"speed":27.0,"expansion":true,"projectile":true,"support":"heal","support_amount":26.0,"radius":100.0,"period":2.4,"attack_style":"cast"},
	"manor_retainer":{"name":"莊園扈從","role":"領地·巡邏","faction":"normal","type":"unit","footprint":[1,2],"patrol":true,"cost":6,"cooldown":10.0,"count":2,"hp":560.0,"damage":70.0,"interval":1.1,"range":59.0,"speed":36.0},
	"axe_thrower":{"name":"投斧手","role":"遠程·破甲","type":"unit","projectile":true,"ignore_armor":true,"cost":9,"cooldown":15.0,"count":1,"hp":350.0,"damage":180.0,"interval":1.9,"range":236.0,"speed":36.0},
	"rolling_boulder":{"name":"巨石滾滾","role":"直線·敵我傷害","type":"spell","rolling":true,"cost":7,"cooldown":15.0,"radius":37.0,"damage":230.0,"building_damage":230.0,"gate_damage":230.0,"roll_speed":240.0},
	"dark_wizard":{"name":"黑暗巫師","role":"高傷·噬魂","faction":"dark","series":"dark","type":"unit","footprint":[2,2],"members":[["dark_wizard",2,45.0],["skeleton",2,0.0]],"art":["dark_wizard","skeleton"],"projectile":true,"soul_bargain":true,"cost":20,"cooldown":25.0,"count":2,"hp":210.0,"damage":130.0,"interval":1.9,"range":354.0,"speed":36.0},
	"summon_trap":{"name":"召喚法陣","role":"陷阱·召獸","faction":"magic","series":"magic","type":"building","ai":["defend_building"],"cost":4,"cooldown":10.0,"hp":80.0,"expires":-1.0,"trap":"summon","charges":3,"trigger_radius":26.0,"radius":52.0,"summon_kind":"chimera","summon_count":1,"summon_blast":90.0,"blast":"cross"},
	"chimera":{"name":"嵌合獸","role":"召喚物·近戰","faction":"magic","series":"magic","type":"unit","summon_only":true,"cost":1,"cooldown":0.0,"count":1,"hp":350.0,"damage":50.0,"interval":0.85,"range":118.0,"speed":65.0},
	"blink_blade":{"name":"閃現劍士","role":"突進·穿陣","type":"unit","footprint":[2,3],"formation":"v_wide","faction":"magic","series":"magic","cost":9,"cooldown":10.0,"count":3,"hp":210.0,"damage":70.0,"interval":0.85,"range":59.0,"speed":65.0,"blink_step":0.25},
	"arcane_golem":{"name":"奧術魔像","role":"重裝·共鳴","type":"unit","faction":"magic","series":"magic","construct":true,"cost":14,"cooldown":25.0,"count":1,"hp":1500.0,"damage":70.0,"interval":1.4,"range":59.0,"speed":27.0,"body_radius":28.0,"resonance":0.1,"resonance_max":0.3,"explosion_damage":140.0,"radius":100.0,"blast":"square","ai":["hold"]},
	"arcane_archer":{"name":"奧術射手","role":"遠程·貫穿","type":"unit","footprint":[2,1],"members":[["arcane_archer",4,45.0],["ward_guard",2,0.0]],"art":["arcane_archer","ward_guard"],"faction":"magic","series":"magic","cost":21,"cooldown":20.0,"count":4,"hp":80.0,"damage":26.0,"interval":1.1,"range":354.0,"speed":36.0,"projectile":true,"pierce":true,"pierce_range_multiplier":2.0},
	"chronomancer":{"name":"時滯術士","role":"控場·暈眩","type":"unit","faction":"magic","series":"magic","cost":25,"cooldown":15.0,"count":1,"hp":560.0,"damage":90.0,"interval":1.4,"range":354.0,"speed":36.0,"area_damage":90.0,"radius":100.0,"blast":"cross","stun_on_hit":1.0},
	"phase_rider":{"name":"相位騎兵","role":"潛行·穿陣","type":"unit","footprint":[2,3],"formation":"v_wide","faction":"magic","series":"magic","cost":11,"cooldown":15.0,"count":3,"hp":210.0,"damage":70.0,"interval":1.1,"range":59.0,"speed":90.0,"phase":true,"ai":["raid"]},
	"artificer":{"name":"工匠","role":"維修·支援","faction":"magic","type":"unit","ai":["no_defend"],"cost":6,"cooldown":10.0,"count":1,"hp":130.0,"damage":20.0,"interval":1.9,"range":59.0,"speed":50.0,"repair_range":118.0,"repair_amount":50.0,"repair_interval":1.9},
	"crystal":{"name":"水晶","role":"耗能·經濟","faction":"magic","type":"building","cost":7,"cooldown":15.0,"hp":350.0,"expires":-1.0,"period":10.0,"max_period":20.0,"income":2.0,"decay_fraction":0.05},
	"teleport_trap":{"name":"傳送法陣","role":"陷阱·轉移","faction":"magic","type":"building","ai":["defend_building"],"cost":4,"cooldown":10.0,"hp":80.0,"expires":-1.0,"trap":"teleport","trigger_radius":26.0,"radius":100.0,"charges":3,"stun_duration":10.0,"slow_duration":10.0},
	"blast_trap":{"name":"爆炸法陣","role":"陷阱·爆破","faction":"magic","type":"building","ai":["defend_building"],"cost":5,"cooldown":10.0,"hp":80.0,"expires":-1.0,"trap":"blast","charges":3,"trigger_radius":26.0,"radius":100.0,"blast":"square","explosion_damage":140.0},
	"arcane_tower":{"name":"祕法塔","role":"範圍·防守","faction":"magic","type":"building","ai":["guard","defend_building","obstacle"],"cost":15,"cooldown":15.0,"hp":350.0,"expires":-1.0,"range":236.0,"interval":1.9,"radius":75.0,"blast":"cross","area_damage":90.0,"reach":{"square":1,"arms":2}},
	# 魔物 (2026-11-06): seven monsters from late-medieval paintings. Special rules live in monster_cards.gd.
	"eyewing_dragon":{"name":"眼翼龍","role":"吼叫·追獵","faction":"beast","series":"beast","type":"unit","cost":14,"cooldown":20.0,"count":1,"hp":1500.0,"damage":95.0,"interval":1.4,"range":118.0,"speed":90.0,"body_radius":28.0,"radius":100.0,"roar_fear":2.5,"roar_period":5.0},
	"belly_eye":{"name":"腹眼魔","role":"偵查·重裝","faction":"beast","series":"beast","type":"unit","cost":7,"cooldown":15.0,"count":1,"hp":1500.0,"damage":50.0,"interval":1.1,"range":59.0,"speed":36.0,"body_radius":28.0,"reveal_radius":150.0},
	"pouch_beast":{"name":"囊腹獸","role":"厚血·前排","faction":"beast","series":"beast","type":"unit","cost":3,"cooldown":5.0,"count":1,"hp":900.0,"damage":36.0,"interval":1.4,"range":0.0,"speed":50.0,"body_radius":22.0,"attack_style":"ram"},
	"fishbeak":{"name":"魚喙怪","role":"換路·追獵","faction":"beast","series":"beast","type":"unit","ai":["raid"],"hunt_nearest":true,"cost":9,"cooldown":10.0,"count":2,"hp":350.0,"damage":70.0,"interval":0.85,"range":59.0,"speed":65.0},
	"bearded_imp":{"name":"鬍子魔","role":"偷金·搗亂","faction":"beast","series":"beast","type":"unit","ai":["raid"],"cost":14,"cooldown":10.0,"count":2,"hp":560.0,"damage":50.0,"interval":1.1,"range":59.0,"speed":65.0,"steal_gold":1.0},
	"hooknose_flyer":{"name":"鉤鼻飛魔","role":"飛行·獵兵","faction":"beast","series":"beast","type":"unit","flying":true,"cost":8,"cooldown":15.0,"count":2,"hp":350.0,"damage":50.0,"interval":0.85,"range":59.0,"speed":120.0},
	"long_dragon":{"name":"長身龍","role":"吐息·穿線","faction":"beast","series":"beast","type":"unit","projectile":true,"pierce":true,"pierce_range_multiplier":1.5,"cost":10,"cooldown":20.0,"count":1,"hp":900.0,"damage":70.0,"interval":1.4,"range":295.0,"speed":50.0,"body_radius":24.0},
	"thorn_dragon":{"name":"骨刺龍","role":"荊棘·反傷","faction":"beast","series":"beast","type":"unit","cost":21,"cooldown":30.0,"count":1,"hp":3000.0,"damage":130.0,"interval":1.9,"range":59.0,"speed":36.0,"body_radius":34.0,"thorns":70.0},

	"barricade":{"name":"木拒馬","role":"耐久·阻擋","type":"building","ai":["defend_building","obstacle"],"cost":3,"cooldown":5.0,"hp":1500.0,"expires":-1.0,"body_radius":26.0},
	"bandit":{"name":"強盜","role":"潛行·突襲","type":"unit","cost":5,"cooldown":20.0,"count":4,"hp":80.0,"damage":26.0,"interval":0.85,"range":59.0,"speed":65.0,"stealth":true},
	"corpse_giant":{"name":"腐屍巨人","role":"重裝·屍爆","faction":"dark","series":"dark","type":"unit","cost":19,"cooldown":60.0,"count":1,"hp":1500.0,"damage":70.0,"interval":1.1,"range":59.0,"speed":27.0,"body_radius":28.0,"burst_step":0.25,"burst_count":4},
	"curse":{"name":"詛咒","role":"死後·為奴","faction":"dark","series":"dark","type":"spell","ai":["defend_spell","wave_spell"],"cost":4,"cooldown":15.0,"radius":290.0,"shape":[3,3]},
	"catapult":{"name":"投石車","role":"遠程·拋射","type":"unit","ai":["hold"],"cost":23,"cooldown":40.0,"count":1,"hp":560.0,"damage":90.0,"area_damage":90.0,"interval":2.4,"range":472.0,"min_range":236.0,"radius":75.0,"blast":"cross","flight_time":0.8,"speed":20.0,"mechanical":true},
	"drummer":{"name":"戰鼓手","faction":"normal","role":"鼓舞·進軍","type":"unit","footprint":[2,3],"formation":"t_front","members":[["drummer",1,45.0],["militia",3,0.0]],"art":["drummer","militia"],"ai":["no_defend"],"cost":8,"cooldown":10.0,"count":1,"hp":210.0,"damage":26.0,"interval":1.1,"range":118.0,"speed":36.0,"inspire_duration":3.0,"inspire_period":10.0},
	"shieldguard":{"name":"盾衛","faction":"normal","role":"盾牆·減傷","type":"unit","footprint":[1,3],"cost":6,"cooldown":5.0,"count":3,"hp":210.0,"damage":26.0,"interval":1.1,"range":59.0,"speed":36.0,"armor":20.0},
	"grave":{"name":"墓碑","role":"死亡·經濟","faction":"dark","series":"dark","type":"building","cost":5,"cooldown":25.0,"hp":560.0,"expires":-1.0,"period":60.0,"income":6.0,"death_advance":5.0},
	"skeleton":{"name":"骷髏兵","role":"廉價·纏鬥","faction":"dark","series":"dark","type":"unit","footprint":[2,1],"cost":8,"cooldown":0.3,"count":6,"hp":50.0,"damage":26.0,"interval":0.65,"range":59.0,"speed":65.0},
	"ghoul":{"name":"食屍鬼","role":"吞噬·成長","faction":"dark","series":"dark","type":"unit","footprint":[1,3],"cost":15,"cooldown":10.0,"count":3,"hp":210.0,"damage":50.0,"interval":0.85,"range":59.0,"speed":65.0,"radius":100.0,"devour_heal":50.0,"max_damage_tier":"A"},
	"necromancer":{"name":"死靈法師","role":"招魂·三路","faction":"dark","series":"dark","type":"unit","footprint":[2,3],"formation":"t_front","members":[["necromancer",1,45.0],["skeleton",3,0.0]],"art":["necromancer","skeleton"],"projectile":true,"cost":15,"cooldown":25.0,"count":1,"hp":210.0,"damage":50.0,"interval":0.85,"range":354.0,"speed":36.0,"summon_interval":10.0,"summon_per_lane":1,"summon_lanes":3},
	"reaper":{"name":"收割者","role":"直劈·三路","faction":"dark","series":"dark","type":"unit","splash":"column","cost":9,"cooldown":15.0,"count":1,"hp":350.0,"damage":130.0,"interval":1.9,"range":118.0,"speed":50.0},
	"raven":{"name":"烏鴉群","role":"飛行·拆田","faction":"dark","series":"dark","type":"unit","footprint":[2,3],"formation":"u_five","hits":"buildings","prefers":"farm","cost":4,"cooldown":10.0,"count":5,"hp":50.0,"damage":20.0,"interval":0.65,"range":59.0,"speed":90.0,"flying":true},
	"plague":{"name":"瘟疫","role":"毒霧·擴散","faction":"dark","series":"dark","type":"spell","ai":["defend_spell"],"cost":5,"cooldown":10.0,"radius":100.0,"shape":[2,2],"tick_damage":35.0,"tick_interval":1.0,"duration":10.0,"spread_duration":3.0,"spread_radius":75.0},
	"bonewall":{"name":"骨牆","role":"阻擋·生骸","faction":"dark","series":"dark","type":"building","ai":["defend_building"],"cost":7,"cooldown":50.0,"hp":3000.0,"expires":-1.0,"body_radius":30.0},
	"farmer":{"name":"農民","role":"經濟·耕田","faction":"normal","type":"unit","ai":["no_defend"],"cost":5,"cooldown":0.3,"count":1,"hp":80.0,"damage":20.0,"interval":1.1,"range":59.0,"speed":50.0},
	"militia":{"name":"民兵隊","faction":"normal","role":"循環·擋路","type":"unit","cost":14,"cooldown":0.3,"count":5,"hp":130.0,"damage":50.0,"interval":0.85,"range":59.0,"speed":50.0},
	"harvest":{"name":"豐收","role":"經濟·爆發","faction":"normal","type":"spell","cost":9,"cooldown":10.0,"radius":100.0,"shape":[2,2]},
	"scarecrow":{"name":"稻草人","role":"誘敵·護田","faction":"normal","type":"building","ai":["guard","defend_building","obstacle"],"cost":4,"cooldown":5.0,"hp":900.0,"expires":-1.0,"body_radius":24.0},
	"mob":{"name":"乾草叉暴民","role":"三路群攻","faction":"normal","type":"unit","ai":["raid"],"cost":16,"cooldown":10.0,"count":4,"spread":true,"footprint":[1,3],"hp":80.0,"damage":26.0,"interval":0.85,"range":59.0,"speed":65.0},
	"hunter":{"name":"獵戶","faction":"normal","role":"遠程輸出","type":"unit","footprint":[1,3],"projectile":true,"cost":19,"cooldown":15.0,"count":3,"hp":80.0,"damage":36.0,"interval":0.85,"range":413.0,"speed":36.0},
	"spearbow":{"name":"槍弓混編","faction":"normal","role":"遠近軍團","type":"unit","cost":22,"cooldown":10.0,"members":[["militia",4,0.0],["hunter",2,45.0]],"footprint":[2,2],"art":["militia","hunter"]},
	"farm":{"name":"農田","role":"經濟·基礎","faction":"normal","type":"building","cost":6,"cooldown":25.0,"hp":350.0,"expires":-1.0},
	"rain":{"name":"箭雨","role":"清群法術","type":"spell","ai":["defend_spell","wave_spell"],"cost":3,"cooldown":5.0,"radius":100.0,"shape":[2,2],"damage":140.0,"building_damage":90.0,"gate_damage":90.0},
	"tower":{"name":"箭樓","faction":"normal","role":"防守","type":"building","ai":["guard","defend_building","obstacle"],"cost":25,"cooldown":15.0,"hp":350.0,"expires":-1.0,"range":236.0,"damage":50.0,"interval":0.65,"reach":{"square":2,"cut_corners":true}},
	"healer":{"name":"草藥婆","role":"支援·治療","faction":"normal","type":"unit","ai":["no_defend","hold"],"cost":7,"cooldown":10.0,"count":1,"hp":210.0,"damage":26.0,"interval":1.1,"range":236.0,"speed":36.0},
	"ox":{"name":"耕牛","role":"衝鋒·拆建","faction":"normal","type":"unit","charge":true,"footprint":[1,2],"ai":["raid"],"cost":13,"cooldown":10.0,"count":2,"hp":350.0,"damage":70.0,"interval":1.9,"range":0.0,"speed":120.0},
	"fire":{"name":"火罐","role":"燒田法術","type":"spell","ai":["defend_spell","wave_spell","raid"],"cost":19,"cooldown":20.0,"radius":100.0,"shape":[2,2],"damage":370.0,"building_damage":600.0,"gate_damage":140.0},
	"knight":{"name":"騎士","role":"主坦","faction":"normal","type":"unit","footprint":[1,2],"cost":18,"cooldown":25.0,"count":2,"hp":900.0,"damage":95.0,"interval":1.9,"range":59.0,"speed":27.0},
	"guard":{"name":"聖堂護衛","role":"重裝軍團","faction":"normal","type":"unit","footprint":[2,2],"cost":26,"cooldown":30.0,"members":[["knight",2,0.0],["healer",2,50.0]],"art":["knight","healer"]},
	"mill":{"name":"磨坊","role":"大型經濟","faction":"normal","type":"building","ai":["obstacle"],"cost":16,"cooldown":40.0,"hp":900.0,"expires":-1.0,"body_radius":24.0},
	"ram":{"name":"攻城槌","faction":"normal","role":"終結·破門","type":"unit","footprint":[2,1],"hits":"buildings","ai":["hold"],"cost":17,"cooldown":60.0,"members":[["ram",1,0.0],["militia",4,40.0]],"art":["ram","militia"],"count":1,"hp":1500.0,"damage":360.0,"interval":2.4,"range":0.0,"speed":20.0,"body_radius":28.0,"mechanical":true}
}

# Behaviour fields a card may carry (read by battle.gd; a new card only needs the fields):
#   "projectile": true            attacks fire an arrow (flight time ARROW_TIME) instead of hitting at once
#   "hits": "buildings"           ignores troops; only attacks buildings, gates, and enemy lords
#   "hits": "units"               ignores buildings; attacks troops, lords and gates (刺客 2026-11-20)
#   "prefers": "farm"             walks to and attacks enemy farms in its lane first
#   "target_rule": "lowest_serial" attacks the lowest serial in reach instead of the nearest
#   "splash": "column"            each hit also strikes every enemy troop in the target's column,
#                                 in this lane and the two next to it (a vertical slash)
#   "flying": true                melee troops and buildings cannot hit it
# AI tags in "ai" (read by enemy_ai.gd):
#   defend_spell   cast on attackers near our gate      wave_spell   cast on enemy clusters while attacking
#   raid           sent at the lane with most enemy farms  guard      one per farm lane, early
#   defend_building placed in front of attackers        obstacle     counts as an enemy wall when choosing a lane
#   no_defend      never sent to stop an attack          hold         only played with gold to spare (or at 45+)
# Each lord's permanent card in the F slot (and its two starting buildings): farmland, except the
# underworld lord, whose tombstones replace farms (producer 2026-10-30). Home cards never go in the
# chosen eight.
static func home_card(lord: String) -> String:
	var data := lord_data(lord)
	return "" if data.get("no_farms",false) else data.get("home_card","farm")

static func is_home_card(kind: String, lord: String = "") -> bool:
	return kind in ["farm","grave","crystal","glutton_nest"]

static func is_economy_building(kind: String) -> bool:
	var d: Dictionary = CARDS.get(kind,{})
	return d.get("type","") == "building" and (is_home_card(kind) or "經濟" in String(d.get("role","")) or kind in ["mana_battery","supply_depot"])

# Factions (producer 2026-10-30): a card with "faction" can only be taken by lords of that faction;
# a card without one is neutral (中立) and fits every deck. Lords carry their faction too.
const FACTIONS := {"normal":"經典","dark":"黑暗","magic":"魔法","beast":"魔物","":"中立"} # internal key "normal" = 經典; "magic" = the mage lord's own cards (producer 2026-11-03)

static func card_faction(kind: String) -> String:
	return CARDS[kind].get("faction","")

# Menu order (producer 2026-11-05). Lords by faction: 經典, 魔法, 黑暗 — the same order as the tabs.
const LORD_MENU_ORDER := ["adventure","lion","iron","harvest","mage","rune","underworld","vampire","beast"]
static func lord_menu_order() -> Array:
	var order: Array = LORD_MENU_ORDER.filter(func(k: String) -> bool: return LORDS.has(k))
	for k: String in LORDS:
		if not k in order: order.append(k) # a new lord shows up at the end until it is placed
	return order

# Card groups for menus: 0 melee, 1 ranged, 2 spell, 3 building. A troop is ranged when it shoots
# (projectile) or reaches 140+ (C); legions count as their leader.
static func card_group(kind: String) -> int:
	var d: Dictionary = CARDS[kind]
	if d.type == "spell": return 2
	if d.type == "building": return 3
	var lead: Dictionary = CARDS.get(d.members[0][0],d) if d.has("members") else d
	return 1 if lead.get("projectile",false) or lead.get("range",MELEE_RANGE) >= RANGED_MIN or d.get("projectile",false) else 0

# Menu sort: melee, ranged, spells, buildings; then cheaper first; then table order.
static func menu_sorted(kinds: Array) -> Array:
	var index := {}
	var i := 0
	for k: String in CARDS:
		index[k] = i
		i += 1
	var result: Array = kinds.duplicate()
	result.sort_custom(func(a: String, b: String) -> bool:
		var ka := [card_group(a),CARDS[a].cost,index[a]]
		var kb := [card_group(b),CARDS[b].cost,index[b]]
		for j: int in range(3):
			if ka[j] != kb[j]: return ka[j] < kb[j]
		return false)
	return result

static func lord_faction(lord: String) -> String:
	return lord_data(lord).get("faction","normal")

static func card_allowed(kind: String, lord: String) -> bool:
	if CARDS[kind].get("unreleased",false): return false
	var faction := card_faction(kind)
	return faction.is_empty() or faction == lord_faction(lord)

static func has_tag(kind: String, tag: String) -> bool:
	return tag in CARDS[kind].get("ai",[])

const CARD_TYPES := ["unit","building","spell"]
# Area effects use the "area_damage" tiers (a spell's "damage" too); troops use "damage".
const AREA_DAMAGE_KEYS := ["damage","building_damage","gate_damage","tick_damage","explosion_damage","enemy_damage"]
const BEHAVIOUR_VALUES := {"hits":["buildings","units"],"prefers":["farm"],"target_rule":["lowest_serial"],"splash":["column"]}
const AI_TAGS := ["defend_spell","wave_spell","raid","guard","defend_building","obstacle","no_defend","hold"]
const NEEDS := {"unit":["count","hp","damage","interval","range","speed"],"building":["hp","expires"],"spell":["radius"]}
const LORD_NEEDS := ["name","role","hp","damage","speed","skill","skill_desc"]

# Everything wrong with the card and lord tables ([] = fine). quick_test.gd fails on any problem and
# the game prints them at start, so a new card with a typo or a missing field is caught at once.
const AUXILIARY_TIERS := {"repair_interval":"interval","repair_range":"range","repair_amount":"damage","regen_amount":"damage","support_amount":"damage","chew_heal":"damage","chew_period":"interval","bolt_damage":"damage","shield":"damage","devour_heal":"damage","reflect_damage":"damage"}

static func validate() -> Array[String]:
	var problems: Array[String] = []
	for kind: String in CARDS:
		var c: Dictionary = CARDS[kind]
		var before := problems.size()
		for key: String in ["name","role","type","cost","cooldown"]:
			if not c.has(key): problems.append("%s: missing %s" % [kind,key])
		var type: String = c.get("type","")
		if not type in CARD_TYPES:
			problems.append("%s: type must be one of %s" % [kind,str(CARD_TYPES)])
			continue
		# One-per-side cards (封印祭壇) may be free: the long cooldown is their price.
		if c.get("cost",0) < (0 if c.get("unique",false) else 1) or c.get("cost",0) > 30: problems.append("%s: cost must be 1-30 (0 allowed for unique cards)" % kind)
		if c.get("cooldown",0.0) < 0 or c.get("cooldown",0.0) > 60: problems.append("%s: cooldown must be 0-60 s" % kind)
		if c.has("members"):
			for group: Array in c.members:
				if not CARDS.has(group[0]) or not CARDS[group[0]].has("hp"): problems.append("%s: legion member %s is not a troop card" % [kind,str(group[0])])
		else:
			for key: String in NEEDS[type]:
				if not c.has(key): problems.append("%s: a %s needs %s" % [kind,type,key])
		for stat: String in TIERS:
			if c.has(stat):
				if stat == "cooldown" and c.get("summon_only",false) and c[stat] == 0: continue
				if stat == "damage" and (c.has("area_damage") or type == "spell"):
					if tier("area_damage",c[stat]).is_empty(): problems.append("%s: damage %s is not an area damage tier value" % [kind,str(c[stat])])
					continue
				if tier(stat,c[stat]).is_empty(): problems.append("%s: %s %s is not a tier value" % [kind,stat,str(c[stat])])
		for key: String in AUXILIARY_TIERS:
			var table: String = AUXILIARY_TIERS[key]
			if c.has(key) and tier(table,c[key]).is_empty(): problems.append("%s: %s is not a %s tier value" % [kind,key,table])
		for key: String in ["radius","spread_radius","trigger_radius","reveal_radius","hop_radius"]:
			if c.has(key) and tier("radius",c[key]).is_empty(): problems.append("%s: %s %s is not a radius tier value" % [kind,key,str(c[key])])
		for key: String in AREA_DAMAGE_KEYS:
			if c.has(key) and (key != "damage" or type == "spell") and tier("area_damage",c[key]).is_empty(): problems.append("%s: %s %s is not an area damage tier value" % [kind,key,str(c[key])])
		for key: String in BEHAVIOUR_VALUES:
			if c.has(key) and not c[key] in BEHAVIOUR_VALUES[key]: problems.append("%s: %s must be one of %s" % [kind,key,str(BEHAVIOUR_VALUES[key])])
		if not c.get("faction","") in FACTIONS: problems.append("%s: faction must be normal, dark, magic, beast or absent (neutral)" % kind)
		for tag in c.get("ai",[]):
			if not tag in AI_TAGS: problems.append("%s: unknown AI tag %s" % [kind,str(tag)])
		for key: String in ["blink_step","resonance","resonance_max","stun_on_hit"]:
			if c.has(key) and (c[key] < 0 or c[key] > (5.0 if key == "stun_on_hit" else 1.0)): problems.append(kind+": invalid "+key)
		for key: String in ["pierce","phase","hunt_nearest","three_lane_target","mechanical","construct"]:
			if c.has(key) and not c[key] is bool: problems.append(kind+": invalid "+key)
		if c.has("strikes") and (not c.strikes is int or int(c.strikes) < 2): problems.append("%s: invalid strikes" % kind)
		if c.has("trap") and not c.trap in ["teleport","blast","summon"]: problems.append(kind+": unknown trap")
		if c.get("trap","") == "summon":
			if not CARDS.has(c.get("summon_kind","")) or c.get("summon_count",0) < 1 or c.get("charges",0) < 1: problems.append(kind+": invalid summon trap")
		if c.has("max_period") and c.max_period < c.get("period",0): problems.append(kind+": invalid production period")
		if c.has("decay_fraction") and (c.decay_fraction <= 0 or c.decay_fraction > 1): problems.append(kind+": invalid decay fraction")
		if c.has("repair_amount") and (c.repair_amount <= 0 or c.get("repair_interval",0) <= 0 or c.get("repair_range",0) <= 0): problems.append(kind+": invalid repair values")
		if c.has("store_per_farm") and (c.store_per_farm <= 0 or c.get("store_max",0.0) <= 0): problems.append(kind+": invalid store values")
		if c.has("on_death_spawn"):
			var spawn: Array = c.on_death_spawn
			if spawn.size() != 2 or not CARDS.has(spawn[0]) or CARDS[spawn[0]].type != "unit" or spawn[1] <= 0: problems.append("%s: invalid on_death_spawn" % kind)
		if c.get("armor",0.0) < 0: problems.append("%s: armor must be nonnegative" % kind)
		if c.has("thorns") and tier("damage",c.thorns).is_empty(): problems.append("%s: thorns %s is not a damage tier value" % [kind,str(c.thorns)])
		if c.has("roar_fear") and (c.roar_fear <= 0 or not c.has("radius")): problems.append(kind+": a roar needs roar_fear > 0 and a radius")
		if c.has("roar_period") and c.roar_period <= 0: problems.append(kind+": invalid roar_period")
		if c.has("steal_gold") and c.steal_gold <= 0: problems.append(kind+": invalid steal_gold")
		if c.has("dot_damage") and (tier("area_damage",c.dot_damage).is_empty() or c.get("dot_interval",0.0) <= 0.0 or int(c.get("dot_ticks",0)) < 1 or (c.has("area_damage") != c.has("radius"))): problems.append(kind+": invalid dot values")
		if c.has("min_range") and (c.min_range < 0 or c.min_range >= c.get("range",0)): problems.append("%s: invalid minimum range" % kind)
		if c.has("blast") and blast_offsets(String(c.blast)).size() <= 1 and String(c.blast) != "cell": problems.append("%s: unknown blast shape %s" % [kind,str(c.blast)])
		if c.has("body_radius") and (c.body_radius <= 0.0 or c.body_radius > 60.0): problems.append("%s: invalid body_radius" % kind)
		# The description reads the fields above, so only build it once they are all present.
		if problems.size() == before and card_description(kind).is_empty(): problems.append("%s: no description" % kind)
	# Shared constants sit on the tier table too (moved here from the old smoke test, 2026-11-09).
	for check: Array in [["HEAL_RADIUS","radius",HEAL_RADIUS],["LORD_RANGE","range",LORD_RANGE],["LORD_RANGED_RANGE_MED","range",LORD_RANGED_RANGE_MED],["LORD_RANGED_RANGE_FAR","range",LORD_RANGED_RANGE_FAR],["LORD_INTERVAL","interval",LORD_INTERVAL],["LORD_RANGED_INTERVAL","interval",LORD_RANGED_INTERVAL],["GATE_HP","hp",GATE_HP],["HEAL_AMOUNT","damage",HEAL_AMOUNT],["HEAL_INTERVAL","interval",HEAL_INTERVAL],["LION_KNIGHT_SPEED","speed",LION_KNIGHT_SPEED]]:
		if tier(check[1],check[2]).is_empty(): problems.append("%s %s is not a %s tier value" % [check[0],str(check[2]),check[1]])
	for kind: String in LORDS:
		for key: String in LORD_NEEDS:
			if not LORDS[kind].has(key): problems.append("lord %s: missing %s" % [kind,key])
		for stat: String in ["hp","damage","speed"]:
			if LORDS[kind].has(stat) and tier(stat,LORDS[kind][stat]).is_empty(): problems.append("lord %s: %s is not a tier value" % [kind,stat])
		var home: String = home_card(kind)
		if not LORDS[kind].get("faction","") in FACTIONS: problems.append("lord %s: invalid faction" % kind)
		# Plain farmland is the fallback: beast uses 貪食巢穴 as its home card in the F slot.
		if CARDS.has(home) and home != "farm" and not card_allowed(home,kind): problems.append("lord %s: home_card %s belongs to another faction" % [kind,home])
		if not CARDS.has(home) or CARDS[home].type != "building": problems.append("lord %s: home_card %s must be a building card" % [kind,home])
		if tier("range",lord_attack_range(kind)).is_empty(): problems.append("lord %s: attack range %s is not a tier value" % [kind,str(lord_attack_range(kind))])
		if tier("interval",lord_attack_interval(kind)).is_empty(): problems.append("lord %s: attack interval %s is not a tier value" % [kind,str(lord_attack_interval(kind))])
	for kind: String in MINION_LORDS:
		var d: Dictionary = MINION_LORDS[kind]
		if LORDS.has(kind): problems.append("minion %s: also a normal lord" % kind)
		for key: String in ["name","card","role","hp","damage","speed"]:
			if not d.has(key): problems.append("minion %s: missing %s" % [kind,key])
		if not CARDS.has(d.get("card","")): problems.append("minion %s: unknown card" % kind)
		for stat: String in ["hp","damage","speed"]:
			if d.has(stat) and tier(stat,d[stat]).is_empty(): problems.append("minion %s: %s is not a tier value" % [kind,stat])
		if tier("range",lord_attack_range(kind)).is_empty(): problems.append("minion %s: attack range %s is not a tier value" % [kind,str(lord_attack_range(kind))])
		if tier("interval",lord_attack_interval(kind)).is_empty(): problems.append("minion %s: attack interval %s is not a tier value" % [kind,str(lord_attack_interval(kind))])
		if skill_text(kind).is_empty(): problems.append("minion %s: empty skill text" % kind)
		if d.has("home_card") and (not CARDS.has(d.home_card) or not is_home_card(d.home_card)): problems.append("minion %s: invalid home_card" % kind)
		for k in d.get("cycle_speed",{}):
			if not CARDS.has(k) or d.cycle_speed[k] <= 0: problems.append("minion %s: invalid cycle_speed" % kind)
		for group: String in ["toughen","haste"]:
			for k in d.get(group,[]):
				if not (k == "*" and group == "haste") and not CARDS.has(k): problems.append("minion %s: unknown card %s in %s" % [kind,str(k),group])
		for k in d.get("swarm",{}):
			if not CARDS.has(k) or CARDS[k].type != "unit" or d.swarm[k] < 1: problems.append("minion %s: invalid swarm %s" % [kind,str(k)])
		for b in d.get("start_buildings",[]):
			if b.size() != 3 or not CARDS.has(b[2]) or CARDS[b[2]].type != "building" or b[0] < 0 or b[0] > 8 or b[1] < 0 or b[1] > 4: problems.append("minion %s: invalid start building" % kind)
	return problems

# Deck = farmland (always, own hand slot) + a chosen lord + 8 rotating cards (producer 2026-10-29).
const PRESET_NAMES := ["向日葵流","穩健農莊","劫掠隊"]
const PRESETS := [
	["farmer","hunter","mill","spearbow","tower","militia","rain","ox"],
	["farmer","militia","hunter","knight","spearbow","tower","rain","healer"],
	["farmer","mob","ox","ram","hunter","fire","scarecrow","militia"]
]
const PRESET_LORDS := ["harvest","iron","lion"]
# A new player's deck (producer 2026-11-12): the lion lord's raiding party. The earlier choice (the
# trap-heavy mage deck from the 2026-11-05 search) was the strongest under 400-hp gates; with SS
# walls it cannot finish a match and a first battle against the 普通 AI ran until the dawn verdict.
const DEFAULT_DECK := ["farmer","drummer","healer","shieldguard","hunter","rain","fire","ram"]
const DEFAULT_LORD := "lion"
const CLASSIC_UNDERWORLD_DECK := ["skeleton","ghoul","dark_wizard","necromancer","corpse_giant","raven","curse","plague"]
const CLASSIC_UNDERWORLD_LORD := "underworld"
# Lords are chosen on the deck screen and never enter the hand.
# Lord health follows role: SS defender, S frontline, A support.
# Lord speeds (2026-11-03 ten tiers): beast B 90, classic lords C 65, ranged casters D 50.
const LORDS := {
	"beast":{"name":"馴獸領主","role":"獸群型","faction":"beast","home_card":"glutton_nest","hp":560.0,"damage":50.0,"speed":120.0,"skill":"獸群號角","skill_cost":40.0,"skill_cooldown":10.0,"pack_count":1,"pack_kind":"pouch_beast","skill_desc":"每條開放路線在己方領地最前端各放出 %s 隻%s。"},
	"rune":{"name":"符文領主","role":"法陣型","faction":"magic","home_card":"crystal","hp":560.0,"damage":70.0,"speed":50.0,"ranged":true,"range":LORD_RANGED_RANGE_MED,"skill":"符文前線","skill_cost":60.0,"skill_cooldown":10.0,"skill_desc":"在每條開放路線領地最前方的空格，各召喚一個隨機陷阱法陣；不覆蓋建築。"},
	"vampire":{"name":"吸血領主","role":"血契型","faction":"dark","home_card":"grave","hp":1500.0,"damage":130.0,"speed":65.0,"skill":"鮮血盟約","skill_cost":85.0,"skill_cooldown":15.0,"blood_duration":16.0,"skill_desc":"所有友方部隊攻速、移速升一檔（最高 S），持續 %s 秒；造成實際傷害時等量增加自身目前及最大生命，已獲得生命保留。"},
	"mage":{"name":"法師領主","role":"時空型","faction":"magic","home_card":"crystal","hp":560.0,"damage":50.0,"speed":50.0,"ranged":true,"range":LORD_RANGED_RANGE_FAR,"skill":"時空凝滯","skill_cost":60.0,"skill_cooldown":15.0,"freeze_duration":6.0,"skill_desc":"空間波動凍結敵方所有部隊、領主與建築 %s 秒，期間敵方停止產金、箭塔停火；我方一切照常。"},
	"adventure":{"name":"邊境領主","role":"主角型","faction":"normal","hp":1500.0,"damage":180.0,"speed":65.0,"skill":"破陣斬","skill_cost":45.0,"skill_cooldown":10.0,"skill_cells":5,"skill_damage":1200.0,"skill_desc":"向前斬出長 %s 格、寬三格的劍氣，對範圍內敵軍、建築與領主造成 %s 傷害。"},
	"underworld":{"name":"冥府領主","role":"亡者型","faction":"dark","home_card":"grave","hp":560.0,"damage":70.0,"speed":50.0,"ranged":true,"range":LORD_RANGED_RANGE_MED,"skill":"亡者大軍","skill_cost":80.0,"skill_cooldown":15.0,"summon_count":4,"skill_desc":"我方每座墓碑各召喚 %s 隻骷髏兵；沒有墓碑時無法發動。"},
	"lion":{"name":"紅獅領主","role":"進攻型","faction":"normal","hp":1500.0,"damage":130.0,"speed":65.0,"skill":"獅王號令","skill_cost":115.0,"skill_cooldown":20.0,"skill_desc":"每路從己方城牆各召喚一名騎士，緩步進軍。"},
	"harvest":{"name":"豐收領主","role":"經濟型","faction":"normal","hp":1500.0,"damage":130.0,"speed":65.0,"skill":"豐年祭","skill_cost":115.0,"skill_cooldown":20.0,"skill_desc":"每路在己方領地空格種一塊農田，全部農田回滿血。"},
	"iron":{"name":"鐵壁領主","role":"防守型","faction":"normal","hp":3000.0,"damage":180.0,"speed":65.0,"skill":"箭樓築城","skill_cost":130.0,"skill_cooldown":30.0,"tower_count":2,"skill_desc":"在我方領地隨機 %s 個空格各建造一座箭樓。"}
}
# 小怪領主 (roguelike, 2026-11-06): enemy-only lords themed on one card. They are not in LORDS, so
# the deck screen, codex, watch mode and online play never offer them. Instead of a skill each
# has one passive rule (all optional):
#   no_farms        no home card and no starting farms        income_mult   base gold tick multiplier
#   toughen [kinds] those troops one hp tier up (max SS)      haste [kinds] those troops one speed and
#   swarm {kind:n}  each such card deploys n more troops                    attack tier up ("*" = all)
#   start_buildings [[col,lane,kind]] placed at the start, columns counted from its own back edge
# "card" names the card whose picture stands in for the lord's portrait.
const MINION_LORDS := {
	"card_enemy_glutton_nest":{"name":"巢穴飼主","card":"glutton_nest","role":"吞噬型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[2,1,"glutton_nest"],[2,3,"glutton_nest"]]},
	"card_enemy_mana_spring":{"name":"湧泉守望者","card":"mana_spring","role":"水晶型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"mana_spring":1.5}},
	"card_enemy_chain_lightning":{"name":"雷霆使者","card":"chain_lightning","role":"連鎖型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"chain_lightning":1.5}},
	"card_enemy_arcane_shield":{"name":"護盾監護者","card":"arcane_shield","role":"護盾型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"arcane_shield":1.5}},
	"card_enemy_time_field":{"name":"時空獄卒","card":"time_field","role":"力場型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"time_field":1.5}},
	"card_enemy_charge_horn":{"name":"衝鋒號手","card":"charge_horn","role":"號角型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"charge_horn":1.5}},
	"card_enemy_levy":{"name":"徵召官","card":"levy","role":"徵召型","hp":560.0,"damage":50.0,"speed":50.0,"cycle_speed":{"levy":1.5}},
	"card_enemy_watchtower":{"name":"望樓哨長","card":"watchtower","role":"偵查型","hp":560.0,"damage":50.0,"speed":50.0,"start_buildings":[[2,2,"watchtower"]]},
	"card_enemy_sacrifice":{"name":"獻祭司儀","card":"sacrifice","role":"犧牲型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"sacrifice":1.5}},
	"card_enemy_dread_howl":{"name":"哀嚎使徒","card":"dread_howl","role":"恐懼型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"dread_howl":1.5}},
	"card_enemy_mass_grave":{"name":"亂葬坑守墓人","card":"mass_grave","role":"死亡型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","start_buildings":[[2,1,"mass_grave"],[2,3,"mass_grave"]]},
	"card_enemy_manor_retainer":{"name":"莊園管家","card":"manor_retainer","role":"領地型","hp":900.0,"damage":70.0,"speed":50.0,"toughen":["manor_retainer"]},
	"card_enemy_rolling_boulder":{"name":"滾石監工","card":"rolling_boulder","role":"直線型","hp":1500.0,"damage":95.0,"speed":50.0,"cycle_speed":{"rolling_boulder":1.5}},
	"card_enemy_dark_wizard":{"name":"噬魂宗師","card":"dark_wizard","role":"高傷型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","toughen":["dark_wizard"]},
	"card_enemy_summon_trap":{"name":"召獸法陣師","card":"summon_trap","role":"陷阱型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[2,1,"summon_trap"],[2,3,"summon_trap"]]},
	"card_enemy_chimera":{"name":"嵌合獸王","card":"chimera","role":"召喚物型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","toughen":["chimera"]},
	"card_enemy_blink_blade":{"name":"閃刃劍豪","card":"blink_blade","role":"突進型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","toughen":["blink_blade"]},
	"card_enemy_arcane_archer":{"name":"貫星射手","card":"arcane_archer","role":"遠程型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","haste":["arcane_archer"]},
	"card_enemy_artificer":{"name":"工坊總管","card":"artificer","role":"維修型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","haste":["artificer"]},
	"card_enemy_crystal":{"name":"水晶監督","card":"crystal","role":"耗能型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[1,2,"crystal"]]},
	"card_enemy_teleport_trap":{"name":"迷途引路人","card":"teleport_trap","role":"陷阱型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[2,1,"teleport_trap"],[2,3,"teleport_trap"]]},
	"card_enemy_arcane_tower":{"name":"祕法塔主","card":"arcane_tower","role":"範圍型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","start_buildings":[[2,1,"arcane_tower"],[2,3,"arcane_tower"]]},
	"card_enemy_eyewing_dragon":{"name":"眼翼龍王","card":"eyewing_dragon","role":"吼叫型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"glutton_nest","toughen":["eyewing_dragon"]},
	"card_enemy_belly_eye":{"name":"百眼監視者","card":"belly_eye","role":"偵查型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","toughen":["belly_eye"]},
	"card_enemy_hooknose_flyer":{"name":"鉤鼻空襲者","card":"hooknose_flyer","role":"飛行型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","haste":["hooknose_flyer"]},
	"card_enemy_long_dragon":{"name":"長龍吐息者","card":"long_dragon","role":"吐息型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"glutton_nest","haste":["long_dragon"]},
	"card_enemy_barricade":{"name":"拒馬工頭","card":"barricade","role":"耐久型","hp":560.0,"damage":50.0,"speed":50.0,"start_buildings":[[2,2,"barricade"]]},
	"card_enemy_corpse_giant":{"name":"腐屍巨王","card":"corpse_giant","role":"重裝型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","toughen":["corpse_giant"]},
	"card_enemy_curse":{"name":"咒縛女巫","card":"curse","role":"死後型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","cycle_speed":{"curse":1.5}},
	"card_enemy_grave":{"name":"墓園守望者","card":"grave","role":"死亡型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"grave"]]},
	"card_enemy_reaper":{"name":"末日收割者","card":"reaper","role":"直劈型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","haste":["reaper"]},
	"card_enemy_plague":{"name":"瘟疫醫師","card":"plague","role":"毒霧型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","cycle_speed":{"plague":1.5}},
	"card_enemy_bonewall":{"name":"白骨築城師","card":"bonewall","role":"阻擋型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","start_buildings":[[2,1,"bonewall"],[2,3,"bonewall"]]},
	"card_enemy_farmer":{"name":"農夫長","card":"farmer","role":"經濟型","hp":560.0,"damage":50.0,"speed":50.0,"haste":["farmer"]},
	"card_enemy_harvest":{"name":"豐收祭司","card":"harvest","role":"經濟型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"harvest":1.5}},
	"card_enemy_scarecrow":{"name":"稻草看守者","card":"scarecrow","role":"誘敵型","hp":560.0,"damage":50.0,"speed":50.0,"start_buildings":[[2,2,"scarecrow"]]},
	"card_enemy_spearbow":{"name":"槍弓教頭","card":"spearbow","role":"遠近軍團型","hp":900.0,"damage":70.0,"speed":50.0,"toughen":["militia","hunter"]},
	"card_enemy_farm":{"name":"田莊主人","card":"farm","role":"經濟型","hp":560.0,"damage":50.0,"speed":50.0,"home_card":"farm","start_buildings":[[1,2,"farm"]]},
	"card_enemy_rain":{"name":"箭雨校尉","card":"rain","role":"清群法術型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"rain":1.5}},
	"card_enemy_fire":{"name":"火罐縱火者","card":"fire","role":"燒田法術型","hp":1500.0,"damage":95.0,"speed":50.0,"cycle_speed":{"fire":1.5}},
	"card_enemy_guard":{"name":"聖堂大團長","card":"guard","role":"重裝軍團型","hp":1500.0,"damage":95.0,"speed":50.0,"toughen":["knight","healer"]},
	"card_enemy_mill":{"name":"磨坊領班","card":"mill","role":"大型經濟型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[2,1,"mill"],[2,3,"mill"]]},
	"mob_foreman":{"name":"暴民頭領","card":"mob","role":"蜂擁型","hp":560.0,"damage":50.0,"speed":50.0,"swarm":{"mob":1}},
	"net_poacher":{"name":"捕獵頭目","card":"net_hunter","role":"纏足型","hp":560.0,"damage":50.0,"speed":50.0,"haste":["net_hunter"]},
	"field_prior":{"name":"行軍修士","card":"healer","role":"救護型","hp":560.0,"damage":50.0,"speed":50.0,"haste":["healer"]},
	"axe_raider":{"name":"破甲掠奪者","card":"axe_thrower","role":"破甲型","hp":900.0,"damage":70.0,"speed":50.0,"haste":["axe_thrower"]},
	"phase_stalker":{"name":"相位追獵者","card":"phase_rider","role":"穿陣型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","haste":["phase_rider"]},
	"ghoul_feaster":{"name":"饕宴屍鬼","card":"ghoul","role":"吞食型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","toughen":["ghoul"]},
	"blood_prior":{"name":"鮮血主祭","card":"blood_tower","role":"續戰型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,1,"blood_tower"],[1,3,"blood_tower"]]},
	"clock_warden":{"name":"時鐘典獄長","card":"chronomancer","role":"禁錮型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","haste":["chronomancer"]},
	"ram_marshal":{"name":"破門督軍","card":"ram","role":"破門型","hp":1500.0,"damage":95.0,"speed":50.0,"toughen":["ram"]},
	"bandit_chief":{"name":"強盜頭子","card":"bandit","role":"劫掠型","hp":560.0,"damage":50.0,"speed":50.0,"no_farms":true,"income_mult":2.0},
	"militia_captain":{"name":"民兵隊長","card":"militia","role":"人海型","hp":560.0,"damage":50.0,"speed":50.0,"swarm":{"militia":2}},
	"hunter_master":{"name":"獵戶頭目","card":"hunter","role":"遠射型","hp":560.0,"damage":50.0,"speed":50.0,"haste":["hunter"]},
	"raven_mother":{"name":"鴉群之母","card":"raven","role":"拆田型","hp":560.0,"damage":50.0,"speed":50.0,"home_card":"grave","haste":["raven"],"swarm":{"raven":2}},
	"card_enemy_pouch_beast":{"name":"囊腹獸頭目","card":"pouch_beast","role":"厚血型","hp":900.0,"damage":70.0,"speed":36.0,"home_card":"glutton_nest"},
	"fishbeak_boss":{"name":"魚喙怪頭目","card":"fishbeak","role":"騷擾型","hp":560.0,"damage":50.0,"speed":50.0,"home_card":"glutton_nest","haste":["fishbeak"],"swarm":{"fishbeak":1}},
	"ox_herder":{"name":"牧牛人","card":"ox","role":"衝鋒型","hp":900.0,"damage":70.0,"speed":50.0,"toughen":["ox"]},
	"shield_sergeant":{"name":"盾衛軍士","card":"shieldguard","role":"盾牆型","hp":900.0,"damage":70.0,"speed":50.0,"toughen":["shieldguard"]},
	"drummer_major":{"name":"鼓手長","card":"drummer","role":"急行型","hp":900.0,"damage":70.0,"speed":50.0,"haste":["*"]},
	"skeleton_king":{"name":"骷髏王","card":"skeleton","role":"亡者型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","swarm":{"skeleton":2}},
	"trap_weaver":{"name":"法陣師","card":"blast_trap","role":"陷阱型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[2,1,"blast_trap"],[2,2,"teleport_trap"],[2,3,"blast_trap"]]},
	"imp_thief":{"name":"鬍子魔王","card":"bearded_imp","role":"偷竊型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","income_mult":1.5,"haste":["bearded_imp"]},
	"knight_commander":{"name":"騎士團長","card":"knight","role":"重裝型","hp":1500.0,"damage":95.0,"speed":50.0,"toughen":["knight"]},
	"tower_warden":{"name":"箭樓守衛","card":"tower","role":"堡壘型","hp":1500.0,"damage":95.0,"speed":50.0,"start_buildings":[[1,1,"tower"],[1,3,"tower"]]},
	"necro_adept":{"name":"死靈學徒","card":"necromancer","role":"招魂型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","haste":["skeleton"]},
	"golem_smith":{"name":"魔像匠","card":"arcane_golem","role":"鍛造型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"crystal","toughen":["arcane_golem"]},
	"catapult_engineer":{"name":"投石匠","card":"catapult","role":"攻城型","hp":1500.0,"damage":95.0,"speed":50.0,"start_buildings":[[2,1,"barricade"],[2,2,"barricade"],[2,3,"barricade"]]},
	"dragon_lord":{"name":"骨刺龍王","card":"thorn_dragon","role":"魔物型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"glutton_nest","toughen":["thorn_dragon"]},
	"card_enemy_mule_cart":{"name":"騾馬貨車首領","card":"mule_cart","role":"運貨型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"mule_cart":1.5}},
	"card_enemy_hook_collector":{"name":"鉤鐮收債人首領","card":"hook_collector","role":"收債型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"hook_collector":1.5}},
	"card_enemy_twin_gambler":{"name":"雙刃賭徒首領","card":"twin_gambler","role":"賭命型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"twin_gambler":1.5}},
	"card_enemy_gold_monster":{"name":"金幣怪物首領","card":"gold_monster","role":"傾囊型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"gold_monster":1.5}},
	"card_enemy_spell_tide_magus":{"name":"咒潮大法師","card":"spell_tide_magus","role":"咒潮型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"spell_tide_magus":1.5}},
	"card_enemy_thorn_mother":{"name":"荊棘巢母","card":"thorn_mother","role":"荊棘型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"thorn_mother":1.5}},
	"card_enemy_gatebreaker":{"name":"破門錘手首領","card":"gatebreaker","role":"破門型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"gatebreaker":1.5}},
	"card_enemy_disgraced_lancer":{"name":"叛逃槍騎首領","card":"disgraced_lancer","role":"衝刺型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"disgraced_lancer":1.5}},
	"card_enemy_runaway_thrall":{"name":"逃亡血奴首領","card":"runaway_thrall","role":"弒主型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"runaway_thrall":1.5}},
	"card_enemy_renegade_artificer":{"name":"叛逃工匠首領","card":"renegade_artificer","role":"重拳型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"renegade_artificer":1.5}},
	"card_enemy_oathless_imp":{"name":"無誓鬼首領","card":"oathless_imp","role":"死撐型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"oathless_imp":1.5}},
	"card_enemy_assassin":{"name":"刺客首領","card":"assassin","role":"潛行型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"assassin":1.5}},
	"card_enemy_vampire_hunter":{"name":"吸血鬼獵人首領","card":"vampire_hunter","role":"獵殺型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"vampire_hunter":1.5}},
	"card_enemy_monster_hunter":{"name":"怪物獵人首領","card":"monster_hunter","role":"獵殺型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"monster_hunter":1.5}},
	"card_enemy_spellbreaker":{"name":"破法者首領","card":"spellbreaker","role":"抗法型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"spellbreaker":1.5}},
	"card_enemy_powder_barrel":{"name":"炸藥桶主人","card":"powder_barrel","role":"陷阱型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[1,2,"powder_barrel"]]},
	"card_enemy_pallbearer":{"name":"抬棺僕首領","card":"pallbearer","role":"抬棺型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"pallbearer":1.5}},
	"card_enemy_mourning_maid":{"name":"喪鐘侍女首領","card":"mourning_maid","role":"鐘聲型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"mourning_maid":1.5}},
	"card_enemy_corpse_stitcher":{"name":"縫屍匠首領","card":"corpse_stitcher","role":"縫屍型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"corpse_stitcher":1.5}},
	"card_enemy_blood_attendant":{"name":"血誓侍從首領","card":"blood_attendant","role":"吸血型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"blood_attendant":1.5}},
	"card_enemy_funeral_cottage":{"name":"殯儀小屋主人","card":"funeral_cottage","role":"送葬型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"funeral_cottage"]]},
	"card_enemy_sleepless_belfry":{"name":"不眠鐘樓主人","card":"sleepless_belfry","role":"驚醒型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"sleepless_belfry"]]},
	"card_enemy_blood_altar":{"name":"血誓祭壇主人","card":"blood_altar","role":"獻血型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"blood_altar"]]},
	"card_enemy_borrowed_bones":{"name":"借骨術士","card":"borrowed_bones","role":"借屍型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"borrowed_bones":1.5}},
	"card_enemy_grave_exchange":{"name":"掘墓換金術士","card":"grave_exchange","role":"掘墓型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"grave_exchange":1.5}},
	"card_enemy_mourning_shroud":{"name":"喪禮披風術士","card":"mourning_shroud","role":"護命型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"mourning_shroud":1.5}},
	"card_enemy_sealed_coffin":{"name":"封棺術士","card":"sealed_coffin","role":"定身型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"sealed_coffin":1.5}},
	"card_enemy_arquebusier":{"name":"行軍火繩槍兵首領","card":"arquebusier","role":"火槍型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"arquebusier":1.5}},
	"card_enemy_funeral_grenadier":{"name":"喪鐘擲彈使首領","card":"funeral_grenadier","role":"擲彈型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"funeral_grenadier":1.5}},
	"card_enemy_dog_cannon":{"name":"骷髏狗扛砲首領","card":"dog_cannon","role":"機動型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"dog_cannon":1.5}},
	"card_enemy_orrery_walker":{"name":"星儀行砲首領","card":"orrery_walker","role":"光束型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"orrery_walker":1.5}},
	"card_enemy_seal_bearer":{"name":"符印輪轂師首領","card":"seal_bearer","role":"扇射型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"seal_bearer":1.5}},
	"card_enemy_imp_bomb_runner":{"name":"小鬼炸彈兵首領","card":"imp_bomb_runner","role":"自爆型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"imp_bomb_runner":1.5}},
	"card_enemy_macebreaker":{"name":"釘錘破甲兵首領","card":"macebreaker","role":"破甲型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"macebreaker":1.5}},
	"card_enemy_beekeeper":{"name":"養蜂人首領","card":"beekeeper","role":"蜂群型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"beekeeper":1.5}},
	"card_enemy_bellbearer":{"name":"送葬鐘使首領","card":"bellbearer","role":"療傷型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"bellbearer":1.5}},
	"card_enemy_seal_altar":{"name":"封印祭壇主人","card":"seal_altar","role":"封印型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"seal_altar":1.5}},
	"card_enemy_plague_bishop":{"name":"腐土主教","card":"plague_bishop","role":"腐土型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"grave","toughen":["funeral_monk"]},
	"card_enemy_funeral_monk":{"name":"送葬修士長","card":"funeral_monk","role":"隨行型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave"},
	"card_enemy_shroud_arbalist":{"name":"裹屍弩手首領","card":"shroud_arbalist","role":"重弩型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","cycle_speed":{"shroud_arbalist":1.5}},
	"card_enemy_sigil_weaver":{"name":"符印織師首領","card":"sigil_weaver","role":"護盾型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"sigil_weaver":1.5}},
	"card_enemy_astrolabe_surveyor":{"name":"星盤測繪師首領","card":"astrolabe_surveyor","role":"偵察型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"astrolabe_surveyor":1.5}},
	"card_enemy_bog_troll":{"name":"沼澤巨魔首領","card":"bog_troll","role":"重裝型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"bog_troll":1.5}},
	"card_enemy_tusk_boar":{"name":"獠牙野豬人首領","card":"tusk_boar","role":"衝鋒型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"tusk_boar":1.5}},
	"card_enemy_granary":{"name":"糧倉主人","card":"granary","role":"儲備型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[1,2,"granary"]]},
	"card_enemy_field_smithy":{"name":"野戰鐵匠鋪主人","card":"field_smithy","role":"護甲型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[1,2,"field_smithy"]]},
	"card_enemy_ossuary":{"name":"藏骨禮拜堂主人","card":"ossuary","role":"亡者型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"ossuary"]]},
	"card_enemy_soul_well":{"name":"引魂井主人","card":"soul_well","role":"靈魂型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"grave","start_buildings":[[1,2,"soul_well"]]},
	"card_enemy_observatory":{"name":"星象觀測所主人","card":"observatory","role":"偵察型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[1,2,"observatory"]]},
	"card_enemy_rune_workshop":{"name":"符文工坊主人","card":"rune_workshop","role":"建築型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[1,2,"rune_workshop"]]},
	"card_enemy_monster_hatchery":{"name":"巨獸孵巢主人","card":"monster_hatchery","role":"孵育型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[1,2,"monster_hatchery"]]},
	"card_enemy_war_lodge":{"name":"獠牙戰寨主人","card":"war_lodge","role":"集結型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[1,2,"war_lodge"]]},
	"card_enemy_old_witch":{"name":"老巫婆首領","card":"old_witch","role":"毒蝕型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"old_witch":1.5}},
	"card_enemy_halberdier":{"name":"長戟教頭","card":"halberdier","role":"列陣型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"halberdier":1.5}},
	"card_enemy_ballista_tower":{"name":"重弩守將","card":"ballista_tower","role":"狙擊型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[1,2,"ballista_tower"]]},
	"card_enemy_supply_depot":{"name":"後勤軍需官","card":"supply_depot","role":"減費型","hp":900.0,"damage":70.0,"speed":50.0,"start_buildings":[[1,2,"supply_depot"]]},
	"card_enemy_counter_charge":{"name":"反撲號手","card":"counter_charge","role":"反擊型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"counter_charge":1.5}},
	"card_enemy_flaming_pitch":{"name":"火油擲手","card":"flaming_pitch","role":"火海型","hp":900.0,"damage":70.0,"speed":50.0,"cycle_speed":{"flaming_pitch":1.5}},
	"card_enemy_rune_sentinel":{"name":"符文守衛長","card":"rune_sentinel","role":"抗魔型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"rune_sentinel":1.5}},
	"card_enemy_ward_guard":{"name":"結界守衛長","card":"ward_guard","role":"護衛型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal"},
	"card_enemy_ward_phalanx":{"name":"結界方陣統領","card":"ward_phalanx","role":"軍陣型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"ward_phalanx":1.5}},
	"card_enemy_prism_mage":{"name":"稜鏡大法師","card":"prism_mage","role":"散射型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"prism_mage":1.5}},
	"card_enemy_aether_hound":{"name":"乙太獵手","card":"aether_hound","role":"相位型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"aether_hound":1.5}},
	"card_enemy_spell_mirror":{"name":"魔鏡宗師","card":"spell_mirror","role":"反彈型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"spell_mirror":1.5}},
	"card_enemy_mana_battery":{"name":"蓄能祭司","card":"mana_battery","role":"蓄能型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[1,2,"mana_battery"]]},
	"card_enemy_warp_beacon":{"name":"折躍守望者","card":"warp_beacon","role":"脈衝型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","start_buildings":[[2,2,"warp_beacon"]]},
	"card_enemy_mana_drain":{"name":"吸魔術士","card":"mana_drain","role":"抽金型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"mana_drain":1.5}},
	"card_enemy_phase_shift":{"name":"折躍先鋒","card":"phase_shift","role":"突進型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"phase_shift":1.5}},
	"card_enemy_gravity_well":{"name":"重力術士","card":"gravity_well","role":"聚敵型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"gravity_well":1.5}},
	"card_enemy_mirror_clone":{"name":"鏡像幻術師","card":"mirror_clone","role":"複製型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"crystal","cycle_speed":{"mirror_clone":1.5}},
	"card_enemy_parasite_mite":{"name":"蟲群母體","card":"parasite_mite","role":"分裂型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"parasite_mite":1.5}},
	"card_enemy_thorn_hound":{"name":"棘刺馴獸師","card":"thorn_hound","role":"反傷型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"thorn_hound":1.5}},
	"card_enemy_web_spinner":{"name":"蛛網女妖","card":"web_spinner","role":"定身型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"web_spinner":1.5}},
	"card_enemy_sky_scavenger":{"name":"禿鷲領袖","card":"sky_scavenger","role":"食腐型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"sky_scavenger":1.5}},
	"card_enemy_dire_hydra":{"name":"狂蜥巨獸","card":"dire_hydra","role":"橫掃型","hp":1500.0,"damage":95.0,"speed":50.0,"home_card":"glutton_nest","toughen":["dire_hydra"]},
	"card_enemy_mimic_egg":{"name":"怪卵守護者","card":"mimic_egg","role":"孵化型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[2,2,"mimic_egg"]]},
	"card_enemy_bramble_wall":{"name":"荊棘領主","card":"bramble_wall","role":"反傷型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[2,2,"bramble_wall"]]},
	"card_enemy_blood_cauldron":{"name":"血鍋祭司","card":"blood_cauldron","role":"暴擊型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[1,2,"blood_cauldron"]]},
	"card_enemy_hive_nest":{"name":"飛魔巢主","card":"hive_nest","role":"空軍型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[1,2,"hive_nest"]]},
	"card_enemy_leech_vine":{"name":"蔓藤領主","card":"leech_vine","role":"吸血型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[2,2,"leech_vine"]]},
	"card_enemy_imp_burrow":{"name":"地洞頭目","card":"imp_burrow","role":"偷金型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","start_buildings":[[1,2,"imp_burrow"]]},
	"card_enemy_berserk_blood":{"name":"狂血戰狂","card":"berserk_blood","role":"狂暴型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"berserk_blood":1.5}},
	"card_enemy_corrosive_bile":{"name":"酸雨術士","card":"corrosive_bile","role":"破防型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"corrosive_bile":1.5}},
	"card_enemy_pack_ambush":{"name":"突襲獸王","card":"pack_ambush","role":"撲擊型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"pack_ambush":1.5}},
	"card_enemy_devouring_maw":{"name":"巨口飼主","card":"devouring_maw","role":"斬殺型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"devouring_maw":1.5}},
	"card_enemy_wing_gust":{"name":"振翼妖王","card":"wing_gust","role":"擊退型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"wing_gust":1.5}},
	"card_enemy_feral_mutation":{"name":"畸變主宰","card":"feral_mutation","role":"強化型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"feral_mutation":1.5}},
	"card_enemy_swarm_eruption":{"name":"爆蟲領主","card":"swarm_eruption","role":"寄生型","hp":900.0,"damage":70.0,"speed":50.0,"home_card":"glutton_nest","cycle_speed":{"swarm_eruption":1.5}},
}

static func is_minion(lord: String) -> bool:
	return MINION_LORDS.has(lord)

const MINION_SKILL_COOLDOWN := 40.0
const FRIENDLY_SPELLS := ["harvest","mana_spring","arcane_shield","levy","charge_horn","sacrifice","grave_exchange","mourning_shroud","mirror_clone","phase_shift","berserk_blood","feral_mutation"]
static var _minion_data_cache: Dictionary = {}

static func lord_is_ranged(lord: String) -> bool:
	if LORDS.has(lord): return bool(LORDS[lord].get("ranged",false))
	if not MINION_LORDS.has(lord): return false
	var d: Dictionary = MINION_LORDS[lord]
	if d.has("ranged"): return bool(d.ranged)
	var c: Dictionary = CARDS.get(d.get("card",""),{})
	var t: String = c.get("type","")
	if t == "unit": return bool(c.get("projectile",false)) or float(c.get("range",0.0)) >= RANGED_MIN
	if t == "building": return float(c.get("range",0.0)) >= RANGED_MIN
	if t == "spell": return not d.card in FRIENDLY_SPELLS
	return false

static func lord_attack_range(lord: String) -> float:
	if LORDS.has(lord):
		if LORDS[lord].has("range"): return float(LORDS[lord].range)
		return LORD_RANGED_RANGE_MED if lord_is_ranged(lord) else LORD_RANGE
	if MINION_LORDS.has(lord) and MINION_LORDS[lord].has("range"): return float(MINION_LORDS[lord].range)
	if not lord_is_ranged(lord): return LORD_RANGE
	var card_kind: String = MINION_LORDS[lord].card
	var c: Dictionary = CARDS.get(card_kind,{})
	if float(c.get("range",0.0)) >= LORD_RANGED_RANGE_MED or card_kind in ["rain","fire","chain_lightning","rolling_boulder","flaming_pitch"]:
		return LORD_RANGED_RANGE_FAR
	return LORD_RANGED_RANGE_MED

static func lord_attack_interval(lord: String) -> float:
	return LORD_RANGED_INTERVAL if lord_is_ranged(lord) else LORD_INTERVAL

static func lord_projectile_kind(lord: String) -> String:
	if not lord_is_ranged(lord): return ""
	if LORDS.has(lord):
		return "dark_wizard" if LORDS[lord].get("faction","") in ["dark","magic"] else "lord"
	var c: Dictionary = CARDS.get(MINION_LORDS.get(lord,{}).get("card",""),{})
	if c.get("faction","") in ["dark","magic"] or c.get("curse_splash",false): return "dark_wizard"
	return "lord"

# Active skill derived from a 小怪領主's themed card so every wild boss carries a combat skill.
static func minion_skill(lord: String) -> Dictionary:
	var d: Dictionary = MINION_LORDS[lord]
	var card_kind: String = d.card
	var c: Dictionary = CARDS[card_kind]
	var ctype: String = c.type
	if ctype == "unit":
		var summon_count := 2 if int(c.cost) <= 8 else 1
		var cost := 25.0 if int(c.cost) <= 8 else (30.0 if int(c.cost) <= 14 else 35.0)
		return {
			"skill":"親衛：%s" % c.name,
			"skill_cost":cost,
			"skill_cooldown":MINION_SKILL_COOLDOWN,
			"skill_desc":"於前線領地召喚 %d 隊%s增援。" % [summon_count,c.name],
			"skill_kind":"unit",
			"skill_card":card_kind,
			"summon_count":summon_count
		}
	if ctype == "spell":
		var cost := clampf(float(c.cost)+12.0,20.0,35.0)
		return {
			"skill":"奧義：%s" % c.name,
			"skill_cost":cost,
			"skill_cooldown":MINION_SKILL_COOLDOWN,
			"skill_desc":"向關鍵戰區免費施放一次%s。" % c.name,
			"skill_kind":"spell",
			"skill_card":card_kind
		}
	return {
		"skill":"構建：%s" % c.name,
		"skill_cost":25.0,
		"skill_cooldown":MINION_SKILL_COOLDOWN,
		"skill_desc":"在前線空位建造一座%s，並修復全體友方建築 25%% 生命。" % c.name,
		"skill_kind":"building",
		"skill_card":card_kind
	}

# Data for any lord a battle may hold: a normal lord, a 小怪領主 (merged with its skill), or lion fallback.
static func lord_data(lord: String) -> Dictionary:
	if LORDS.has(lord): return LORDS[lord]
	if MINION_LORDS.has(lord):
		if not _minion_data_cache.has(lord):
			var merged: Dictionary = MINION_LORDS[lord].duplicate()
			merged.merge(minion_skill(lord),true)
			_minion_data_cache[lord] = merged
		return _minion_data_cache[lord]
	return LORDS.lion

static func lord_name(lord: String) -> String:
	return lord_data(lord).name

static func has_skill(lord: String) -> bool:
	return LORDS.has(lord) or MINION_LORDS.has(lord)

# One line describing a 小怪領主's passive rule (and ranged attack when applicable).
static func minion_text(lord: String) -> String:
	var txt := passive_text(MINION_LORDS[lord])
	if lord_is_ranged(lord):
		var prefix := txt.trim_suffix("。")
		var rtxt := "遠程攻擊（射程 %s）" % cells_text(lord_attack_range(lord))
		return (prefix + "，" + rtxt + "。") if not prefix.is_empty() else (rtxt + "。")
	return txt

# One line for any passive rule set (a 小怪領主, or a roguelike 內政領主), built from its data.
static func passive_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	if d.has("start_ink"): parts.append("開局金幣 +%d" % int(d.start_ink))
	if d.has("farm_mult"): parts.append("農田產出 ×%s" % number(d.farm_mult))
	if d.get("no_farms",false): parts.append("不帶農田")
	if d.has("income_mult"): parts.append("自然增長金幣 ×%s" % number(d.income_mult))
	if d.has("home_card"): parts.append("常駐牌改為%s" % CARDS[d.home_card].name)
	for kind: String in d.get("cycle_speed",{}): parts.append("%s手牌冷卻速度 ×%s" % ["全部卡牌" if kind == "*" else CARDS[kind].name,number(d.cycle_speed[kind])])
	for kind: String in d.get("toughen",[]): parts.append(("全軍" if kind == "*" else CARDS[kind].name)+"生命升一檔")
	for kind: String in d.get("haste",[]): parts.append(("全軍" if kind == "*" else CARDS[kind].name)+"移速與攻速升一檔")
	for kind: String in d.get("swarm",{}): parts.append("%s每張多 %d 名" % ["部隊卡" if kind == "*" else CARDS[kind].name,int(d.swarm[kind])])
	if d.has("start_buildings"):
		var names := {}
		for b: Array in d.start_buildings: names[CARDS[b[2]].name] = true
		parts.append("開局已蓋好"+"、".join(names.keys()))
	if d.has("skill_discount"): parts.append("領主技能充能 -%d" % int(d.skill_discount*SKILL_CHARGE_MULT))
	if d.has("skill_haste"): parts.append("領主技能冷卻 ×%s" % number(d.skill_haste))
	if d.has("lord_boost"): parts.append("上場領主生命與傷害升 %d 檔" % int(d.lord_boost))
	if d.has("gate_armor"): parts.append("城牆減傷 %d%%" % roundi(d.gate_armor*100.0))
	if d.has("thorns_gate"): parts.append("城牆反傷 %d" % int(d.thorns_gate))
	if d.has("kill_bounty"): parts.append("擊殺敵兵賞金 +%s" % number(d.kill_bounty))
	if d.has("post_heal"): parts.append("戰後每座城牆修 %d、領主治 %d" % [int(d.post_heal.get("gate",0)),int(d.post_heal.get("lord",0))])
	if d.has("gold_bonus"): parts.append("戰勝金幣 +%d%%" % roundi(d.gold_bonus*100.0))
	if d.get("targeted_upgrade",false): parts.append("商店與營火／古祠強化改為自選屬性（不隨機）")
	if d.has("skill_charge_mult"): parts.append("領主技能充能 ×%s" % number(d.skill_charge_mult))
	if d.has("skill_start_charge"): parts.append("開局技能已充能 %d%%" % roundi(d.skill_start_charge*100.0))
	if d.has("skill_echo_gold"): parts.append("每次施放領主技能得 %d 金幣" % int(d.skill_echo_gold))
	if d.has("kill_charge"): parts.append("每擊殺 1 名敵兵技能充能 +%d" % int(d.kill_charge))
	if d.has("gate_fall_spell"): parts.append("我方城牆被攻破時，在缺口免費施放%s" % String(CARDS.get(String(d.gate_fall_spell.get("kind","")),{}).get("name","法術")))
	for fm: Dictionary in d.get("field_mutators",[]):
		if fm.has("water_cols"): parts.append("中央第 %s 縱列化為水路（禁建／非飛行 -60%% 速）" % "、".join(fm.water_cols.map(func(c: int) -> String: return str(c+1))))
		if bool(fm.get("double_home_rows",false)): parts.append("開局前 2 排築滿 10 座我方常駐建築")
		if fm.has("periodic"):
			var p: Dictionary = fm.periodic
			var cname: String = CARDS.get(String(p.get("kind","grave")),{}).get("name","建築")
			parts.append("每 %d 秒戰場隨機浮現%s" % [int(p.get("interval",25.0)),cname])
		if fm.has("periodic_spell"):
			var ps: Dictionary = fm.periodic_spell
			var sname: String = CARDS.get(String(ps.get("kind","rain")),{}).get("name","法術")
			parts.append("每 %d 秒自動施放%s" % [int(ps.get("interval",20.0)),sname])
	return "，".join(parts)+"。"

# Lord skills (producer 2026-10-29): lords have no passive effects; each has one strong skill the
# player casts with Q (the AI casts its own). Since 2026-11-19 it costs no gold: it casts free once
# its charge meter is full (see skill_charge_need). After a cast it cools down first, and the meter
# only fills again once the cooldown is over.
const SKILL_COST := 50.0
const SKILL_COOLDOWN := 60.0
# A lord may set its own "skill_cooldown" (producer 2026-11-05: 亡者大軍 is much shorter).
static func skill_cooldown(lord: String) -> float:
	return lord_data(lord).get("skill_cooldown",SKILL_COOLDOWN)
const LION_KNIGHT_SPEED := 50.0 # 紅獅號令騎士行軍速度 (tier D)
const FEAST_BOOST := 30.0 # 豐年祭: seconds of doubled farm output
static func skill_cost(kind: String) -> float:
	return lord_data(kind).get("skill_cost",SKILL_COST)
# The charge meter (producer 2026-11-19): every gold spent on cards and every gold lost to a full
# purse adds 1 charge. A skill needs SKILL_CHARGE_MULT x its value ("skill_cost", the old gold price)
# plus SKILL_CHARGE_BASE; a "skill_discount" lowers the value first.
const SKILL_CHARGE_MULT := 2.0
const SKILL_CHARGE_BASE := 10.0
static func skill_charge_need(kind: String, discount: float = 0.0) -> float:
	return maxf(0.0,skill_cost(kind)-discount)*SKILL_CHARGE_MULT+SKILL_CHARGE_BASE

# One-line skill text for the deck screen, battle panel and help.
static func skill_text(kind: String) -> String:
	var info: Dictionary = lord_data(kind)
	var desc: String = String(info.get("skill_desc",""))
	if kind == "harvest" and "%s" in desc: desc = desc % number(FEAST_BOOST)
	if kind == "underworld": desc = desc % int(info.summon_count)
	if kind == "iron": desc = desc % int(info.tower_count)
	if kind == "mage": desc = desc % number(info.freeze_duration)
	if kind == "vampire": desc = desc % number(info.blood_duration)
	if kind == "beast": desc = desc % [str(int(info.pack_count)),CARDS[info.pack_kind].name]
	if kind == "adventure": desc = desc % [str(info.skill_cells),number(info.skill_damage)]
	return "%s（充能 %d，冷卻 %d 秒）：%s" % [info.skill,int(skill_charge_need(kind)),int(skill_cooldown(kind)),desc]

# Stat tiers SSS..G (producer 2026-11-03: ten tiers). S keeps the old S value and G is the old floor
# (old E: nothing below it means anything); A..F split that span evenly, SS/SSS sit above S. Every troop, tower and lord stat uses exactly one of these values, so the same tier always
# means the same number. Interval is seconds per hit (lower = faster).
# Use tier_index()/tier_value() instead of raw array positions: positions moved when tiers were added.
const TIER_NAMES := ["SSS","SS","S","A","B","C","D","E","F","G"]
const TIERS := {
	"radius":[760.0,470.0,290.0,210.0,150.0,100.0,75.0,52.0,37.0,26.0], # S spans 5 x 5 cells
	"area_damage":[2400.0,1200.0,600.0,370.0,230.0,140.0,90.0,55.0,35.0,20.0], # spells and explosions
	"damage":[720.0,360.0,180.0,130.0,95.0,70.0,50.0,36.0,26.0,20.0], # producer 2026-11-05: G = 20, A-F between S and G as whole numbers
	"hp":[6000.0,3000.0,1500.0,900.0,560.0,350.0,210.0,130.0,80.0,50.0],
	"range":[531.0,472.0,413.0,354.0,295.0,236.0,177.0,118.0,59.0,0.0], # cells x 118: 4.5 4 3.5 3 2.5 2 1.5 1 0.5 0 (2026-11-19: 0.5-cell steps across half the 9-cell field)
	"speed":[360.0,240.0,160.0,120.0,90.0,65.0,50.0,36.0,27.0,20.0],
	"interval":[0.18,0.27,0.4,0.5,0.65,0.85,1.1,1.4,1.9,2.4],
	"cooldown":[0.3,5.0,10.0,15.0,20.0,25.0,30.0,40.0,50.0,60.0],
}
# What each tier is for, per stat (same order as TIER_NAMES). docs/數值檔次.md lists the cards on each tier.
# SSS and SS are reserved for bosses, walls, siege engines and lord skills; troop cards normally stop at S.
const TIER_NOTES := {
	"cooldown":["極速輪轉","高速輪轉","快攻補兵","快速補充","短冷卻","標準輪轉","中等冷卻","較長冷卻","長冷卻","慢速補充"],
	"hp":[
		"最終 BOSS：關卡魔王專用，整場戰役合力才打得倒",
		"頂級城牆：要一整支軍隊圍攻才拆得掉",
		"優質肉盾：重裝前排與重型器械",
		"主坦・英雄：能單獨扛住一路",
		"精英重兵：比重型單位再硬一截",
		"重型單位：標準建築與重兵",
		"中堅：能挨幾下的二線兵與支援",
		"標準步兵：一對一能互換的基本兵",
		"人海：一張牌給好幾個，各自能挨一兩下",
		"蟲群：單隻不算數，只看總量，範圍法術的獵物"],
	"damage":[
		"魔王必殺：一擊打死所有部隊",
		"處決：一兩下拆掉城牆",
		"破城：重型攻城",
		"重擊：主坦與強攻型領主的普攻",
		"精英：比主戰再痛一截",
		"主戰：穩定的主力輸出",
		"普通兵：標準近戰",
		"小隊長：比輕攻擊強一點的雜兵頭目",
		"輕攻擊：單發不痛，靠人數堆傷害",
		"自衛・騷擾：支援角色防身、拆沒人顧的田"],
	"area_damage":[
		"天災：清空全場",
		"毀滅：一發清掉主坦群",
		"大招：燒平建築、領主技能",
		"強力清場：清掉中堅群",
		"重型清群：清掉人海與步兵",
		"標準清群：一發清掉蟲群與人海",
		"拋射：削血不秒殺，也拿來削建築",
		"削弱：連續命中才有用",
		"持續傷害：毒霧每一跳",
		"附帶：控場效果順便造成的傷害"],
	"radius":[
		"全場：幾乎蓋住整個戰場",
		"半場：蓋住大半個戰場",
		"巨型：約 5×5 格",
		"大型：約 3×3 格",
		"中大型：一路加左右各一路",
		"標準法術：一路加左右各半路",
		"小型：落點周圍一小團",
		"單格：只打一格",
		"腳下：只影響自己站的位置",
		"觸發點：陷阱踩到才發動的距離"],
	"range":[
		"4.5 格：跨越半張地圖（保留，或經偵查增程後的超遠程）",
		"4 格：超遠程攻城與直線重弩（投石車、重弩塔）",
		"3.5 格：長程射手，長弓、火槍、星儀行砲與法師領主",
		"3 格：標準遠程，弓弩、主力法師與砲擊",
		"2.5 格：中程遠程、投擲與噴射",
		"2 格：短投擲、治療、鐘聲與防禦塔",
		"1.5 格：近戰領主",
		"1 格：長兵器，槍戟鐮刀",
		"0.5 格：短兵器，刀劍爪牙",
		"0 格：貼身，衝撞啃咬自爆"],
	"speed":[
		"瞬移級：一眨眼橫越戰場",
		"疾風：超高速突襲",
		"極速：飛行突襲",
		"衝鋒：騎乘與衝撞",
		"輕騎：比輕裝再快一截",
		"敏捷：輕裝快攻",
		"標準：一般行軍",
		"緩慢：遠程與支援",
		"笨重：重裝前排",
		"攻城器：最慢，推著走的器械"],
	"interval":[
		"暴風連擊：一秒五下以上",
		"連擊：一秒三四下",
		"極快：快攻專精",
		"快攻：一秒兩下",
		"快速：小傷害高頻",
		"偏快：輕裝步兵",
		"標準：約一秒一下",
		"稍慢：穩扎穩打",
		"重擊：蓄力一下很痛",
		"攻城：一下拆一大塊"]
}

# Tier letter of a stat value, or "" when the value is off the tier table.
static func tier(stat: String, value: float) -> String:
	for i: int in range(TIER_NAMES.size()):
		if is_equal_approx(TIERS[stat][i],value): return TIER_NAMES[i]
	return ""

# Position of a tier letter in TIER_NAMES (lower = stronger), and the value of a stat at that tier.
static func tier_index(tier_name: String) -> int:
	return TIER_NAMES.find(tier_name)

static func tier_value(stat: String, tier_name: String) -> float:
	return TIERS[stat][tier_index(tier_name)]

# Note for a stat value's tier, e.g. tier_note("hp",1500.0) -> "優質肉盾：...".
static func tier_note(stat: String, value: float) -> String:
	var index := tier_index(tier(stat,value))
	return TIER_NOTES[stat][index] if index >= 0 and TIER_NOTES.has(stat) else ""

const MILL_BONUS := 2.0
const HARVEST_TIME := 15.0 # 豐收 doubles farms this long; no instant payout since 2026-10-30
const HEAL_RADIUS := 100.0 # radius tier C
const HEAL_AMOUNT := 50.0
const HEAL_INTERVAL := 2.4
# One charge rule for every charging troop (2026-11-20): the charge hit deals x CHARGE_MULT, knocks the
# target back and stuns it briefly; the charge comes back after CHARGE_RESET_TIME s of marching.
const CHARGE_MULT := 2.0
const CHARGE_KNOCKBACK := 30.0
const CHARGE_STUN := 0.5
const OX_BUILDING_BONUS := 1.5
const CHARGE_RESET_TIME := 3.0
const FIRE_KNOCKBACK := 20.0

# Text shares the data used by combat; optional tables let tests exercise future balance edits.
# A range in pixels as cells: "5 格", "0.5 格", "貼身".
static func cells_text(px: float) -> String:
	if px <= 0.0: return "貼身"
	return "%s 格" % number(snappedf(px/CELL_WIDTH,0.25))

# Grid blasts (2026-11-19): explosions hit whole cells, like spells do. The impact's cell is the
# centre; "cell" 1 格, "cross" 十字 5 格, "square" 九宮格, "rowN" N 格 along the lane away from the
# attacker. Gates count as the cell just past each end of their lane.
const BLAST_NAMES := {"cell":"單格","cross":"十字","square":"九宮格"}

static func blast_offsets(shape: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	match shape:
		"cross": out.append_array([Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)])
		"square":
			for dx: int in [-1,0,1]:
				for dy: int in [-1,0,1]:
					if dx != 0 or dy != 0: out.append(Vector2i(dx,dy))
		_:
			if shape.begins_with("row"):
				for n: int in range(1,int(shape.trim_prefix("row"))): out.append(Vector2i(n,0))
	return out

static func blast_text(shape: String) -> String:
	if shape.begins_with("row"): return "一行 %d 格" % int(shape.trim_prefix("row"))
	return BLAST_NAMES.get(shape,shape)

static func grid_cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),-1,L.GRID_COLUMNS),clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1))

static func actor_grid_cell(a: Dictionary) -> Vector2i:
	if a.has("cell"): return a.cell
	var c := grid_cell_at(a.pos)
	return Vector2i(c.x,int(a.get("lane",c.y)))

# forward: +1 when the attacker is red (team 0), -1 when blue, so rows run away from the attacker.
static func blast_hits(center: Vector2, shape: String, forward: int, target: Dictionary) -> bool:
	var c := grid_cell_at(center)
	var t := actor_grid_cell(target)
	for o: Vector2i in blast_offsets(shape):
		if c+Vector2i(o.x*forward,o.y) == t: return true
	return false

static func blast_hits_gate(center: Vector2, shape: String, forward: int, side: int, lane: int) -> bool:
	var c := grid_cell_at(center)
	var gate := Vector2i(-1 if side == 0 else L.GRID_COLUMNS,lane)
	for o: Vector2i in blast_offsets(shape):
		var cell := c+Vector2i(o.x*forward,o.y)
		if cell == gate or (cell.y == lane and ((side == 0 and cell.x <= -1) or (side == 1 and cell.x >= L.GRID_COLUMNS))): return true
	return false

# Whole numbers read as "350", not "350.0" (2026-11-19 polish); fractions keep up to 2 digits.
static func number(value: float) -> String:
	return String.num(value,2).trim_suffix(".0")

static func troop_description(kind: String, count: int, cards: Dictionary, include_name: bool = true) -> String:
	var d: Dictionary = cards[kind]
	var stats := "生命 %s、傷害 %s／%s 秒、射程 %s、移速 %s。" % [number(d.hp),number(d.damage),number(d.interval),cells_text(d.range),number(d.speed)]
	if include_name: return "%s ×%d：每名%s" % [d.name,count,stats]
	return stats if count == 1 else "%d 名：每名%s" % [count,stats]

static func card_description(kind: String, cards: Dictionary = CARDS) -> String:
	var d: Dictionary = cards[kind]
	var lines: Array[String] = ["召喚限定" if d.get("summon_only",false) else "%s 金幣 · 冷卻 %s 秒" % [number(d.cost),number(d.cooldown)]]
	if d.type == "unit":
		if d.has("members"):
			for group: Array in d.members:
				lines.append(troop_description(group[0],group[1],cards,true))
			for group: Array in d.members:
				var md: Dictionary = cards[group[0]]
				if group[0] != kind and md.has("ward_share"): lines.append("%s結界：身邊 %s 範圍內的友軍受到傷害時，%d%% 改由最近的%s承受；構裝，工匠會優先修補且免疫毒蝕。" % [md.name,number(md.ward_radius),int(md.ward_share*100),md.name])
		else: lines.append(troop_description(kind,d.count,cards,false))
		if d.get("spread",false): lines.append("三路各 %d 名，共 %d 名。" % [d.count,d.count*3])
		var foot: String = preload("res://grid_rules.gd").footprint_text(kind)
		if not foot.is_empty(): lines.append(foot)
		if d.get("mechanical",false): lines.append("機械單位：免疫毒蝕。")
	elif d.type == "building":
		lines.append("生命 %s；永久存在，同種建築覆蓋可補滿生命。" % number(d.hp))
		if d.has("damage"): lines.append("傷害 %s／%s 秒、射程 %s。" % [number(d.damage),number(d.interval),cells_text(d.range)])
		var reach_line: String = preload("res://grid_rules.gd").reach_text(kind)
		if not reach_line.is_empty(): lines.append(reach_line)
	else:
		if d.get("rolling",false): lines.append("直線滾動半徑 %s；落下時間 %s 秒。" % [number(d.radius),number(SPELL_DELAY)])
		else:
			var sh := spell_shape(d)
			lines.append("範圍 %d×%d 格（%s）；落下時間 %s 秒。" % [sh.x,sh.y,spell_shape_tag(sh),number(SPELL_DELAY)])
		if d.has("damage"): lines.append("部隊傷害 %s、建築傷害 %s、城牆傷害 %s。" % [number(d.damage),number(d.building_damage),number(d.gate_damage)])
	lines.append_array(expansion_description(d))
	if d.get("pay_all",false): lines = preload("res://gold_monster.gd").describe()
	lines.append_array(preload("res://seal_altar.gd").describe(kind))
	lines.append_array(preload("res://core_cards.gd").describe(kind))
	match kind:
		"glutton_nest": lines.append("不會定時產金；隱藏時免傷，敵我地面部隊進入 %s 範圍會顯形並張嘴 %s 秒，之後吞噬周圍 %s 內最多 %d 名敵我地面部隊（優先吞噬最近敵軍，不足時再補吞最近友軍；不含領主、飛行與相位；目前生命大於 %s 只造成 %s 傷害，吞噬我方部隊計為 %s 倍飼料）。依本次飼料總量換金：首枚 %s 血，其後每枚多 %s 血，不足不計，有吞到部隊額外 +%d 金；金幣會在咀嚼過程中持續分批產出（非一次獲得），消化中途被毀則不產出剩餘金幣。消化時間為 %s 秒加上本次每枚金幣 %s 秒；閉嘴時可被攻擊；吞到部隊後每 %s 秒咀嚼恢復 %s 生命，不超過最大生命，消化後再隱藏。" % [number(d.trigger_radius),number(d.windup),number(d.radius),int(d.bite_max),number(d.bite_cap),number(d.bite_cap),number(d.ally_feed_mult),number(d.gold_first),number(d.gold_step),int(d.gold_bonus),number(d.digest_time),number(d.digest_per_gold),number(d.chew_period),number(d.chew_heal)])
		"manor_retainer": lines.append("在本路己方領地巡邏，邊緣折返、遇敵作戰。失去領地便返回最近己方格；整路失守則原地防守。")
		"axe_thrower": lines.append("投出飛斧，命中時無視護甲減傷；不無視其他減傷效果。")
		"mana_spring": lines.append("範圍內每座我方水晶立刻產出一次金幣，並回滿生命；範圍內沒有水晶時不能施放。")
		"chain_lightning": lines.append("擊中落點最近的敵方部隊或建築造成 %s 傷害，再跳向附近未被擊中的敵方部隊或建築，最多 %d 次，每跳傷害小一檔；不打城牆與領主。" % [number(d.bolt_damage),int(d.hops)])
		"arcane_shield": lines.append("範圍內我方部隊獲得 %s 點永久護盾；護盾先吸收傷害，重複施放可累加。" % number(d.shield))
		"time_field": lines.append("力場持續 %s 秒，使區域內敵軍部隊移速與攻速減半（攻擊間隔延長至 2 倍）；敵方建築攻擊與生產速度減半。" % number(d.duration))
		"charge_horn": lines.append("施放的那一路我方部隊移速與攻速各提高一檔（最高 S），持續 %s 秒；與戰鼓、其他號令等加速疊加。" % number(d.duration))
		"levy": lines.append("我方領地內每有 1 名敵方地面部隊，就在它前方召喚 1 名民兵；這些民兵移速與攻速各提高一檔（可與其他加速疊加），離開我方領地即消失。領地內沒有敵人時不能施放。")
		"net_hunter": lines.append("命中的地面敵人被網住 %s 秒，移速與攻速減半；重複命中只刷新時間。" % number(d.net_slow))
		"watchtower": lines.append("範圍內進行偵查，潛行敵人現形並永久失去潛行；範圍內我方會射擊的部隊與箭樓射程提高一檔。本身不攻擊。")
		"sacrifice": lines.append("對範圍內所有我方部隊造成等同目前生命的真實傷害（目前生命大於 %s 只造成 %s 傷害；正常觸發死亡效果）。依本次造成總傷害換金（貪食巢穴雙倍轉換率）：首枚 %s 血，其後每枚多 %s 血，不足不計；並且每扣 5 點生命換 1 點領主技能充能。同時引發血祭爆裂，對範圍內敵方部隊造成獻祭總傷害 %d%% 的傷害（最低 %s、最高 %s）並使其減速 %s 秒。範圍內沒有我方部隊時不能施放。" % [number(d.bite_cap),number(d.bite_cap),number(d.gold_first),number(d.gold_step),int(d.blast_share*100),number(d.blast_min),number(d.blast_max),number(d.slow_duration)])
		"dread_howl": lines.append("對範圍內敵方部隊造成 %s 傷害，並使其轉身往自己城牆逃跑且減速 %s 秒（期間不攻擊、受傷害 ×%s 破膽，期間死亡將化為我方骷髏兵）；範圍內我方部隊移速與攻速升一檔 4 秒以利追擊。" % [number(d.enemy_damage),number(d.duration),number(d.terror_mult)])
		"mass_grave": lines.append("每 %s 秒爬出 %d 隻骷髏兵；本路每名敵我部隊死亡，提前 %s 秒，超出的時間不保留。" % [number(d.period),int(d.spawn_count),number(d.death_advance)])
		"blood_tower": lines.append("平時每秒存 %s 點血，本路每死 1 名部隊 +%s；以每秒 %s 點平均治療本路受傷友軍。存量歸零後要超過 %s 才重新輸出，上限 %s。" % [number(d.blood_rate),number(d.blood_per_death),number(d.heal_rate),number(d.restart_at),number(d.blood_max)])
		"borrowed_bones": lines.append("在落點召喚 %d 隻骷髏兵，%s 秒後回到棺裡消失（不算死亡）；歸還時每隻在%s範圍骨爆，造成 %s 傷害。" % [int(d.summon_count),number(d.summon_life),blast_text(d.blast),number(d.return_blast)])
		"grave_exchange": lines.append("拆掉範圍內我方建築（常駐牌除外），每座退還一半費用並冒出 %d 隻骷髏兵。範圍內沒有可拆建築時不能施放。" % int(d.skeletons))
		"mourning_shroud": lines.append("範圍內我方部隊 %s 秒內第一次受到致命傷時保留 1 生命。" % number(d.duration))
		"sealed_coffin": lines.append("範圍內敵方地面部隊陷入封棺暈眩 %s 秒：不能移動也不能攻擊。" % number(d.root))
		"powder_barrel": lines.append("敵方地面部隊踩上時爆炸一次：%s範圍造成 %s 傷害，之後消失。" % [blast_text(d.blast),number(d.explosion_damage)])
		"rolling_boulder": lines.append("只能放在每路我方第一格，以速度 %s 從我方領主身前滾完整路到敵方城牆（不會撞到我方領主）。傷害沿途敵我部隊、建築及領主，每個目標一次；撞門後碎裂，不直接獲勝。" % number(d.roll_speed))
		"summon_trap": lines.append("敵方地面部隊踩入 %s 範圍時，召喚 %d 隻%s並在%s範圍造成 %s 奧術衝擊；共可觸發 %d 次。同一名敵兵只觸發一次，同時踩入的一群只消耗一次。飛行與相位單位不觸發。" % [number(d.trigger_radius),d.summon_count,cards[d.summon_kind].name,blast_text(d.blast),number(d.summon_blast),d.charges])
		"chimera": lines.append("由召喚法陣召喚的地面近戰部隊；不能直接加入牌組。")
		"dark_wizard": lines.append("致命傷害時吞噬 3×3 格內最近的友方部隊，以其最大生命續命，可反覆觸發。領主、建築與未登場者除外。")
		"blink_blade": lines.append("每次受傷向前閃現 %s 格，優先攻擊前方；不能越過城牆。" % number(d.blink_step))
		"arcane_golem": lines.append("每座友方水晶減傷 %s%%，最多 %s%%；構裝單位，工匠可修補且免疫毒蝕。死亡時對%s內敵兵造成 %s 傷害。" % [number(d.resonance*100),number(d.resonance_max*100),blast_text(d.blast),number(d.explosion_damage)])
		"arcane_archer": lines.append("光箭飛行 %s 秒，貫穿本路 %s（索敵距離的 %s 倍）的敵方部隊、建築與城牆；可對空，命中進行偵查（永久失去潛行）。" % [number(ARROW_TIME),cells_text(d.range*d.pierce_range_multiplier),number(d.pierce_range_multiplier)])
		"chronomancer": lines.append("落點半徑 %s 造成 %s 傷害，敵兵暈眩 %s 秒；不縮短既有暈眩。" % [number(d.radius),number(d.area_damage),number(d.stun_on_hit)])
		"phase_rider": lines.append("登場時潛行穿陣，無法被敵方直接鎖定且不觸發陷阱；發動攻擊或被偵查時，永久失去潛行。範圍傷害仍可命中。")
		"artificer": lines.append("無敵人在攻擊距離內時，優先跟隨修補距離 %s 內受損最多的構裝（奧術魔像、結界護衛），否則維修友方建築，每 %s 秒恢復 %s 生命；不復活已摧毀建築。" % [number(d.repair_range),number(d.repair_interval),number(d.repair_amount)])
		"crystal": lines.append("每次產出 %s 金幣並損失最大生命的 %s%%，自身耗損最低留 1 生命。產出間隔隨生命降低由 %s 秒延長至 %s 秒；維修可恢復效率，敵人仍能摧毀。" % [number(d.income),number(d.decay_fraction*100),number(d.period),number(d.max_period)])
		"teleport_trap": lines.append("敵方地面部隊踩入 %s 範圍後觸發（可傳送 %s 次），將 %s 範圍內敵方地面部隊送回本路的敵方起點，並使被傳送敵軍暈眩且移速與攻速減半 %s 秒。不阻擋或吸引普攻。" % [number(d.trigger_radius),number(d.get("charges",3)),number(d.radius),number(d.get("stun_duration",10.0))])
		"blast_trap": lines.append("敵方地面部隊踩入 %s 範圍後爆炸（可爆炸 %s 次），對%s內敵方地面部隊造成 %s 傷害；同一名敵兵只會觸發同一座法陣一次。不阻擋或吸引普攻。" % [number(d.trigger_radius),number(d.get("charges",3)),blast_text(d.blast),number(d.explosion_damage)])
		"arcane_tower": lines.append("每 %s 秒攻擊攻擊範圍內敵軍，對落點%s內敵方部隊造成 %s 範圍傷害，可對空。" % [number(d.interval),blast_text(d.blast),number(d.area_damage)])
		"eyewing_dragon": lines.append("登場時與之後每 %s 秒吼叫一次，半徑 %s 內敵方部隊轉身往自己城牆逃跑 %s 秒，期間不攻擊。" % [number(d.get("roar_period",5.0)),number(d.radius),number(d.roar_fear)])
		"belly_eye": lines.append("半徑 %s 內進行偵查，潛行敵人現形並永久失去潛行。" % number(d.reveal_radius))
		"fishbeak": lines.append("主動換路尋找最近的敵人（部隊、建築或領主）發動攻擊；同一路無敵人時不被侷限。")
		"bearded_imp": lines.append("每次打中敵方建築或城牆，從敵方偷走 %s 金幣給我方；敵方沒錢時偷不到。" % number(d.steal_gold))
		"hooknose_flyer": lines.append("飛行：近戰部隊與建築打不到它，遠程、箭樓與領主仍可攻擊。它會攻擊地面部隊。")
		"long_dragon": lines.append("吐出火焰，沿本路往前燒 %s，途中每名敵方部隊各受一次傷害。" % cells_text(d.range*d.pierce_range_multiplier))
		"thorn_dragon": lines.append("每次被近戰部隊打中，攻擊者受到 %s 反傷；遠程、法術與領主不會被刺傷。" % number(d.thorns))
		"barricade": lines.append("沒有特殊效果。不攻擊、不產金、不反傷；依一般建築規則提供領地。")
		"bandit": lines.append("登場時潛行，敵方部隊與建築無法直接鎖定（領主看得見）；發動攻擊後現形，脫戰持續移動 %s 秒後再次潛行（被偵查揭露則永久失去潛行）。範圍傷害仍可命中。" % number(CHARGE_RESET_TIME))
		"corpse_giant": lines.append("生命每減少 %d%%（含死亡）就在原地爆出 %d 名骷髏兵；自身死亡仍會加速墓碑並觸發吞噬。" % [int(d.burst_step*100),int(d.burst_count)])
		"curse": lines.append("範圍內所有部隊（含我方）受到永久詛咒；死亡時在原地變成我方骷髏兵。")
		"catapult": lines.append("攻擊本路 %s～%s 內最遠敵方部隊、建築或城牆；每 %s 秒拋射，%s 秒後落地，對落點%s內敵方部隊、建築與城牆造成 %s 範圍傷害。落點不追蹤移動。" % [cells_text(d.min_range),cells_text(d.range),number(d.interval),number(d.flight_time),blast_text(d.blast),number(d.area_damage)])
		"drummer": lines.append("登場時與之後每 10 秒擊鼓，全場友軍（不含自身）移速與攻速各升一檔，持續 3 秒，最高 S。多名戰鼓手的鼓聲重疊時各算一檔，可與其他加速疊加。")
		"shieldguard": lines.append("每次受到傷害減少 %s，最低仍受 1 傷害。" % number(d.armor))
		"grave": lines.append("每 %s 秒產出 %s 金幣；本路每名敵我部隊死亡，提前 %s 秒，超出的時間不保留。" % [number(d.period),number(d.income),number(d.death_advance)])
		"ghoul": lines.append("半徑 %s 內每名敵我部隊死亡，回復 %s 生命，攻擊升一檔，最高 A 檔 %s。" % [number(d.radius),number(d.devour_heal),number(tier_value("damage",d.max_damage_tier))])
		"necromancer": lines.append("進場時前排三路各帶 1 名骷髏兵（出場時不額外召喚）；之後每 %s 秒，在本路與相鄰兩路同一欄各召喚 %d 名骷髏兵。" % [number(d.summon_interval),d.summon_per_lane])
		"reaper": lines.append("揮鐮直劈：每次攻擊也打中目標那一欄、本路與上下相鄰兩路的所有敵兵與敵方建築。")
		"raven": lines.append("飛越近戰部隊，只攻擊建築、城牆與敵方領主，優先本路農田；遠程與領主仍可攻擊它。")
		"plague": lines.append("毒霧持續 %s 秒，每 %s 秒對非機械敵兵疊加 1 層毒蝕（每層每秒 %s 傷害，可無限疊加），離開毒霧後仍持續 2 秒；毒死的敵兵產生半徑 %s、持續 %s 秒的小毒霧。對建築與機械單位無效。" % [number(d.duration),number(d.tick_interval),number(d.tick_damage),number(d.spread_radius),number(d.spread_duration)])
		"bonewall": lines.append("不具攻擊力；每失去 20% 生命在後方安全位置召喚 2 隻骷髏兵守護，被摧毀時不爆炸。")
		"farm": lines.append("常駐卡，不輪轉。種下 %s 秒後啟動，每 %s 秒產出 %s 金幣（未加成）。" % [number(FARM_START),number(FARM_INTERVAL),number(FARM_DROP)])
		"farmer": lines.append("順路耕田 %s 秒，農田回復 %s 生命，%s 秒內產出加倍。" % [number(CULTIVATE_TIME),number(FARMER_HEAL),number(BOOST_TIME)])
		"mill": lines.append("同一路農田產出 ×%s；多座磨坊、耕田、豐收的加成相乘疊加。" % number(MILL_BONUS))
		"scarecrow": lines.append("將周圍九宮格（本路與相鄰兩路、前後各一欄）內的敵兵吸引至同一路，敵兵會先換完行再優先攻擊稻草人（不會斜向攻擊），包括烏鴉。")
		"harvest": lines.append("範圍內農田持續 %s 秒產出加倍（不會立刻產出）；與耕田、磨坊的加成相乘疊加。" % number(HARVEST_TIME))
		"fire": lines.append("敵方部隊擊退 %s。" % number(FIRE_KNOCKBACK))
		"ox": lines.append("建築與城牆傷害 ×%s。" % number(OX_BUILDING_BONUS))
		"healer", "guard": lines.append("草藥婆每 %s 秒為半徑 %s 內友軍部隊回復 %s 生命，並減輕 1 層毒蝕。" % [number(HEAL_INTERVAL),number(HEAL_RADIUS),number(HEAL_AMOUNT)])
		"ram": lines.append("攻城槌只打建築、城牆與敵方領主，民兵在前護送；破門後拆完殘垣再前進。")
		"hunter", "spearbow": lines.append("獵戶箭矢飛行 %s 秒，命中才扣血。" % number(ARROW_TIME))
	return "\n".join(lines)

static func expansion_description(d: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if not d.get("expansion",false): return lines
	if d.get("ignore_armor",false): lines.append("攻擊無視護甲減傷。")
	if d.get("lane_shooter",false): lines.append("僅直線射擊本路前方的敵軍，命中路徑上的第一個目標。")
	if d.get("stealth",false): lines.append("登場時潛行，敵方部隊與建築無法直接鎖定（領主看得見）；脫戰持續移動 %s 秒後再次潛行（被偵查揭露則永久失去潛行）。" % number(CHARGE_RESET_TIME))
	if d.has("net_slow"): lines.append("命中使敵軍移速與攻速減半 %s 秒。" % number(d.net_slow))
	if d.has("reveal_radius"): lines.append("揭露 %s 範圍內的潛行敵軍。" % number(d.reveal_radius))
	if d.has("regen_amount"): lines.append("每 %s 秒恢復 %s 生命（脫戰持續移動 %s 秒後恢復量 ×1.5），不超過最大生命。" % [number(d.period),number(d.regen_amount),number(CHARGE_RESET_TIME)])
	if d.get("charge",false): lines.append("衝鋒：衝鋒時移速升一檔，衝鋒一擊造成 ×%s 傷害並擊退、暈眩 %s 秒；脫戰持續移動 %s 秒後再次衝鋒。" % [number(CHARGE_MULT),number(CHARGE_STUN),number(CHARGE_RESET_TIME)])
	if d.has("income"): lines.append("每 %s 秒產出 %s 金幣。" % [number(d.period),number(d.income)])
	if d.has("store_per_farm") and d.has("store_max"): lines.append("每當己方農田產出時累積 %s 金幣；累積滿 %s 金幣或死亡時放出。" % [number(d.store_per_farm),number(d.store_max)])
	if d.has("spawn_kind") and d.has("period"):
		if d.get("spawn_on_build",false): lines.append("建造完成時立即召喚 %d 名%s，之後每 %s 秒再召喚 %d 名。" % [d.spawn_count,CARDS[d.spawn_kind].name,number(d.period),d.spawn_count])
		else: lines.append("每 %s 秒召喚 %d 名%s。" % [number(d.period),d.spawn_count,CARDS[d.spawn_kind].name])
	if d.get("shuttle",false): lines.append("不攻擊；往返我方領地邊界與城門，依距離獲得等差金幣（%s、%s、%s、%s…），到家休息 %s 秒；被擊殺時敵方得 %s 金幣。" % [number(d.shuttle_base),number(d.shuttle_base+d.shuttle_step),number(d.shuttle_base+d.shuttle_step*2),number(d.shuttle_base+d.shuttle_step*3),number(d.shuttle_rest),number(d.shuttle_loot)])
	if d.has("kill_income"): lines.append("親手擊殺敵方部隊時得 %s 金幣。" % number(d.kill_income))
	if d.has("damage_roll"): lines.append("每次攻擊傷害在 %s 到 %s 之間隨機。" % [number(tier_value("damage",d.damage_roll[0])),number(tier_value("damage",d.damage_roll[1]))])
	if d.has("structure_mult"): lines.append("攻擊建築與城門時傷害 ×%s。" % number(d.structure_mult))
	if d.has("bonus_vs"):
		for f: String in d.bonus_vs: lines.append("攻擊%s時傷害 ×%s。" % ["領主" if f == "lord" else FACTIONS[f]+"陣營",number(d.bonus_vs[f])])
	if d.has("spell_resist"): lines.append("受到法術傷害 ×%s。" % number(d.spell_resist))
	if d.has("lifesteal"): lines.append("造成傷害的 %d%% 回復自身生命。" % int(d.lifesteal*100))
	if d.get("last_stand",false): lines.append("第一次受到致命傷時保留 1 生命。")
	if d.has("stun_on_hit") and not d.get("expansion_spell",false): lines.append("每次攻擊造成半徑 %s 範圍傷害 %s，並使範圍內敵軍暈眩 %s 秒。" % [number(d.radius),number(d.area_damage),number(d.stun_on_hit)])
	if d.has("on_death_spawn"): lines.append("死亡時在原地召喚 %d 隻%s。" % [int(d.on_death_spawn[1]),CARDS[d.on_death_spawn[0]].name])
	if d.has("ally_death_spawn"):
		var who: String = "任何非%s部隊" % CARDS[d.ally_death_spawn].name if d.get("stitch_any_team",false) else "友軍"
		var cnt: int = int(d.get("stitch_count",1))
		var heal_s: String = "並自身回復 %s 生命" % number(d.stitch_heal) if d.get("stitch_heal",0.0) > 0.0 else ""
		lines.append("周圍 %s 範圍內有%s死亡時縫出 %d 名%s%s（每 %s 秒最多一次）。" % [number(d.radius),who,cnt,CARDS[d.ally_death_spawn].name,heal_s,number(d.stitch_cooldown)])
	if d.get("lob",false): lines.append("拋射：落點 %s 範圍造成 %s 傷害。" % [number(d.radius),number(d.area_damage)])
	if d.has("dot_damage"):
		if d.has("area_damage"):
			lines.append("咒彈命中時對半徑 %s 內敵方部隊造成 %s 傷害，並對非機械敵兵疊加 1 層毒蝕（每層每 %s 秒 %s 傷害，持續 %d 秒，可無限疊加，不傳染毒霧）。" % [number(d.radius),number(d.area_damage),number(d.dot_interval),number(d.dot_damage),int(d.dot_ticks)])
		else:
			lines.append("毒蜂命中時對非機械目標疊加 1 層毒蝕（每層每 %s 秒 %s 傷害，持續 %d 秒，可無限疊加）。" % [number(d.dot_interval),number(d.dot_damage),int(d.dot_ticks)])
	if d.get("suicide_blast",false): lines.append("碰到第一個目標就自爆：%s 範圍對部隊、建築與城門造成 %s 傷害，自身死亡。" % [number(d.radius),number(d.area_damage)])
	if d.has("death_income"):
		var every: String = ("，每 %s 秒最多一次" % number(d.period)) if d.get("period",0.0) > 0.0 else "（無冷卻）"
		var charge_s: String = ("並為領主技能充能 %s 點" % number(d.death_charge)) if d.has("death_charge") else ""
		lines.append("周圍 %s 範圍每有%s部隊死亡獲得 %s 金幣%s%s。" % [number(d.radius),"我方" if d.get("death_side","") == "ally" else "",number(d.death_income),charge_s,every])
	if d.get("well_heal_full",false): lines.append("經過周圍 %s 範圍內的友方部隊回復全部生命並獲得移速與攻速升一檔，持續 %s 秒（每名部隊每口井限一次）。" % [number(d.radius),number(d.duration)])
	if d.get("support","") == "slow": lines.append("每 %s 秒讓 %s 範圍內敵方地面部隊減速 %s 秒。" % [number(d.period),number(d.radius),number(d.duration)])
	elif d.get("support","") == "cleanse": lines.append("每 %s 秒敲鐘使 %s 範圍內友軍移速與攻速升一檔 %s 秒並淨化暈眩、減速、恐懼、定身與毒蝕；成功淨化時該友軍回復 %s 生命並使範圍內敵軍減速 1.5 秒。" % [number(d.period),number(d.radius),number(d.get("duration",2.4)),number(d.get("support_amount",50.0))])
	elif d.get("support","") == "tithe":
		var buff_s: String = "並賜予範圍內友軍 %s 秒移速與攻速升一檔及 25%% 吸血" % number(d.tithe_buff_sec) if d.get("tithe_buff_sec",0.0) > 0.0 else ""
		lines.append("持續從 %s 範圍內友軍每秒抽取 %s 生命（不會抽死），累積滿 %s 獲得 %s 金幣%s。" % [number(d.radius),number(d.tithe_dps),number(d.tithe_goal),number(d.tithe_gold),("，" + buff_s) if not buff_s.is_empty() else ""])
	elif d.has("support"):
		var effect: String = {"heal":"治療友軍","repair":"修復友方建築","shield":"友軍護盾","armor":"友軍護甲","haste":"友軍移速與攻速升一檔","range":"友軍遠程射程升一檔"}[d.support]
		lines.append("每 %s 秒對 %s 範圍施加%s%s%s；同類加成不疊加。" % [number(d.period),number(d.radius),effect,(" %s 點" % number(d.support_amount)) if d.has("support_amount") else "",("，持續 %s 秒" % number(d.duration)) if d.has("duration") else ""])
	if d.has("thorns"): lines.append("每次被近戰攻擊時反傷攻擊者 %s 點。" % number(d.thorns))
	if d.get("patrol",false): lines.append("在本路己方領地巡邏守衛。")
	if d.get("hits","") == "units": lines.append("不攻擊建築（城牆除外），只打部隊、領主與城牆。")
	if d.has("ward_share"): lines.append("結界：身邊 %s 範圍內的友軍受到傷害時，%d%% 改由最近的結界護衛承受。" % [number(d.ward_radius),int(d.ward_share*100)])
	if d.get("construct",false): lines.append("構裝：工匠會優先修補，且免疫毒蝕。")
	if d.has("blast"): lines.append("爆炸範圍：%s。" % blast_text(String(d.blast)))
	if d.get("flying",false): lines.append("飛行單位，地面近戰無法攻擊。")
	if d.get("phase",false): lines.append("相位單位，可穿過地面阻擋推進。")
	if int(d.get("strikes",1)) > 1: lines.append("每次攻擊連續出手 %d 次（三連擊）。" % int(d.strikes))
	if d.get("three_lane_target",false): lines.append("近戰但可直接鎖定本路與相鄰兩路的敵方目標。")
	if d.get("splash","") == "column": lines.append("每次攻擊橫掃本路與相鄰兩路（含同欄敵方建築）。" if not d.get("projectile",false) else "每次攻擊橫掃本路與相鄰兩路。")
	if d.has("depot_refund"): lines.append("本路打出部隊時返還 %s 金幣。" % number(d.depot_refund))
	if d.has("reflect_damage"): lines.append("受到攻擊時反彈 %s 傷害，冷卻 2 秒。" % number(d.reflect_damage))
	if d.has("max_charges"): lines.append("敵我施法時蓄能 1 次，上限 %d；被毀時每層返還 %s 金幣並造成 %s 範圍傷害。" % [int(d.max_charges),number(d.gold_per_charge),number(d.area_damage)])
	if d.has("pushback"): lines.append("蓄能待命，每 %s 秒將本路射程內所有敵方部隊（含飛行）擊退 %s、暈眩 %s 秒並造成 %s 傷害。" % [number(d.period),number(d.pushback),number(d.get("pulse_stun",1.0)),number(d.get("area_damage",0.0))])
	if d.get("split_on_kill",false): lines.append("擊殺敵軍時在原地分裂 1 隻同類單位。")
	if d.has("root_on_hit"): lines.append("攻擊命中使敵軍定身 %s 秒，冷卻 4 秒。" % number(d.root_on_hit))
	if d.get("scavenger",false): lines.append("周圍 %s 內有單位死亡時回復 %s 生命並提升攻擊檔次，最高 A 檔。" % [number(d.radius),number(d.scavenger_heal)])
	if d.get("ambush_hatch",false): lines.append("敵方地面部隊踏進%s範圍時立刻孵化。" % blast_text(d.blast))
	if d.has("hatch_time"): lines.append("存活 %s 秒或被擊破時孵化 %d 隻%s並對%s內敵兵造成 %s 傷害。" % [number(d.hatch_time),int(d.spawn_count),CARDS[d.spawn_kind].name,blast_text(d.blast),number(d.area_damage)])
	if d.has("crit_mult"): lines.append("每 %s 秒為 %s 內友軍回復 %s 生命，並強化下次攻擊傷害 ×%s。" % [number(d.period),number(d.radius),number(d.get("support_amount",36.0)),number(d.crit_mult)])
	if d.get("expansion_spell",false):
		if d.has("knockback"): lines.append("將範圍內敵軍擊退 %s。" % number(d.knockback))
		if d.get("lane_split_gather",false): lines.append("將範圍內敵方部隊擊退至相鄰道路，並使範圍內相鄰道路的我方部隊集中到施放這一路。")
		if d.has("tick_damage") and not d.has("spread_radius"): lines.append("在地面留下持續 %s 秒的火海，每秒造成 %s 傷害。" % [number(d.duration),number(d.tick_damage)])
		if d.has("enemy_damage") and not d.has("execute_hp"): lines.append("對範圍內敵軍造成 %s 傷害。" % number(d.enemy_damage))
		if d.has("stun_on_hit") and not d.get("pull_center",false): lines.append("使範圍內敵軍暈眩 %s 秒。" % number(d.stun_on_hit))
		if d.has("rally_haste_sec"): lines.append("解除範圍內友軍減速與定身，並獲得 %s 秒移速與攻速升一檔。" % number(d.rally_haste_sec))
		if d.has("drain_gold_per_hit"): lines.append("每命中 1 名敵軍抽取 %s 金幣，上限 %s。" % [number(d.drain_gold_per_hit),number(d.drain_gold_max)])
		if d.has("phase_shift"): lines.append("將範圍內友軍向前折躍並短暫相位 %s。" % number(d.phase_shift))
		if d.get("pull_center",false): lines.append("將範圍內敵軍拉向中心並暈眩 %s 秒。" % number(d.get("stun_on_hit",1.0)))
		if d.has("duration") and not d.has("tick_damage") and not d.has("support"): lines.append("複製範圍內最強友軍 1 名，幻影存在 %s 秒。" % number(d.duration))
		if d.has("hp_cost_share"): lines.append("消耗範圍內友軍 %d%% 當前生命，使攻擊傷害升一檔（最高 S），並獲得 6 秒移速與攻速升檔及 25%% 吸血。" % int(d.hp_cost_share*100))
		if d.get("strip_defences",false): lines.append("清除敵軍護盾與護甲、對非機械敵軍疊加 1 層毒蝕（每秒 20 傷害，持續 2 秒，可無限疊加），並以酸雨直接傷害敵方建築。")
		if d.get("grant_charge",false): lines.append("賦予範圍內我方部隊衝鋒，立即獲得衝鋒移速加成；下次攻擊造成 ×%s 傷害並擊退、暈眩 %s 秒（既有衝鋒者立刻重置衝鋒）。" % [number(CHARGE_MULT),number(CHARGE_STUN)])
		if d.has("ambush_spawn"): lines.append("並在本路我方領地最前端放出 %d 隻%s。" % [int(d.ambush_spawn[1]),CARDS[d.ambush_spawn[0]].name])
		if d.has("maw_targets"): lines.append("咬住範圍內生命最高的 %d 名敵方地面部隊，各造成 %s 傷害。" % [int(d.maw_targets),number(d.maw_damage)])
		if d.has("execute_hp"): lines.append("直接吞殺最多 %d 名生命 ≤ %s 的敵方地面部隊（每名得 %s 金幣），並對其餘敵軍造成 %s 傷害。" % [int(d.execute_max),number(d.execute_hp),number(d.execute_gold),number(d.get("enemy_damage",140.0))])
		if d.get("upgrade_hp",false): lines.append("將範圍內友方部隊最大與當前生命升一檔（最高 SS），且攻擊傷害升一檔（最高 S）。")
		if d.has("spawn_on_kill"): lines.append("被擊殺的敵軍原地召喚存在 %s 秒的%s。" % [number(d.spawn_life),CARDS[d.spawn_on_kill].name])
		if d.has("anti_air_mult"): lines.append("對飛行敵軍的傷害與暈眩時間 ×%s。" % number(d.anti_air_mult))
	return lines

# Body / collision radius (single source of truth): attack ranges & AoE checks extend from edges.
static func kind_radius(kind: String) -> float:
	if kind.is_empty() or kind == "gate": return 0.0
	if LORDS.has(kind):
		var hp: float = float(LORDS[kind].get("hp",0.0))
		return 26.0 if hp >= 3000.0 else (LORD_BODY_RADIUS if hp >= 1500.0 else 20.0)
	if MINION_LORDS.has(kind):
		var hp: float = float(MINION_LORDS[kind].get("hp",0.0))
		return 26.0 if hp >= 3000.0 else (LORD_BODY_RADIUS if hp >= 1500.0 else 20.0)
	var d: Dictionary = CARDS.get(kind,{})
	if d.is_empty(): return UNIT_BODY_RADIUS
	if d.has("body_radius"): return float(d.body_radius)
	if d.get("type","") == "building": return 0.0 if d.has("trap") else BUILDING_BODY_RADIUS
	return UNIT_BODY_RADIUS

static func actor_radius(actor: Dictionary) -> float:
	if actor.is_empty(): return 0.0
	if actor.has("body_radius"): return float(actor.body_radius)
	var k: String = actor.get("kind","")
	if k == "lord": return kind_radius(actor.get("lord","lion"))
	return kind_radius(k)

static func edge_distance(a: Dictionary, b: Dictionary) -> float:
	return maxf(0.0,a.pos.distance_to(b.pos)-actor_radius(a)-actor_radius(b))

static func point_edge_distance(point: Vector2, target: Dictionary) -> float:
	return maxf(0.0,point.distance_to(target.pos)-actor_radius(target))

# Grid-based spell footprint ([cols, rows]) and snapped battlefield Rect2.
static func spell_shape(d: Dictionary) -> Vector2i:
	if d.has("shape"):
		var s: Array = d.shape
		return Vector2i(clampi(int(s[0]),1,L.GRID_COLUMNS),clampi(int(s[1]),1,L.GRID_ROWS))
	var r := float(d.get("radius",100.0))
	if r >= 250.0: return Vector2i(3,3)
	if r >= 180.0: return Vector2i(3,3)
	if r >= 130.0: return Vector2i(3,2)
	return Vector2i(2,2)

static func spell_shape_tag(shape: Vector2i) -> String:
	if shape.y == 1: return "橫向直線"
	if shape.x == 1: return "縱向直線"
	return "方格區域"

static func spell_rect(pos: Vector2, d: Dictionary) -> Rect2:
	var sh := spell_shape(d)
	var cx := clampf((pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x,0.0,float(L.GRID_COLUMNS)-0.001)
	var cy := clampf((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y,0.0,float(L.GRID_ROWS)-0.001)
	var c0 := clampi(floori(cx-float(sh.x)*0.5+0.5),0,L.GRID_COLUMNS-sh.x)
	var r0 := clampi(floori(cy-float(sh.y)*0.5+0.5),0,L.GRID_ROWS-sh.y)
	return Rect2(L.GRID_ORIGIN+Vector2(float(c0)*L.CELL_SIZE.x,float(r0)*L.CELL_SIZE.y),Vector2(float(sh.x)*L.CELL_SIZE.x,float(sh.y)*L.CELL_SIZE.y))

static func rect_hits_point(rect: Rect2, point: Vector2, pad: float = 0.0) -> bool:
	return point.x >= rect.position.x-pad and point.x <= rect.end.x+pad and point.y >= rect.position.y-pad and point.y <= rect.end.y+pad

static func rect_hits_actor(rect: Rect2, target: Dictionary) -> bool:
	return rect_hits_point(rect,target.pos,actor_radius(target))

static func spell_hits_actor(pos: Vector2, d: Dictionary, target: Dictionary) -> bool:
	return rect_hits_actor(spell_rect(pos,d),target)

static func is_mechanical(kind: String) -> bool:
	var c: Dictionary = CARDS.get(kind,{})
	return c.get("mechanical",false) or c.get("construct",false)

static func poison_immune(target: Dictionary) -> bool:
	if target.is_empty() or target.has("cell"): return true
	var kind: String = String(target.get("kind",""))
	if kind == "gate": return true
	var c: Dictionary = CARDS.get(kind,{})
	return c.get("type","") == "building" or c.get("mechanical",false) or c.get("construct",false)
