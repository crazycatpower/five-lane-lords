"""Automatic balance loop: random-deck AI matches, then nudge card costs toward 50% win rate.

    python tools/autobalance.py --total 10000 --rounds 5 --workers 11

Each round plays total/rounds matches (random 8-card decks, random lords; tools/random_sim.gd)
in parallel Godot processes, measures every card's win rate, and edits the "cost" of cards that
win too often (+) or too rarely (-) in balance.gd. Only costs change: stats stay on the S-E tiers.
Lord win rates are reported but not changed (lord stats are tier-locked; the producer decides).

A card's win rate only counts matches where exactly one side holds it, so mirrors don't dilute it.
Draws (time cap) count as half a win. Raw results go to tools/autobalance_runs/ (not committed);
the summary is written to tools/autobalance_runs/report.md (not committed).
"""
import argparse, hashlib, json, math, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BALANCE = os.path.join(ROOT, "balance.gd")
RUNS = os.path.join(ROOT, "tools", "autobalance_runs")
REPORT = os.path.join(ROOT, "tools", "autobalance_runs", "report.md") # tool output, not committed
MIN_COST, MAX_COST = 1, 50  # = balance.gd MAX_CARD_COST (使用者 2026-11-24)


def round_half_up(val):
    return int(math.floor(val + 0.5))


def read_cards():
    """{kind: (name, cost)} for every card line in balance.gd (lines that carry a "type")."""
    cards = {}
    for line in open(BALANCE, encoding="utf-8"):
        if '"summon_only":true' in line:
            continue
        m = re.match(r'\t"(\w+)":\{"name":"([^"]+)".*?"type":"\w+".*?"cost":(\d+)', line)
        if m: cards[m.group(1)] = (m.group(2), int(m.group(3)))
    return cards


def read_card_dicts():
    """Parse every card dictionary literal line in balance.gd into a Python dict."""
    out = {}
    for line in open(BALANCE, encoding="utf-8"):
        m = re.match(r'\t"(\w+)":(\{"name":.*\}),?\s*$', line)
        if not m:
            continue
        kind, body = m.group(1), m.group(2).rstrip(",")
        try:
            d = json.loads(body)
            if "type" in d:
                out[kind] = d
        except Exception:
            pass
    return out


ROLE_ANCHORS = {
    "frontline": {"manor_retainer": 5, "shieldguard": 6, "knight": 21},
    "ranged": {"axe_thrower": 7, "hunter": 9, "arcane_archer": 9},
    "swarm_raid": {"bandit": 3, "raven": 7, "ox": 8, "militia": 11, "ram": 15},
    "support_unit": {"drummer": 4, "healer": 5, "necromancer": 18},
    "defense_building": {"barricade": 1, "scarecrow": 2, "blast_trap": 6, "mimic_egg": 7, "arcane_tower": 11, "tower": 23},
    "economy": {"sacrifice": 1, "grave_exchange": 3, "mule_cart": 6, "harvest": 8, "farmer": 12, "mill": 29},
    "spell": {"time_field": 2, "dread_howl": 2, "arcane_shield": 4, "plague": 6, "rain": 8, "chain_lightning": 11, "fire": 20},
}

ROLE_LABELS = {
    "frontline": "前排／近戰決鬥科",
    "ranged": "遠射／後排火力科",
    "swarm_raid": "人海／突襲／攻城科",
    "support_unit": "支援／治療／召喚部隊科",
    "defense_building": "防禦／陷阱／支援建築科",
    "economy": "經濟／資源科",
    "spell": "法術科（清場／控場／增益）",
}

ROLE_EXAMINER_DESC = {
    "frontline": "民兵隊（人海圍毆）、盾衛＋投斧手（重甲破甲集火）、騎士（重裝硬碰硬）、獵戶（頂箭推進）",
    "ranged": "騎士（重裝靶標）、民兵隊（人海衝陣）、鉤鼻飛魔（防空考驗）、盾衛＋獵戶（坦射對射），我方配置盾衛前排掩護",
    "swarm_raid": "投斧手＋雙農田（抗單點重砲與拆田）、獵戶＋雙農田（切後排與偷襲）、箭樓（攻城破防）、莊園扈從（巡邏攔截）",
    "support_unit": "莊園扈從（持久消耗）、民兵隊（群體衝擊）、投斧手（高傷壓制），量測對我方受損前排的淨續航／加速／招魂增益",
    "defense_building": "民兵隊＋扈從（步兵攻城波）、耕牛＋扈從（衝鋒破陣波）、騎士＋扈從（重裝推進波）、烏鴉群＋扈從（空地偷襲波）",
    "economy": "鬍子魔（偷金騷擾）、強盜（潛行突襲），量測 24 秒內淨產金量、回本效率與抗騷擾能力",
    "spell": "民兵隊（步兵密集陣）、獵戶＋民兵（前後排混合陣）、盾衛（護甲陣）、騎士＋民兵（重裝混編陣），於交鋒瞬間精準施放",
}

EXAMINER_COSTS = {k: v for grp in ROLE_ANCHORS.values() for k, v in grp.items()}


def compute_theory_cost(kind, d, all_cards):
    """LOOCV-calibrated analytical power-budget cost across units, buildings, and spells."""
    if kind in EXAMINER_COSTS:
        return float(EXAMINER_COSTS[kind])
    ctype = d.get("type", "unit")

    if ctype == "unit":
        if "members" in d:
            sub_val = 0.0
            for grp in d["members"]:
                mk, mc = grp[0], int(grp[1])
                md = all_cards.get(mk, {})
                single_c = compute_theory_cost(mk, md, all_cards) / max(1, int(md.get("count", 1)))
                sub_val += single_c * mc
            return max(1.0, min(30.0, sub_val))

        count = float(d.get("count", 1)) * (3.0 if d.get("spread", False) else 1.0)
        hp = float(d.get("hp", 130.0))
        if "armor" in d:
            hp *= 1.0 + float(d["armor"]) / 38.0
        if "spell_resist" in d:
            hp *= 1.0 + (1.0 - float(d["spell_resist"])) * 0.25
        if d.get("last_stand", False):
            hp *= 1.15
        if "regen_amount" in d:
            hp += float(d["regen_amount"]) / max(1.0, float(d.get("period", 2.4))) * 8.0
        if "lifesteal" in d:
            hp *= 1.0 + float(d["lifesteal"]) * 0.5

        dmg = float(d.get("area_damage", d.get("damage", 26.0))) * float(d.get("strikes", 1))
        if "damage_roll" in d:
            dmg *= 1.35
        if d.get("burst_count", 0) > 1:
            dmg *= float(d["burst_count"])
        if "devour_heal" in d and "max_damage_tier" in d:
            hp += float(d["devour_heal"]) * 4.0
            dmg = max(dmg, 120.0)
        interval = max(0.18, float(d.get("interval", 1.1)))
        dps = dmg / interval
        if "area_damage" in d:
            dps *= 1.35 + float(d.get("radius", 52.0)) / 110.0
        elif d.get("splash", "") == "column":
            dps *= 1.8 if d.get("three_lane_target", False) else 1.6
        if d.get("pierce", False):
            dps *= 1.55
        if "dot_damage" in d:
            dps += float(d["dot_damage"]) * float(d.get("dot_ticks", 2)) / max(1.0, interval) * 0.85
        if d.get("suicide_blast", False):
            dps = float(d.get("area_damage", 230.0)) / 3.0

        rng = float(d.get("range", 47.0)) * (float(d.get("pierce_range_multiplier", 1.0)) if d.get("pierce", False) else 1.0)
        rng_f = 1.0 + max(0.0, rng - 47.0) / 260.0
        fly_f = 1.15 if d.get("flying", False) else 1.0
        pat_f = 0.65 if d.get("patrol", False) else 1.0
        P = ((count ** 0.90) * (hp ** 0.45) * (dps ** 0.35) * rng_f * fly_f * pat_f) ** 0.90

        ctrl = sum(float(d[k]) for k in ("stun_on_hit", "root_on_hit", "net_slow", "roar_fear", "charge_stun") if k in d)
        if d.get("stealth", False):
            ctrl += 0.5
        if d.get("phase", False) or "blink_step" in d:
            ctrl += 0.8
        heal_ps = 0.0
        if kind == "healer":
            heal_ps = 50.0 / 2.4
        elif d.get("support") == "heal":
            heal_ps = float(d.get("support_amount", 26.0)) / max(1.0, float(d.get("period", 2.4)))
        elif d.get("support") == "shield":
            heal_ps = float(d.get("support_amount", 50.0)) / max(1.0, float(d.get("period", 3.0)))
        elif "repair_amount" in d:
            heal_ps = float(d["repair_amount"]) / max(1.0, float(d.get("repair_interval", 2.0))) * 0.6

        summon_ps = 0.0
        if "summon_interval" in d:
            summon_ps = float(d.get("summon_per_lane", 1)) / float(d["summon_interval"])
        elif "on_death_spawn" in d:
            summon_ps = float(d["on_death_spawn"][1]) / 20.0
        elif "ally_death_spawn" in d:
            per = float(d.get("stitch_period", 0.0))
            scnt = float(d.get("stitch_count", 1))
            summon_ps = (scnt / per if per > 0 else 0.0) + (0.14 if d.get("stitch_any_team", False) else 0.08)

        on_hit = float(d.get("thorns", 0.0)) * 0.06 + float(d.get("reflect_damage", 0.0)) * 0.04 + float(d.get("explosion_damage", 0.0)) * 0.025
        if "charge_damage" in d or kind == "ox":
            on_hit += float(d.get("charge_damage", 180.0)) * count * 0.02

        if kind == "farmer":
            return 8.0
        if d.get("shuttle", False):
            return 10.0
        val = 0.1747 * P + 0.42 * ctrl + 0.13 * heal_ps + 20.41 * summon_ps + 1.15 * on_hit - 2.55
        return max(1.0, min(30.0, val))

    elif ctype == "building":
        hp = float(d.get("hp", 350.0))
        dmg = float(d.get("area_damage", d.get("damage", 0.0)))
        iv = float(d.get("interval", 1.0)) or 1.0
        dps = dmg / iv if dmg > 0 else 0.0
        rng = float(d.get("range", 0.0))
        aoe_b = 1.4 if "area_damage" in d else 1.0
        combat = dps * (1.0 + rng / 350.0) * aoe_b * (1.2 if d.get("ignore_armor", False) else 1.0)
        sp = 0.0
        if "spawn_kind" in d and d["spawn_kind"] in all_cards:
            sk = d["spawn_kind"]
            rate = (60.0 / max(1.0, float(d.get("period", 20.0)))) * float(d.get("spawn_count", 1)) / max(1.0, float(all_cards[sk].get("count", 1)))
            sp = rate * (float(all_cards[sk]["cost"]) ** 0.7)
        elif "spawn_count" in d and "period" in d:
            sp = (60.0 / float(d["period"])) * float(d["spawn_count"]) / 6.0 * (9.0 ** 0.7)
        econ = 0.0
        if kind == "granary":
            econ = 7.5
        elif "income" in d:
            econ = float(d["income"]) / max(1.0, float(d.get("period", 20.0))) * 20.0
        elif "tithe_gold" in d:
            econ = float(d["tithe_gold"]) * (0.9 if d.get("tithe_buff_sec", 0.0) > 0 else 0.4)
        elif "death_income" in d:
            econ = float(d["death_income"]) * 1.0
        if kind in ["barricade", "scarecrow", "watchtower"]:
            return float(d.get("cost", 3))
        if kind == "mill":
            return 20.0
        val = 1.33 * (hp / 1000.0) + 0.84 * (combat / 10.0) + 0.60 * sp + 1.01 * econ + 3.30
        if "support" in d or "crit_mult" in d or "pushback" in d or "thorns" in d:
            val += 2.2
        return max(1.0, min(30.0, val))

    else:  # spell
        dmg = float(d.get("area_damage", d.get("damage", d.get("enemy_damage", 0.0))))
        bdmg = float(d.get("building_damage", 0.0))
        tick = float(d.get("tick_damage", 0.0))
        dur = float(d.get("duration", 0.0))
        ti = float(d.get("tick_interval", 1.0)) or 1.0
        dot = tick * (dur / ti) if tick and dur else 0.0
        bolt = float(d.get("bolt_damage", 0.0))
        hops = float(d.get("hops", 1.0))
        rad = float(d.get("radius", 100.0)) or 100.0
        area_m = (rad / 100.0) ** 0.35
        dmg_eq = (dmg * (1.0 + max(0.0, dmg - 140.0) / 450.0) + bdmg * 0.28 + dot * 0.72 + bolt * (1.0 + 0.35 * (hops - 1)) * 0.42) * area_m / 100.0
        tac = 0.0
        if kind in ("levy", "harvest", "mana_spring"):
            tac = 1.6
        elif "spawn_on_kill" in d or "summon_count" in d or "skeletons" in d or "execute_hp" in d:
            tac = 1.1
        elif "shield" in d or "root" in d or "stun_on_hit" in d or "rally_haste_sec" in d or "heal_fraction" in d or "drain_gold_max" in d or "upgrade_hp" in d:
            tac = 0.75
        elif dur > 0 and tick == 0:
            tac = 0.25
        val = 1.81 * dmg_eq + 3.10 * tac + 1.87
        return max(1.0, min(30.0, val))


def run_gauntlet_worker(args):
    worker_id, card_list, out_path = args
    cmd = [
        "godot_console", "--headless", "--path", ROOT, "-s", "tools/random_sim.gd", "--",
        "--gauntlet", f"--cards={','.join(card_list)}", f"--out={out_path}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", shell=(os.name == "nt"))
    if result.returncode != 0 or "SCRIPT ERROR" in result.stdout + result.stderr:
        raise RuntimeError(f"gauntlet worker {worker_id} failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return out_path


def run_examiner_gauntlet(workers, dry_run=False, report_path=REPORT):
    t0 = time.time()
    os.makedirs(RUNS, exist_ok=True)
    all_cards = read_card_dicts()
    cards = read_cards()
    target_kinds = [k for k in cards if k not in ["farm", "grave", "glutton_nest", "crystal"]]
    per = math.ceil(len(target_kinds) / workers)
    jobs = []
    for w in range(workers):
        chunk = target_kinds[w * per:(w + 1) * per]
        if not chunk:
            break
        jobs.append((w, chunk, os.path.join(RUNS, f"gauntlet_w{w}.jsonl")))
    with ThreadPoolExecutor(len(jobs)) as pool:
        files = list(pool.map(run_gauntlet_worker, jobs))
    rows = {}
    for path in files:
        for line in open(path, encoding="utf-8"):
            if line.strip():
                r = json.loads(line)
                rows[r["kind"]] = r

    # Calibrate linear regression per Role Track anchored on that role's Benchmark Examiner cards
    role_models = {}
    for role, anchors in ROLE_ANCHORS.items():
        akeys = [k for k in anchors if k in rows]
        if len(akeys) >= 2:
            mx = sum(rows[k]["examiner_avg"] for k in akeys) / len(akeys)
            my = sum(anchors[k] for k in akeys) / len(akeys)
            num = sum((rows[k]["examiner_avg"] - mx) * (anchors[k] - my) for k in akeys)
            den = sum((rows[k]["examiner_avg"] - mx) ** 2 for k in akeys)
            slope = max(0.004, min(0.028, num / den if den > 1e-6 else 0.012))
            intercept = my - slope * mx
        else:
            mx, my, slope, intercept = 400.0, 8.0, 0.012, 3.2
        role_models[role] = (mx, my, slope, intercept)

    changes = {}
    summary_rows = []
    for k in target_kinds:
        if k not in rows:
            continue
        r = rows[k]
        role = r["role_track"]
        mx, my, slope, intercept = role_models[role]
        old_cost = cards[k][1]
        d = all_cards.get(k, {})
        theory_c = compute_theory_cost(k, d, all_cards)
        gauntlet_c = max(1.0, min(float(MAX_COST), intercept + slope * r["examiner_avg"]))
        # Role-normalized 0-100 score where 60 = role anchor average
        gauntlet_score_100 = max(12.0, min(99.0, 60.0 + (r["examiner_avg"] - mx) * 0.045))
        if k in EXAMINER_COSTS:
            new_cost = EXAMINER_COSTS[k]
        else:
            blended = 0.45 * gauntlet_c + 0.55 * theory_c
            new_cost = max(MIN_COST, min(MAX_COST, round_half_up(blended)))
            if new_cost != old_cost:
                changes[k] = new_cost
        ex_detail = " / ".join(f"{cards.get(ek, (ek, 0))[0]}:{ev:.0f}" for ek, ev in r["examiner_scores"].items())
        summary_rows.append((k, cards[k][0], r["faction"], role, old_cost, new_cost, gauntlet_score_100, r["examiner_avg"], theory_c, gauntlet_c, ex_detail))

    if changes and not dry_run:
        write_costs(changes)

    elapsed = time.time() - t0
    lines = [
        "# 七大職責分科考官闖關評分與自動費用平衡報告\n\n",
        f"- 執行時間：{time.strftime('%Y-%m-%d %H:%M:%S')}（耗時 `{elapsed:.1f}` 秒，並行 Worker：{len(jobs)}）\n\n",
        "## 一、七大職責考科與基準錨定考官\n\n",
        "| 職責考科 | 專屬考場與考官配置 | 基準錨定卡牌（鎖定標準費） |\n",
        "|---|---|---|\n",
    ]
    for role, label in ROLE_LABELS.items():
        anchor_str = "、".join(f"{cards[ak][0]}（{ac}費）" for ak, ac in ROLE_ANCHORS[role].items() if ak in cards)
        lines.append(f"| **{label}** | {ROLE_EXAMINER_DESC[role]} | {anchor_str} |\n")

    lines.append(f"\n## 二、費用調整總覽（共調整 {len(changes)} 張卡牌）\n\n")
    if changes:
        lines.append("| 卡牌 | 陣營 | 職責考科 | 分科闖關分 | 考官實戰均值 | 理論預算費 | 考官對標費 | 費用調整 |\n")
        lines.append("|---|---|---|---:|---:|---:|---:|---|\n")
        for k, name, fac, role, old_c, new_c, gs, s1, tc, gc, _ in sorted(summary_rows, key=lambda x: (x[3], -abs(x[5] - x[4]))):
            if old_c == new_c:
                continue
            arrow = "↑" if new_c > old_c else "↓"
            lines.append(f"| {name} | {fac} | {ROLE_LABELS[role]} | {gs:.1f} | {s1:.0f} | {tc:.1f} | {gc:.1f} | **{old_c} → {new_c}** ({arrow}{abs(new_c - old_c)}) |\n")
    else:
        lines.append("所有卡牌費用均已收斂於合理區間。\n")

    lines.append("\n## 三、各職責分科全卡池闖關評分明細\n")
    for role, label in ROLE_LABELS.items():
        lines.append(f"\n### {label}\n\n")
        lines.append("| 卡牌 | 陣營 | 原費 | 新費 | 分科評分 | 考官淨戰果 | 理論費 | 對標費 | 各考官單項明細 | 狀態 |\n")
        lines.append("|---|---|---:|---:|---:|---:|---:|---:|---|---|\n")
        role_items = [row for row in summary_rows if row[3] == role]
        for k, name, fac, _, old_c, new_c, gs, s1, tc, gc, ex_det in sorted(role_items, key=lambda x: -x[6]):
            status = "基準錨點" if k in EXAMINER_COSTS else (f"**{old_c}→{new_c}**" if old_c != new_c else "維持")
            lines.append(f"| {name} | {fac} | {old_c} | {new_c} | {gs:.1f} | {s1:.0f} | {tc:.1f} | {gc:.1f} | {ex_det} | {status} |\n")

    open(report_path, "w", encoding="utf-8").write("".join(lines))
    print("".join(lines[:45]), flush=True)
    print(f"Role-Specific Gauntlet finished in {elapsed:.1f}s; {len(changes)} card costs adjusted. Report: {report_path}")
    return 0


def write_costs(new_costs):
    text = open(BALANCE, encoding="utf-8").read()
    for kind, cost in new_costs.items():
        pattern = r'(\t"%s":\{"name":"[^"]+".*?"type":"\w+".*?"cost":)\d+' % kind
        text, n = re.subn(pattern, lambda m: m.group(1) + str(cost), text, count=1)
        assert n == 1, kind
    open(BALANCE, "w", encoding="utf-8", newline="").write(text)


def run_worker(args):
    start, count, out, cap, must_have, must_have_cards, hz = args
    cmd = ["godot_console", "--headless", "--path", ROOT, "-s", "tools/random_sim.gd", "--",
           f"--start={start}", f"--count={count}", f"--out={out}", f"--cap={cap}", f"--hz={hz}"]
    if must_have: cmd.append(f"--must-have-lords={must_have}")
    if must_have_cards: cmd.append(f"--must-have-cards={must_have_cards}")
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", shell=(os.name == "nt"))
    if result.returncode != 0 or "SCRIPT ERROR" in result.stdout + result.stderr:
        raise RuntimeError(f"worker {start} failed:\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")
    return out


def play_round(index, matches, workers, cap, seed_base, must_have="", must_have_cards="", hz=60.0):
    os.makedirs(RUNS, exist_ok=True)
    per = math.ceil(matches / workers)
    jobs = []
    for w in range(workers):
        count = min(per, matches - w * per)
        if count <= 0: break
        jobs.append((seed_base + w * per, count, os.path.join(RUNS, f"round{index}_w{w}.jsonl"), cap, must_have, must_have_cards, hz))
    with ThreadPoolExecutor(len(jobs)) as pool:
        files = list(pool.map(run_worker, jobs))
    results = []
    for path in files:
        for line in open(path, encoding="utf-8"):
            if line.strip(): results.append(json.loads(line))
    return results


def card_details(results, cards):
    totals = {k: dict(samples=0, plays=0, first=[], damage=0.0, spent=0.0,
                      damage_available=True) for k in cards}
    for result in results:
        for side in result.get("card_stats", []):
            for kind, value in side.items():
                if kind not in totals:
                    continue
                row = totals[kind]
                row["samples"] += 1
                row["plays"] += value["plays"]
                if value["first_play"] is not None:
                    row["first"].append(value["first_play"])
                if value["damage"] is None:
                    row["damage_available"] = False
                else:
                    row["damage"] += value["damage"]
                row["spent"] += value["spent"]
    return {kind: {
        "samples": v["samples"],
        "plays_per_match": v["plays"] / v["samples"] if v["samples"] else None,
        "first_play": sum(v["first"]) / len(v["first"]) if v["first"] else None,
        "damage_per_gold": v["damage"] / v["spent"] if v["damage_available"] and v["spent"] else None,
    } for kind, v in totals.items()}


HOME_CARDS = {"farm", "grave", "glutton_nest", "crystal"}


def analyse(results, cards):
    stat = {k: [0.0, 0] for k in cards if k not in HOME_CARDS}  # home cards not in deck pool
    lords = {}
    factions = {}
    red = [0, 0]
    draws = 0
    lengths = []
    for r in results:
        w = r["winner"]
        if w < 0: draws += 1
        else:
            red[0] += w == 0
            red[1] += 1
            lengths.append(r["t"])
        score = [0.5, 0.5] if w < 0 else [1.0 if w == 0 else 0.0, 1.0 if w == 1 else 0.0]
        a, b = set(r["decks"][0]), set(r["decks"][1])
        for side, own, other in ((0, a, b), (1, b, a)):
            for kind in own - other:
                stat[kind][0] += score[side]
                stat[kind][1] += 1
        fa, fb = r.get("factions", ["unknown", "unknown"])
        if fa != fb:
            for side, faction in enumerate((fa, fb)):
                entry = factions.setdefault(faction, [0.0, 0])
                entry[0] += score[side]
                entry[1] += 1
        la, lb = r["lords"]
        if la != lb:
            for side, lord in ((0, la), (1, lb)):
                s = lords.setdefault(lord, [0.0, 0])
                s[0] += score[side]
                s[1] += 1
    lengths.sort()
    breaches = sorted(r["breach"] for r in results if r.get("breach", -1) >= 0)
    lost = [n for r in results for n in r.get("farms_lost_early", [])]
    skills = [n for r in results for n in r.get("skills", [])]
    return {
        "breach": breaches[len(breaches) // 2] if breaches else -1,
        "farms_lost": sum(lost) / len(lost) if lost else 0,
        "skills": sum(skills) / len(skills) if skills else 0,
        "cards": {k: (v[0] / v[1] if v[1] else 0.5, v[1]) for k, v in stat.items()},
        "lords": {k: (v[0] / v[1] if v[1] else 0.5, v[1]) for k, v in lords.items()},
        "factions": {k: (v[0] / v[1], v[1]) for k, v in factions.items()},
        "red_rate": red[0] / red[1] if red[1] else 0.5,
        "draws": draws,
        "median": lengths[len(lengths) // 2] if lengths else 0,
        "matches": len(results),
        "card_details": card_details(results, cards),
    }


def adjust(analysis, cards, threshold, step, min_games=25, shrinkage=0.0, max_delta=0):
    """Cost change per card: proportional to how far from 50% it is, at least 1, at most 25% of cost (or max_delta)."""
    changes = {}
    for kind, (rate, games) in analysis["cards"].items():
        if games < min_games: continue
        raw_gap = rate - 0.5
        gap = raw_gap * (games / (games + shrinkage)) if shrinkage > 0.0 else raw_gap
        if abs(gap) < threshold: continue
        cost = cards[kind][1]
        delta = max(1, round(abs(gap) * cost * step))
        cap_delta = max(1, round(cost * 0.25))
        if max_delta > 0:
            cap_delta = min(cap_delta, max_delta)
        delta = min(delta, cap_delta)
        new = max(MIN_COST, min(MAX_COST, cost + (delta if gap > 0 else -delta)))
        if new != cost: changes[kind] = new
    return changes


def table(analysis, cards, changes, float_costs=None):
    if float_costs is not None:
        rows = ["| 卡牌 | 整數費用 | 浮點累積 | 勝率 | 場次 | 平均出牌次數 | 每金幣傷害 | 平均第一次出牌時間 | 調整 |",
                "|---|---|---|---|---|---|---|---|---|"]
        for kind, (rate, games) in sorted(analysis["cards"].items(), key=lambda kv: -kv[1][0]):
            fc = float_costs.get(kind, float(cards[kind][1]))
            change = f"{cards[kind][1]} → {changes[kind]}" if kind in changes else ""
            detail = analysis.get("card_details", {}).get(kind, {})
            def metric(key, suffix=""):
                value = detail.get(key)
                return "—" if value is None else f"{value:.2f}{suffix}"
            rows.append(f"| {cards[kind][0]} | {cards[kind][1]} | {fc:.2f} | {rate:.1%} | {games} | "
                        f"{metric('plays_per_match')} | {metric('damage_per_gold')} | "
                        f"{metric('first_play', ' 秒')} | {change} |")
    else:
        rows = ["| 卡牌 | 費用 | 勝率 | 場次 | 平均出牌次數 | 每金幣傷害 | 平均第一次出牌時間 | 調整 |",
                "|---|---|---|---|---|---|---|---|"]
        for kind, (rate, games) in sorted(analysis["cards"].items(), key=lambda kv: -kv[1][0]):
            change = f"{cards[kind][1]} → {changes[kind]}" if kind in changes else ""
            detail = analysis.get("card_details", {}).get(kind, {})
            def metric(key, suffix=""):
                value = detail.get(key)
                return "—" if value is None else f"{value:.2f}{suffix}"
            rows.append(f"| {cards[kind][0]} | {cards[kind][1]} | {rate:.1%} | {games} | "
                        f"{metric('plays_per_match')} | {metric('damage_per_gold')} | "
                        f"{metric('first_play', ' 秒')} | {change} |")
    lords = ", ".join(f"{k} {v[0]:.1%}（{v[1]}）" for k, v in sorted(analysis["lords"].items(), key=lambda kv: -kv[1][0]))
    head = (f"{analysis['matches']} 場；平手 {analysis['draws']}；決勝局中位數 {analysis['median']:.0f} 秒；"
            f"紅方勝率 {analysis['red_rate']:.1%}\n\n"
            f"前 3 分鐘每方平均被拆農田 {analysis['farms_lost']:.2f} 塊；第一次破門中位數 {analysis['breach']:.0f} 秒；每方平均發動領主技能 {analysis['skills']:.2f} 次\n\n領主勝率（雙方領主不同時）：{lords}\n")
    head += "\n陣營勝率（只計跨陣營）：" + ", ".join(f"{k} {rate:.1%}（{n}）" for k, (rate, n) in analysis.get("factions", {}).items()) + "\n"
    notes = ("\n\n統計口徑：出牌次數以持有該牌的每方每場計算（含鏡像對局）；首次出牌時間只平均實際出過牌的樣本。"
             "每金幣傷害＝同兵種傷害總和／實際花費總和，包含部隊、建築、城門傷害。"
             "現有傷害桶按兵種歸類，可能包含軍團成員及領主召喚兵；不能當成單一卡牌的精確投資報酬。"
             "軍團牌無法還原來源傷害，顯示 —；未出牌或舊資料缺少欄位也顯示 —，不是 0。"
             "此欄不可單獨用來調整軍團或召喚相關牌的平衡。\n")
    return head + "\n" + "\n".join(rows) + notes


def main():
    global REPORT, RUNS
    p = argparse.ArgumentParser()
    p.add_argument("--seed-base", type=int, default=1)
    p.add_argument("--total", type=int, default=10000)
    p.add_argument("--rounds", type=int, default=5)
    p.add_argument("--per-round", type=int, default=0, help="matches per round (overrides total // rounds when > 0)")
    p.add_argument("--hours", type=float, default=0.0, help="run continuously for up to this many hours (overrides --rounds when > 0)")
    p.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    p.add_argument("--cap", type=float, default=900)
    p.add_argument("--threshold", type=float, default=0.03, help="ignore cards within this of 50%%")
    p.add_argument("--step", type=float, default=1.0, help="cost change = gap x cost x step (damped later)")
    p.add_argument("--max-delta", type=int, default=0, help="cap single-round cost change per card (0 = 25%% of cost)")
    p.add_argument("--ema-decay", type=float, default=0.0, help="carry decayed (wins, games) across rounds for unchanged cards")
    p.add_argument("--per-match-delta", type=float, default=0.0, help="accumulate +- delta fee per match (round half-up)")
    p.add_argument("--dry-run", action="store_true", help="measure only, never edit balance.gd")
    p.add_argument("--adjust-last", action="store_true", help="the last round adjusts too (default: it only measures)")
    p.add_argument("--report", default=REPORT)
    p.add_argument("--runs-dir", default=RUNS)
    p.add_argument("--only-cards", default="", help="comma-separated cards allowed to change cost")
    p.add_argument("--exclude-cards", default="", help="comma-separated cards locked from cost changes")
    p.add_argument("--must-have-lords", default="", help="comma-separated lord names where at least one side must be from this pool")
    p.add_argument("--must-have-cards", default="", help="comma-separated card names that must be drafted in each match")
    p.add_argument("--min-games", type=int, default=25, help="minimum non-mirror matches for a card to be adjusted")
    p.add_argument("--shrinkage", type=float, default=0.0, help="empirical Bayes shrinkage pseudo-count toward 50%% win rate")
    p.add_argument("--hz", type=float, default=60.0, help="simulation step rate in Hz (e.g. 30 for ~2x faster batch runs)")
    p.add_argument("--gauntlet", action="store_true", help="run fast Benchmark Examiner Gauntlet scoring and cost calibration")
    args = p.parse_args()
    REPORT, RUNS = os.path.abspath(args.report), os.path.abspath(args.runs_dir)
    if args.gauntlet:
        return run_examiner_gauntlet(args.workers, args.dry_run, REPORT)
    allowed = set(c.strip() for c in args.only_cards.split(",") if c.strip()) if args.only_cards else None
    excluded = set(c.strip() for c in args.exclude_cards.split(",") if c.strip())

    per_round = args.per_round if args.per_round > 0 else max(1, args.total // max(1, args.rounds))
    deadline = (time.time() + args.hours * 3600.0) if args.hours > 0 else None
    start_costs = {k: v[1] for k, v in read_cards().items()}
    float_costs = {k: float(v) for k, v in start_costs.items()} if args.per_match_delta > 0 else None
    ema_stats = {}  # kind -> [weighted_wins, weighted_games]
    must_notes = []
    if args.must_have_lords: must_notes.append(f"領主：{args.must_have_lords}")
    if args.must_have_cards: must_notes.append(f"卡牌：{args.must_have_cards}")
    rule_note = f"每場過後立刻 +- {args.per_match_delta} 費（持續累積，四捨五入）" if args.per_match_delta > 0 else "每輪後依卡牌勝率調整費用（只改費用，數值檔次不動）"
    must_note = f"（每局必含{'，'.join(must_notes)}）" if must_notes else ""
    duration_note = f"限時 {args.hours:g} 小時、每輪 {per_round} 場" if args.hours > 0 else f"共 {per_round * args.rounds} 場、分 {args.rounds} 輪，每輪 {per_round} 場"
    log = [f"# 自動平衡報告\n\n{time.strftime('%Y-%m-%d %H:%M')}：{duration_note}隨機牌組＋隨機領主的 AI 對戰{must_note}。{rule_note}。"
           f"勝率只計算「只有一方帶這張牌」的對局；平手算半勝。\n"]
    r = 0
    while True:
        if deadline is None and r >= args.rounds:
            break
        if deadline is not None and r > 0 and time.time() >= deadline:
            break
        cards = read_cards()
        t0 = time.time()
        fingerprint = hashlib.sha256(open(BALANCE, "rb").read()).hexdigest()
        results = play_round(r, per_round, args.workers, args.cap, seed_base=args.seed_base + r * 1_000_000, must_have=args.must_have_lords, must_have_cards=args.must_have_cards, hz=args.hz)
        if hashlib.sha256(open(BALANCE, "rb").read()).hexdigest() != fingerprint:
            raise RuntimeError("balance.gd changed during this batch; results cannot be mixed")
        analysis = analyse(results, cards)
        if args.ema_decay > 0.0:
            for k, (rate, games) in list(analysis["cards"].items()):
                prev_w, prev_n = ema_stats.get(k, (0.0, 0.0))
                new_w = prev_w * args.ema_decay + rate * games
                new_n = prev_n * args.ema_decay + games
                ema_stats[k] = (new_w, new_n)
                eff_games = round(new_n)
                analysis["cards"][k] = ((new_w / new_n) if new_n > 0 else 0.5, eff_games)
        last = (deadline is None and r == args.rounds - 1 and not args.adjust_last) or (deadline is not None and time.time() >= deadline and not args.adjust_last)

        if args.per_match_delta > 0:
            for r_match in results:
                w = r_match["winner"]
                if w < 0: continue
                a = set(r_match["decks"][0])
                b = set(r_match["decks"][1])
                # Side 0 exclusive cards: a - b; Side 1 exclusive cards: b - a
                if w == 0:
                    for k in a - b:
                        float_costs[k] = min(float(MAX_COST), float_costs[k] + args.per_match_delta)
                    for k in b - a:
                        float_costs[k] = max(float(MIN_COST), float_costs[k] - args.per_match_delta)
                elif w == 1:
                    for k in a - b:
                        float_costs[k] = max(float(MIN_COST), float_costs[k] - args.per_match_delta)
                    for k in b - a:
                        float_costs[k] = min(float(MAX_COST), float_costs[k] + args.per_match_delta)
            changes = {}
            if not (args.dry_run or last):
                for kind in cards:
                    if kind in HOME_CARDS: continue
                    new_int = max(MIN_COST, min(MAX_COST, round_half_up(float_costs[kind])))
                    if new_int != cards[kind][1]:
                        changes[kind] = new_int
        else:
            # Damp step smoothly across rounds while keeping adjust responsive for long runs.
            damped_step = args.step / (1.0 + 0.15 * r)
            changes = {} if (args.dry_run or last) else adjust(analysis, cards, args.threshold, damped_step, args.min_games, args.shrinkage, args.max_delta)

        if allowed is not None: changes = {k: v for k, v in changes.items() if k in allowed}
        if excluded: changes = {k: v for k, v in changes.items() if k not in excluded}
        for k in changes:
            ema_stats.pop(k, None)
        section = f"\n## 第 {r + 1} 輪（{time.time() - t0:.0f} 秒）\n\n" + table(analysis, cards, changes, float_costs) + "\n"
        section += f"\n數值 SHA256：`{fingerprint}`；種子起點 {args.seed_base + r * 1_000_000}。\n"
        print(f"[round {r + 1}] {len(results)} matches in {time.time() - t0:.1f}s | changed {len(changes)} cards: {changes}", flush=True)
        log.append(section)
        if changes: write_costs(changes)
        open(REPORT, "w", encoding="utf-8").write("".join(log))
        r += 1

    final = {k: v[1] for k, v in read_cards().items()}
    if float_costs is not None:
        diff = [f"| {read_cards()[k][0]} | {start_costs[k]} | {float_costs[k]:.2f} | {final[k]} |" for k in final if final[k] != start_costs[k] or abs(float_costs[k] - start_costs[k]) > 0.001]
        log.append("\n## 費用總變動\n\n| 卡牌 | 原費用 | 浮點累積 | 新費用 |\n|---|---|---|---|\n" + "\n".join(diff) + "\n" if diff else "\n## 費用總變動\n\n無。\n")
    else:
        diff = [f"| {read_cards()[k][0]} | {start_costs[k]} | {final[k]} |" for k in final if final[k] != start_costs[k]]
        log.append("\n## 費用總變動\n\n| 卡牌 | 原費用 | 新費用 |\n|---|---|---|\n" + "\n".join(diff) + "\n" if diff else "\n## 費用總變動\n\n無。\n")
    open(REPORT, "w", encoding="utf-8").write("".join(log))
    print("report:", REPORT)


if __name__ == "__main__":
    sys.exit(main())
