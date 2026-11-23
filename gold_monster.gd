extends RefCounted
# 金幣怪物 (2026-11-17): a neutral unit that spends the whole purse (whole coins, 1..MAX_INK).
# How many bodies come out and each body's tiers depend only on the gold paid: B.GOLD_MONSTER_STAGES
# holds, for every gold amount, the tier combination whose cost-model value is closest to 100% of it, with one
# rule on top: one more coin never lowers a stat, except when it adds another body.
# Hooks: battle.play() (price), battle.deploy() (count + stats), enemy_ai (when), game/economy_hud (labels).
const B = preload("res://balance.gd")
const Upgrades = preload("res://card_upgrades.gd")

# The AI waits for a real monster instead of throwing out a 1-coin imp (24 = two 900-hp bodies);
# when a lane is being stormed it settles for a single 560-hp body.
const AI_SAVE_GOLD := 24.0
const AI_DEFEND_GOLD := 8.0
const REFUND_SHARE := 0.4

static func pays_all(kind: String) -> bool:
	return B.CARDS.get(kind,{}).get("pay_all",false)

# Whole coins spent: everything in the purse, at least the printed cost (1), at most MAX_INK.
static func price(ink: float) -> int:
	return clampi(int(floor(ink+0.000001)),1,int(B.MAX_INK))

# What play() takes from the purse for this card.
static func cost(m, team: int, kind: String) -> float:
	return float(price(m.ink[team])) if pays_all(kind) else float(B.CARDS[kind].cost)

# [min_gold, count, hp, damage, interval, speed] for this much gold.
static func stage(gold: int) -> Array:
	var best: Array = B.GOLD_MONSTER_STAGES[0]
	for s: Array in B.GOLD_MONSTER_STAGES:
		if gold >= int(s[0]): best = s
	return best

# deploy(): how many bodies come out.
static func shape(groups: Array, gold: int) -> void:
	groups[0][1] = int(stage(gold)[1])

# deploy(): each body's stats for this stage; run upgrades add additive percentages from stage values.
static func apply(u: Dictionary, gold: int, ups: Dictionary, body_index: int = 0, total_bodies: int = 0) -> void:
	var s: Array = stage(gold)
	u.base_hp = float(s[2])
	u.hp_pct = float(u.get("hp_pct",0.0))+Upgrades.stat_pct("hp",int(ups.get("hp",0)))
	u.max_hp = roundf(u.base_hp*maxf(0.1,1.0+float(u.hp_pct)))
	u.hp = u.max_hp
	u.damage = Upgrades.scaled("damage",float(s[3]),int(ups.get("damage",0)))
	u.damage_mult = 1.0+Upgrades.stat_pct("damage",int(ups.get("damage",0)))
	u.interval = float(s[4])
	u.speed = float(s[5])
	u.atk_speed_pct = float(u.get("atk_speed_pct",0.0))+Upgrades.stat_pct("interval",int(ups.get("interval",0)))
	u.speed_pct = float(u.get("speed_pct",0.0))+Upgrades.stat_pct("speed",int(ups.get("speed",0)))
	u.gold_paid = gold
	var bodies: int = total_bodies if total_bodies > 0 else maxi(1,int(s[1]))
	var total_refund: int = int(floor(float(gold)*REFUND_SHARE))
	var refund: int = int(total_refund / bodies) + (1 if body_index < (total_refund % bodies) else 0)
	u.death_refund = float(refund)

# Hand and purse labels: the medallion reads 全 and the purse whitens every coin it would take.
static func cost_text(kind: String, data: Dictionary) -> String:
	return "全" if pays_all(kind) else str(data.cost)

static func need(kind: String, ink: float) -> float:
	return float(price(ink)) if pays_all(kind) else float(B.CARDS[kind].cost)

# enemy_ai: skip the card until there is enough gold for it to matter.
static func ai_wait(kind: String, ink: float, defending: bool) -> bool:
	if not pays_all(kind): return false
	return ink < (AI_DEFEND_GOLD if defending else AI_SAVE_GOLD)

# Card text: a compact ladder instead of the 1-coin base stats.
static func describe() -> Array[String]:
	var lines: Array[String] = ["花光全部金幣（最多 %d）· 冷卻 %s 秒" % [int(B.MAX_INK),B.number(B.CARDS.gold_monster.cooldown)]]
	var marks: Array[String] = []
	for gold: int in [1,8,16,24,41,50]:
		var s: Array = stage(gold)
		marks.append("%d 金：%d 隻 生命 %s 傷害 %s" % [gold,int(s[1]),B.number(s[2]),B.number(s[3])])
	lines.append("金幣越多越強，隻數與數值取最接近所付金幣的組合：")
	lines.append("；".join(marks)+"。")
	lines.append("多 1 金幣不會讓任何數值變低，只有多分出一隻時重新分配。")
	lines.append("每隻陣亡時碎裂返還所付金幣的 %d%%（平分，1～2 金不返還；獻祭不觸發）。" % int(round(REFUND_SHARE*100.0)))
	return lines
