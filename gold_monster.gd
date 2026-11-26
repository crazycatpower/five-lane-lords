extends RefCounted
# 金幣怪物 (2026-11-17): a neutral unit that spends the whole purse (whole coins, 1..MAX_CARD_COST).
# How many bodies come out and each body's stats depend only on the gold paid: B.GOLD_MONSTER_STAGES
# has one row per gold amount, worth exactly 70% of it in the cost model, off-tier (tools/gold_monster_table.py,
# 使用者 2026-11-24). Each amount is a different form (迅捷 pack, 重裝 lump, 狂暴 pair, 蟲群 swarm, 疾行 runner,
# 均衡 soldiers), never the same twice in a row: one coin more can mean a completely different monster.
# Hooks: battle.play() (price), battle.deploy() (count + stats), enemy_ai (when), game/economy_hud (labels).
const B = preload("res://balance.gd")
const Upgrades = preload("res://card_upgrades.gd")

# The AI waits for a real monster instead of throwing out a 1-coin imp (24 gold is worth ~17 cost);
# when a lane is being stormed it settles for whatever 8 gold makes.
const AI_SAVE_GOLD := 24.0
const AI_DEFEND_GOLD := 8.0
const REFUND_SHARE := 0.4

static func pays_all(kind: String) -> bool:
	return B.CARDS.get(kind,{}).get("pay_all",false)

# Whole coins spent: everything in the purse, at least the printed cost (1), at most MAX_CARD_COST
# (the purse holds up to MAX_INK = 100 since 2026-11-24; the monster still tops out at 50).
static func price(ink: float) -> int:
	return clampi(int(floor(ink+0.000001)),1,B.MAX_CARD_COST)

# What play() takes from the purse for this card.
static func cost(m, team: int, kind: String) -> float:
	return float(price(m.ink[team])) if pays_all(kind) else float(B.CARDS[kind].cost)

# [gold, count, hp, damage, interval, speed, form] for this much gold (rows are 1..MAX_CARD_COST, one each).
static func stage(gold: int) -> Array:
	var best: Array = B.GOLD_MONSTER_STAGES[0]
	for s: Array in B.GOLD_MONSTER_STAGES:
		if gold >= int(s[0]): best = s
	return best

# deploy(): how many bodies come out.
static func shape(groups: Array, gold: int) -> void:
	groups[0][1] = int(stage(gold)[1])

# deploy(): each body's stats for this gold; run upgrades add additive percentages from these values.
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
	u.range_pct = float(u.get("range_pct",0.0))+Upgrades.stat_pct("range",int(ups.get("range",0)))
	u.gold_paid = gold
	var bodies: int = total_bodies if total_bodies > 0 else maxi(1,int(s[1]))
	var total_refund: int = int(floor(float(gold)*REFUND_SHARE))
	var refund: int = int(total_refund / bodies) + (1 if body_index < (total_refund % bodies) else 0)
	u.death_refund = float(refund)

# Hand and purse labels. In battle (ink >= 0) the medallion shows the live price, capped at
# MAX_CARD_COST (使用者 2026-11-24); outside battle it reads 全. The purse whitens every coin it would take.
static func cost_text(kind: String, data: Dictionary, ink: float = -1.0) -> String:
	if not pays_all(kind): return str(data.cost)
	return "全" if ink < 0.0 else str(price(ink))

static func need(kind: String, ink: float) -> float:
	return float(price(ink)) if pays_all(kind) else float(B.CARDS[kind].cost)

# enemy_ai: skip the card until there is enough gold for it to matter. pr = the AI weights
# (gm_save / gm_defend, searched by tools/evolve_ai.py; absent = the constants above).
static func ai_wait(kind: String, ink: float, defending: bool, pr: Dictionary = {}) -> bool:
	if not pays_all(kind): return false
	return ink < (float(pr.get("gm_defend",AI_DEFEND_GOLD)) if defending else float(pr.get("gm_save",AI_SAVE_GOLD)))

# "迅捷×3": the form and body count this much gold makes (hand tag in battle, card text).
static func form_text(gold: int) -> String:
	var s: Array = stage(gold)
	return "%s×%d" % [String(s[6]) if s.size() > 6 else "",int(s[1])]

const FORM_NOTES := {
	"迅捷":"一群快腿快嘴的小怪","重裝":"一隻慢吞吞的巨肉","狂暴":"兩隻高攻脆皮","蟲群":"五隻小蟲一擁而上",
	"疾行":"一隻飛奔的獨狼","均衡":"幾名普通金幣兵",
}

# Card text: the forms and a few sample amounts instead of the 1-coin base stats.
static func describe() -> Array[String]:
	var lines: Array[String] = ["花光全部金幣（最多 %d）· 冷卻 %s 秒" % [B.MAX_CARD_COST,B.number(B.CARDS.gold_monster.cooldown)]]
	lines.append("每個金額長成不同形態，多 1 金可能就完全變樣（手牌上會標出這次的形態）；總戰力約為所付金幣的七成，射程不變。")
	var notes: Array[String] = []
	for form: String in FORM_NOTES: notes.append("%s：%s" % [form,FORM_NOTES[form]])
	lines.append("；".join(notes)+"。")
	var marks: Array[String] = []
	for gold: int in [12,13,24,25,50]:
		var s: Array = stage(gold)
		marks.append("%d 金 %s 生命 %s 傷害 %s 移速 %s" % [gold,form_text(gold),B.number(s[2]),B.number(s[3]),B.number(s[5])])
	lines.append("例："+"；".join(marks)+"。")
	lines.append("每隻陣亡時碎裂返還所付金幣的 %d%%（平分，1～2 金不返還；獻祭不觸發）。" % int(round(REFUND_SHARE*100.0)))
	return lines
