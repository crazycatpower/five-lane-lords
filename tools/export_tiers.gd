extends SceneTree
# Regenerate the reference from the same tables validated by the game.
const B = preload("res://balance.gd")
func _initialize() -> void:
 var errors := B.validate()
 if not errors.is_empty():
  printerr(errors)
  quit(1)
  return
 var lines: Array[String] = ["# 數值檔次（SSS–G 十檔）", "", "由 `godot_console --headless --path . -s tools/export_tiers.gd` 從 balance.gd 產生。", "", "基礎生命、傷害、射程、移速、攻擊間隔、範圍及出牌冷卻必須符合檔次；部隊、召喚物、建築與領主均驗證。攻擊間隔與出牌冷卻越小越強。", "", "召喚專用單位不進手牌，冷卻 0 表示不適用；一般卡牌不可使用 0 秒冷卻。費用、數量、百分比、技能持續時間、動畫前搖與戰鬥中增減的生命並非基礎能力檔次。領主技能冷卻與出牌冷卻分開，未套用本次卡牌冷卻表。", ""]
 var titles := {"hp":"生命", "damage":"單體傷害", "area_damage":"範圍傷害", "radius":"範圍半徑", "range":"射程", "speed":"移速", "interval":"攻擊間隔（秒）", "cooldown":"出牌冷卻（秒）"}
 for stat: String in titles:
  lines.append("## "+titles[stat])
  lines.append("")
  lines.append("| 檔次 | 數值 | 定位 | 目前使用 |")
  lines.append("|---|---:|---|---|")
  for i: int in range(B.TIER_NAMES.size()):
   var value: float = B.TIERS[stat][i]
   var names: Array[String] = []
   for kind: String in B.CARDS:
    var d: Dictionary = B.CARDS[kind]
    var key := stat
    var area: bool = d.type == "spell" or d.has("area_damage")
    if stat == "damage" and area: continue
    if stat == "area_damage" and area and d.has("damage"): key = "damage"
    if d.has(key) and is_equal_approx(d[key],value): names.append(d.name)
   if stat in ["hp","damage","speed"]:
    for kind: String in B.LORDS:
     if is_equal_approx(B.LORDS[kind].get(stat,-1),value): names.append(B.LORDS[kind].name)
   lines.append("| %s | %s | %s | %s |" % [B.TIER_NAMES[i],B.number(value),B.TIER_NOTES[stat][i],"、".join(names) if not names.is_empty() else "—"])
  lines.append("")
 lines.append("## 驗證範圍")
 lines.append("")
 lines.append("B.validate() 另驗證全體小怪領主的生命、傷害及移速；混編牌沿用成員資料。維修距離／間隔／回復量、支援量、再生、咀嚼回血、衝鋒傷害與共用治療數值也按對應檔次檢查。戰鬥中的護甲、倍率、BUFF 和肉鴿強化屬規則運算，不把最終傷害或目前生命強制取整到檔次。")
 var f := FileAccess.open("res://docs/數值檔次.md",FileAccess.WRITE)
 f.store_string("\n".join(lines)+"\n")
 print("Tier reference generated; %d cards, %d lords, %d enemy lords validated" % [B.CARDS.size(),B.LORDS.size(),B.MINION_LORDS.size()])
 quit(0)
