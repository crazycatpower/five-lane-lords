# 金幣怪物逐金變形表產生器（2026-11-24，使用者：「不要分段，用計算每個金幣各種變量的最契合」「除了射程和費用都能變」
#   「隻數不用只增不減」「可能這費是多隻迅捷，下一費是單隻重裝；不要啥都強制遞增」）
#   python tools/gold_monster_table.py [比例=0.70] [亂數種子=1124]
# 1～50 金每一個金額長成一種「形態」，相鄰金額不重複；每種形態決定隻數與身材（生命、傷害、攻擊間隔、移速），射程、費用不動。
#   價值 = tools/autobalance.py 的部隊成本模型 ×(移速/36)^0.2；每個金額的總價值剛好 = 比例 × 金幣（整數化後誤差約 1%），
#          所以哪個金額都公平，只是長相完全不同、也不必比前一金強在每一項。
#   基準身材 = 從卡池近戰部隊擬合：傷害、攻擊間隔、移速各是生命的冪函數；形態再把它們乘上各自的倍率，最後解生命讓價值剛好。
#   1 金固定為卡面數值（130／36／1.9／36）。
# 印出的 GD: 那一行貼進 balance.gd 的 GOLD_MONSTER_STAGES（每列最後一格是形態名）。
import json, math, random, re, statistics as st, sys, os

K = float(sys.argv[1]) if len(sys.argv) > 1 else 0.70
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 1124
N = 50
BASE = (130.0, 36.0, 1.9, 36.0)          # the card's printed 1-coin stats
HP_FLOOR, HP_CAP = 50.0, 6666.0          # lowest tier body; a single brute never outgrows the biggest giant
SPEED = (20.0, 120.0)
INTERVAL = (0.4, 2.4)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# name: (damage x, interval x, speed x, body count for gold g)
FORMS = {
    "迅捷": (0.75, 0.60, 1.80, lambda g: min(5, max(3, 2 + g // 10))),   # a pack of quick biters
    "重裝": (1.40, 1.50, 0.70, lambda g: 1),                             # one slow, huge lump
    "狂暴": (1.90, 0.75, 1.25, lambda g: 2),                             # two glass-cannon brutes
    "蟲群": (0.55, 0.80, 1.00, lambda g: 5),                             # five frail crawlers
    "疾行": (1.20, 0.80, 2.50, lambda g: 1),                             # a lone runner
    "均衡": (1.00, 1.00, 1.00, lambda g: min(5, 1 + g // 12)),           # the plain coin-soldier
}

def V(c, hp, d, iv, sp):
    P = ((c ** 0.9) * (hp ** 0.45) * ((d / iv) ** 0.35) * 1.046) ** 0.9
    return (0.1747 * P - 2.55) * (sp / 36.0) ** 0.2

def pool():
    out = []
    for line in open(os.path.join(ROOT, "balance.gd"), encoding="utf-8"):
        m = re.match(r'\s*"(\w+)":(\{.*\}),?\s*$', line)
        if not m: continue
        try: d = json.loads(m.group(2))
        except ValueError: continue
        if d.get("type") != "unit" or d.get("boss_only") or d.get("pay_all") or "members" in d: continue
        if float(d.get("range", 999)) > 118 or "hp" not in d: continue
        out.append(d)
    return out

def power_fit(xs, ys):
    lx, ly = [math.log(x) for x in xs], [math.log(y) for y in ys]
    mx, my = st.mean(lx), st.mean(ly)
    b = sum((x - mx) * (y - my) for x, y in zip(lx, ly)) / sum((x - mx) ** 2 for x in lx)
    return math.exp(my - b * mx), b

cards = pool()
hps = [c["hp"] for c in cards]
FIT = {k: power_fit(hps, [c[k] for c in cards]) for k in ("damage", "interval", "speed")}

def body(hp, form):
    md, mi, ms, _ = FORMS[form]
    d = FIT["damage"][0] * hp ** FIT["damage"][1] * md
    iv = min(max(FIT["interval"][0] * hp ** FIT["interval"][1] * mi, INTERVAL[0]), INTERVAL[1])
    sp = min(max(FIT["speed"][0] * hp ** FIT["speed"][1] * ms, SPEED[0]), SPEED[1])
    return d, iv, sp

def solve(c, g, form):
    lo, hi = 1.0, 1e6
    for _ in range(100):
        m = (lo * hi) ** 0.5
        if V(c, m, *body(m, form)) < K * g: lo = m
        else: hi = m
    return lo

# Form for each amount: shuffled rounds of every form, never the same form twice in a row.
rng = random.Random(SEED)
order, names = [], list(FORMS)
while len(order) < N - 1:
    bag = names[:]
    rng.shuffle(bag)
    if order and bag[0] == order[-1]: bag.append(bag.pop(0))
    order += bag

rows = [(1, 1) + BASE + ("原形",)]
for g in range(2, N + 1):
    form = order[g - 2]
    c = FORMS[form][3](g)
    while c > 1 and solve(c, g, form) < HP_FLOOR: c -= 1     # too little gold to split that far
    while solve(c, g, form) > HP_CAP and c < 5: c += 1         # a brute that would outgrow a giant splits
    hp = solve(c, g, form)
    d, iv, sp = body(hp, form)
    rows.append((g, c, round(hp), round(d), round(iv, 2), round(sp), form))

worst = 0.0
for r in rows:
    v = V(r[1], r[2], r[3], r[4], r[5]); ratio = v / r[0]
    if r[0] > 1: worst = max(worst, abs(ratio / K - 1))
    print("%2d 金 %s %d 隻 生命%5d 傷害%4d 間隔%5.2f 移速%4d  價值 %.2f（%.3f／金）" % (r[0], r[6], r[1], r[2], r[3], r[4], r[5], v, ratio))
print("fit:", {k: "%.2f*hp^%.3f" % v for k, v in FIT.items()}, " worst value error %.2f%%" % (worst * 100))
print("GD:", ",".join('[%d,%d,%.1f,%.1f,%s,%.1f,"%s"]' % (r[0], r[1], r[2], r[3], repr(float(r[4])), r[5], r[6]) for r in rows))
