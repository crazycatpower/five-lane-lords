"""Paired cost sweep: solve each card's fair cost in one batch (使用者 2026-11-25「想一個更高效的方式調整平衡」).

    python tools/balance_sweep.py --cards thorn_mother,dire_hydra --seeds 50 --workers 11 [--apply]

For every target card, each seed builds one match (random lords and decks; the card is forced into one side's
deck, the other side never has it) and plays that very same match once per tested cost (current cost and
+-spread). Because the decks, lords and seed are shared, most of the luck cancels between the costs.
A logistic fit of "the holder wins" against cost gives the cost where the holder wins 50% of the time,
and a bootstrap over seeds gives its 95% interval. --apply writes the rounded fair cost into balance.gd for
cards whose current cost lies outside that interval. Costs are injected at run time (balance.gd
override_costs), so balance.gd can be edited while a sweep runs.
"""
import argparse, json, math, os, random, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import autobalance as AB

ROOT = AB.ROOT
GIANTS = ["thorn_mother", "dire_hydra", "arcane_golem", "eyewing_dragon", "thorn_dragon", "corpse_giant",
          "siege_tower", "crystal_colossus", "flesh_abomination", "bone_dragon"]


def levels_for(cost, spread):
    lv = sorted({max(AB.MIN_COST, min(AB.MAX_COST, int(round(cost * f)))) for f in (1 - spread, 1.0, 1 + spread)})
    while len(lv) < 3 and lv[-1] < AB.MAX_COST:
        lv.append(min(AB.MAX_COST, lv[-1] * 2))
    return lv


def run_worker(job):
    start, count, spec_path, out, hz, cap = job
    cmd = ["godot_console", "--headless", "--path", ROOT, "-s", "tools/random_sim.gd", "--",
           f"--start={start}", f"--count={count}", f"--sweep={spec_path}", f"--out={out}", f"--hz={hz}", f"--cap={cap}"]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", shell=(os.name == "nt"))
    if r.returncode != 0 or "SCRIPT ERROR" in r.stdout + r.stderr:
        raise RuntimeError(f"worker {start} failed:\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
    return out


def logistic_fit(xs, ys, iters=50):
    """MLE of P(win) = 1/(1+exp(-(a+b*x))), x centred; ys may be 0, 0.5 or 1. Returns (a, b, mean_x)."""
    mx = sum(xs) / len(xs)
    a, b = 0.0, 0.0
    for _ in range(iters):
        ga = gb = haa = hab = hbb = 0.0
        for x, y in zip(xs, ys):
            z = x - mx
            p = 1 / (1 + math.exp(-(a + b * z)))
            w = p * (1 - p)
            ga += y - p; gb += (y - p) * z
            haa += w; hab += w * z; hbb += w * z * z
        det = haa * hbb - hab * hab + 1e-9
        da = (hbb * ga - hab * gb) / det
        db = (haa * gb - hab * ga) / det
        a += da; b += db
        if abs(da) + abs(db) < 1e-7: break
    return a, b, mx


def fair_cost(rows):
    xs = [r[0] for r in rows]; ys = [r[1] for r in rows]
    if len(set(xs)) < 2: return None
    a, b, mx = logistic_fit(xs, ys)
    if b >= -1e-4: return None  # costlier should mean weaker; a flat or rising fit gives no answer
    return mx - a / b


def analyse(results, targets, boot=400, rng_seed=1):
    by_card = {}
    for r in results:
        sw = r["sweep"]
        y = 0.5 if r["winner"] < 0 else (1.0 if r["winner"] == sw["side"] else 0.0)
        by_card.setdefault(sw["card"], {}).setdefault(r["seed"], []).append((sw["cost"], y))
    rnd = random.Random(rng_seed)
    out = {}
    for card, seeds in by_card.items():
        rows = [row for s in seeds.values() for row in s]
        per_level = {}
        for c, y in rows:
            w, n = per_level.get(c, (0.0, 0)); per_level[c] = (w + y, n + 1)
        est = fair_cost(rows)
        keys = list(seeds)
        boots = []
        for _ in range(boot):
            sample = [row for k in (rnd.choice(keys) for _ in keys) for row in seeds[k]]
            v = fair_cost(sample)
            if v is not None: boots.append(v)
        boots.sort()
        ci = (boots[int(len(boots) * 0.025)], boots[int(len(boots) * 0.975) - 1]) if len(boots) >= 50 else None
        out[card] = {"seeds": len(keys), "levels": {c: (w / n, n) for c, (w, n) in sorted(per_level.items())},
                     "fair": est, "ci": ci, "boot_ok": len(boots)}
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cards", default=",".join(GIANTS))
    p.add_argument("--seeds", type=int, default=50, help="matches-sets per card (each plays every tested cost)")
    p.add_argument("--spread", type=float, default=0.25, help="tested costs = current x (1-spread, 1, 1+spread)")
    p.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    p.add_argument("--hz", type=float, default=30.0)
    p.add_argument("--cap", type=float, default=900.0)
    p.add_argument("--seed-base", type=int, default=50000)
    p.add_argument("--out-dir", default=os.path.join(ROOT, "tools", "autobalance_runs", "sweep"))
    p.add_argument("--report", default="")
    p.add_argument("--apply", action="store_true", help="write fair costs for cards whose current cost is outside the 95%% interval")
    args = p.parse_args()

    cards = AB.read_cards()
    names = [c.strip() for c in args.cards.split(",") if c.strip()]
    for n in names:
        if n not in cards: sys.exit(f"unknown or summon-only card: {n}")
    targets = {n: levels_for(cards[n][1], args.spread) for n in names}
    os.makedirs(args.out_dir, exist_ok=True)
    spec_path = os.path.join(args.out_dir, "spec.json")
    json.dump({"targets": targets}, open(spec_path, "w", encoding="utf-8"))

    total_seeds = args.seeds * len(names)
    base = args.seed_base - args.seed_base % len(names)  # seed % n picks the card, so every card gets args.seeds
    per = math.ceil(total_seeds / args.workers)
    jobs = []
    for w in range(args.workers):
        start = base + w * per
        count = min(per, base + total_seeds - start)
        if count > 0: jobs.append((start, count, spec_path, os.path.join(args.out_dir, f"w{w}.jsonl"), args.hz, args.cap))
    matches = sum(len(v) for v in targets.values()) * args.seeds
    print(f"sweep {len(names)} cards x {args.seeds} seeds -> {matches} matches on {len(jobs)} workers", flush=True)
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=len(jobs)) as ex:
        files = list(ex.map(run_worker, jobs))
    results = [json.loads(l) for f in files for l in open(f, encoding="utf-8") if l.strip()]
    print(f"{len(results)} matches in {time.time() - t0:.0f}s", flush=True)

    res = analyse(results, targets)
    lines = ["| 卡牌 | 現費 | 各費用勝率 | 50% 費用 | 95% 區間 | 建議 |", "|---|---|---|---|---|---|"]
    changes = {}
    for n in names:
        r = res.get(n)
        cur = cards[n][1]
        if not r:
            lines.append(f"| {cards[n][0]} | {cur} | 無資料 | | | |"); continue
        lv = "　".join(f"{c}費 {w*100:.0f}%" for c, (w, k) in r["levels"].items())
        if r["fair"] is None:
            avg = sum(w for w, _ in r["levels"].values()) / len(r["levels"])
            verdict = "看不出差異（樣本不足）" if abs(avg - 0.5) < 0.05 else ("超出測試範圍，偏強" if avg > 0.5 else "超出測試範圍，偏弱")
            lines.append(f"| {cards[n][0]} | {cur} | {lv} | — | — | {verdict} |"); continue
        fair = max(AB.MIN_COST, min(AB.MAX_COST, r["fair"]))
        ci = r["ci"]
        ci_txt = f"{ci[0]:.1f}～{ci[1]:.1f}" if ci else "—"
        outside = ci is not None and not (ci[0] <= cur <= ci[1])
        suggestion = int(round(fair))
        verdict = f"→ {suggestion}" if outside and suggestion != cur else "維持"
        if outside and suggestion != cur: changes[n] = suggestion
        lines.append(f"| {cards[n][0]} | {cur} | {lv} | {fair:.1f} | {ci_txt} | {verdict} |")
    report = "\n".join(lines)
    print(report)
    if args.report: open(args.report, "w", encoding="utf-8").write(report + "\n")
    if args.apply and changes:
        AB.write_costs(changes)
        print("applied:", changes)


if __name__ == "__main__":
    main()
