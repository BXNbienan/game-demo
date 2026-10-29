extends Node2D

@onready var game = get_parent()

const C_BG := Color("#111925")
const C_PANEL := Color("#202f40")
const C_PANEL_DARK := Color("#172230")
const C_BORDER := Color("#ddb875")
const C_TEXT := Color("#fff4dc")
const C_MUTED := Color("#d2dddc")
const C_GOLD := Color("#ffe08c")
const C_GREEN := Color("#aee4bd")
const C_RED := Color("#ffc0a8")
const C_CYAN := Color("#a9e5ef")

func _process(_delta: float) -> void:
    queue_redraw()
    # Keep foreground objects behind all game UI and settlement panels.
    game.get_node("StallOccluder").visible = not game.home_mode and not game.panel_open and not game.settlement_open

func _draw() -> void:
    _draw_hud()
    if game.home_mode:
        if game.panel_open and game.panel_mode == "seeds":
            _draw_seed_shop_panel()
        else:
            _draw_home_help()
        return
    if game.settlement_open:
        _draw_settlement_panel()
        return
    if game.panel_open:
        if game.panel_mode == "stock":
            _draw_stock_panel()
        elif game.panel_mode == "prep":
            _draw_prep_panel()
        else:
            _draw_sale_panel()
        return

    # Keep prompts in a narrow left-side column. Earlier bottom banners crossed
    # the customer's entrance lane (x≈202, y≈176→108), making movement appear
    # invisible even when the actor was walking correctly.
    if not game.service_started and not game.game_finished:
        _panel(Rect2(4, 36, 188, 18), Color("#111925"), Color("#c89f63"))
        _text("B 采购原料 · 到左侧备菜台按 C 制作 · F 开张", Vector2(8, 48), 7, C_GOLD, 180)
    elif game._near_stall() and not game.game_finished:
        _panel(Rect2(4, 36, 188, 18), Color("#111925"), Color("#c89f63"))
        _text("E 接待队首 · B 备货", Vector2(8, 48), 8, C_TEXT, 180)

    if game.result_clock > 0.0 and not game.game_finished:
        _panel(Rect2(4, 56, 188, 17), Color("#111925"), Color("#344858"))
        _text(game.last_result, Vector2(8, 67), 7, C_TEXT, 180)

    _text("WASD / 方向键移动", Vector2(8, 178), 8, C_MUTED, 170)

func _text(value: String, pos: Vector2, size: int = 9, color: Color = C_TEXT, width: float = -1.0, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
    draw_string(ThemeDB.fallback_font, pos, value, alignment, width, size, color)

func _panel(rect: Rect2, fill: Color = C_PANEL_DARK, border: Color = C_BORDER) -> void:
    draw_rect(rect, fill)
    draw_rect(rect, border, false, 1.0)

func _draw_hud() -> void:
    if game.home_mode:
        _panel(Rect2(4, 3, 196, 40), C_BG, Color("#566775"))
        _panel(Rect2(204, 3, 112, 18), Color("#2d2930"), Color("#b58c52"))
        _panel(Rect2(204, 23, 112, 18), Color("#1d303b"), Color("#568797"))
        _text("小屋农场 · 第 %d 天" % game.farm_day, Vector2(10, 15), 10, C_GOLD, 186)
        _text("种子 稻%d 菜%d 柠%d" % [game.seed_stock[0], game.seed_stock[1], game.seed_stock[2]], Vector2(10, 27), 7, C_GREEN, 186)
        _text("收获 米%d 菜%d 柠%d" % [game.produce_stock[0], game.produce_stock[1], game.produce_stock[2]], Vector2(10, 38), 7, C_CYAN, 186)
        _text("现金 ¥%d" % game.cash, Vector2(209, 15), 9, C_GOLD, 102, HORIZONTAL_ALIGNMENT_RIGHT)
        _text("白天 %s" % game.game_time_text(), Vector2(209, 35), 9, C_CYAN, 102, HORIZONTAL_ALIGNMENT_RIGHT)
        return
    # Large, high-contrast two-line HUD. Cash and time are fixed in the top-right.
    _panel(Rect2(4, 3, 196, 30), C_BG, Color("#566775"))
    _panel(Rect2(204, 3, 112, 14), Color("#2d2930"), Color("#b58c52"))
    _panel(Rect2(204, 19, 112, 14), Color("#1d303b"), Color("#568797"))

    _text("午夜小摊", Vector2(10, 15), 10, C_GOLD, 86)
    _text("第 %d 晚" % game.night, Vector2(104, 15), 9, C_TEXT, 86)
    _text("口碑 %d 成交 %d/%d 队 %d 入场 %d" % [game.reputation, game.served, game.total_customers(), game.queue_count(), game.customer_arrival_count()], Vector2(10, 28), 7, C_GREEN, 186)
    _text("现金 ¥%d" % game.cash, Vector2(209, 14), 9, C_GOLD, 102, HORIZONTAL_ALIGNMENT_RIGHT)
    _text("时间 %s" % game.game_time_text(), Vector2(209, 30), 9, C_CYAN, 102, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_home_help() -> void:
    _panel(Rect2(4, 44, 240, 23), C_BG, C_BORDER)
    _text("1/2/3 选种  ·  E 操作最近的地块  ·  B 买种子", Vector2(8, 54), 7, C_GOLD, 232)
    _text("成熟按 E 收获，生长期按 E 浇水；F 去夜市，T 睡到明天。", Vector2(8, 64), 6, C_TEXT, 232)
    if game.result_clock > 0.0 and not game.last_result.is_empty():
        _panel(Rect2(4, 68, 240, 11), Color("#111925"), Color("#485f4a"))
        _text(game.farm_feedback, Vector2(8, 76), 5, C_GREEN, 232)

func _draw_seed_shop_panel() -> void:
    _draw_panel_frame("小屋种子箱 · 种子可重复购买")
    var crop: Dictionary = game.crop_data(game.selected_crop)
    var total_cost: int = int(crop.seed_cost) * game.requested_seed_qty
    _text("现金 ¥%d   当前选择：%s" % [game.cash, String(crop.seed_name)], Vector2(20, 68), 8, C_GOLD, 276)
    _text("1 稻种 ¥2  持有 %d" % game.seed_stock[0], Vector2(20, 82), 8, C_TEXT if game.selected_crop == 0 else C_MUTED, 276)
    _text("2 菜种 ¥3  持有 %d" % game.seed_stock[1], Vector2(20, 94), 8, C_TEXT if game.selected_crop == 1 else C_MUTED, 276)
    _text("3 柠檬苗 ¥4 持有 %d" % game.seed_stock[2], Vector2(20, 106), 8, C_TEXT if game.selected_crop == 2 else C_MUTED, 276)
    _text("购买数量 %d  ·  合计 ¥%d" % [game.requested_seed_qty, total_cost], Vector2(20, 121), 9, C_GOLD, 276)
    _text("← / → 调数量（1–5） · Enter 购买 · Esc 关闭", Vector2(20, 135), 7, C_TEXT, 276)
    _text(game.farm_feedback, Vector2(20, 148), 7, C_GREEN, 276)
    _text("返回农田：1/2/3 选种 · E 操作地块 · F 前往夜市", Vector2(20, 161), 7, C_GREEN, 276)

func _draw_panel_frame(title: String) -> void:
    _panel(Rect2(10, 34, 300, 134), C_BG, C_BORDER)
    draw_rect(Rect2(13, 37, 294, 17), C_PANEL)
    _text(title, Vector2(20, 49), 10, C_GOLD, 280)
    draw_line(Vector2(18, 55), Vector2(302, 55), Color("#5c7180"), 1.0)

func _draw_sale_panel() -> void:
    _draw_panel_frame("顾客订单")
    if game.current_customer.is_empty():
        _text("当前没有待服务顾客。", Vector2(20, 73), 9, C_TEXT, 274)
        _text("按 E 接待队首顾客，或按 B 进行备货。", Vector2(20, 91), 8, C_MUTED, 274)
        _text("Enter / 空格确认   Esc 关闭", Vector2(20, 158), 8, C_GREEN, 274)
        return

    var customer: Dictionary = game.current_customer
    var favorite: Dictionary = game.item_data(int(customer.get("likes", 0)))
    _text("顾客：%s  ·  特点：%s" % [String(customer.get("name", "顾客")), String(customer.get("style", "普通顾客"))], Vector2(20, 68), 8, C_TEXT, 276)
    _text("需求：%s  预算 ¥%d  耐心 %d/%d" % [String(customer.get("need", "未知")), int(customer.get("budget", 0)), int(customer.get("patience", 0)), int(customer.get("patience_max", 2))], Vector2(20, 80), 8, C_GREEN, 276)
    _text("偏好：%s   成品 饭团 %d  热汤 %d  茶 %d" % [String(favorite.name), game.stock[0], game.stock[1], game.stock[2]], Vector2(20, 92), 7, C_CYAN, 276)

    var item: Dictionary = game.item_data(game.selected_item)
    var asking_price: int = game.price_for_item(game.selected_item, game.price_tier)
    var expected_profit: int = asking_price - int(item.cost)
    _text("选中：%s   成品库存 %d   售价 ¥%d" % [String(item.name), game.stock[game.selected_item], asking_price], Vector2(20, 105), 9, C_GOLD, 276)
    _text("价格：%s  (← / →)   预计单份毛利 ¥%d" % [game.price_label(game.price_tier), expected_profit], Vector2(20, 118), 8, C_TEXT, 276)
    _text(game._offer_hint(game.selected_item, game.price_tier), Vector2(20, 131), 8, C_MUTED, 276)
    _text(game.panel_feedback, Vector2(20, 144), 8, C_RED if game.panel_feedback.find("拒绝") >= 0 or game.panel_feedback.find("超过") >= 0 else C_GREEN, 276)
    _text("1/2/3 选品   Enter 上菜   B 原料采购   C 制作台", Vector2(20, 159), 8, C_GREEN, 276)

func _draw_stock_panel() -> void:
    _draw_panel_frame("辅料采购 · 自种作物不能省略")
    var selected: Dictionary = game.item_data(game.selected_item)
    var total_cost: int = int(selected.cost) * game.requested_stock_qty
    _text("现金 ¥%d   仓储 %d/%d（作物+辅料+成品）" % [game.cash, game.total_stock(), game.max_total_stock()], Vector2(20, 68), 8, C_GOLD, 276)
    _text("1 海苔辅料 ¥5  辅料 %d  稻米 %d  成品 %d" % [game.raw_stock[0], game.produce_stock[0], game.stock[0]], Vector2(20, 81), 7, C_TEXT if game.selected_item == 0 else C_MUTED, 276)
    _text("2 汤底辅料 ¥7  辅料 %d  蔬菜 %d  成品 %d" % [game.raw_stock[1], game.produce_stock[1], game.stock[1]], Vector2(20, 93), 7, C_TEXT if game.selected_item == 1 else C_MUTED, 276)
    _text("3 茶底辅料 ¥3  辅料 %d  柠檬 %d  成品 %d" % [game.raw_stock[2], game.produce_stock[2], game.stock[2]], Vector2(20, 105), 7, C_TEXT if game.selected_item == 2 else C_MUTED, 276)
    _text("采购：%s辅料 × %d = ¥%d" % [String(selected.name), game.requested_stock_qty, total_cost], Vector2(20, 119), 8, C_GOLD, 276)
    _text("← / → 调数量（1–5） · 单品总量上限 %d" % game.max_item_stock(), Vector2(20, 132), 7, C_MUTED, 276)
    _text(game.panel_feedback, Vector2(20, 145), 7, C_GREEN, 276)
    var footer: String
    if not game.current_customer.is_empty():
        footer = "Enter 进原料 · C 制作台 · B 返回订单"
    elif not game.service_started:
        footer = "Enter 采购辅料 · C 制作 · F 开张 · H 回小屋"
    else:
        footer = "Enter 采购辅料 · C 制作台 · Esc 关闭"
    _text(footer, Vector2(20, 159), 7, C_GREEN, 276)

func _draw_prep_panel() -> void:
    _draw_panel_frame("手工制作台 · 炒制动画与火候小游戏")
    var selected: Dictionary = game.item_data(game.selected_item)
    _text("现金 ¥%d   辅料 %d   自种原料 %d   成品 %d" % [game.cash, game.raw_stock[game.selected_item], game.produce_stock[game.selected_item], game.stock[game.selected_item]], Vector2(20, 68), 7, C_GOLD, 276)
    _text("1 烤饭团  稻米 %d + 海苔 %d → 成品 %d（%.1f秒）" % [game.produce_stock[0], game.raw_stock[0], game.stock[0], float(game.item_data(0).get("prep_seconds", 2.6))], Vector2(20, 80), 6, C_TEXT if game.selected_item == 0 else C_MUTED, 276)
    _text("2 热汤    蔬菜 %d + 汤底 %d → 成品 %d（%.1f秒）" % [game.produce_stock[1], game.raw_stock[1], game.stock[1], float(game.item_data(1).get("prep_seconds", 4.2))], Vector2(20, 91), 6, C_TEXT if game.selected_item == 1 else C_MUTED, 276)
    _text("3 柠檬茶  柠檬 %d + 茶底 %d → 成品 %d（%.1f秒）" % [game.produce_stock[2], game.raw_stock[2], game.stock[2], float(game.item_data(2).get("prep_seconds", 1.8))], Vector2(20, 102), 6, C_TEXT if game.selected_item == 2 else C_MUTED, 276)
    _text("配方：自种作物 ×1 + 采购辅料 ×1", Vector2(20, 113), 8, C_CYAN, 276)

    if game.cooking_item >= 0:
        var cooking_name: String = String(game.item_data(game.cooking_item).name)
        _text("正在炒制：%s · 剩余 %.1f 秒" % [cooking_name, maxf(0.0, game.cooking_time_remaining)], Vector2(20, 124), 8, C_GOLD, 276)
        var progress_rect := Rect2(20, 128, 276, 4)
        draw_rect(progress_rect, Color("#3d4b58"))
        draw_rect(Rect2(progress_rect.position, Vector2(progress_rect.size.x * game.cooking_progress(), progress_rect.size.y)), C_GREEN)
        _text("火候：绿区=不错，金区=完美；按 SPACE（仅一次）" if not game.cooking_timing_attempted else game.cooking_timing_message, Vector2(20, 139), 7, C_TEXT, 276)
        var gauge := Rect2(20, 143, 276, 7)
        draw_rect(gauge, Color("#273441"))
        var good_start := gauge.position.x + gauge.size.x * 0.48
        draw_rect(Rect2(good_start, gauge.position.y, gauge.size.x * 0.28, gauge.size.y), Color("#397350"))
        var perfect_start := gauge.position.x + gauge.size.x * 0.575
        draw_rect(Rect2(perfect_start, gauge.position.y, gauge.size.x * 0.09, gauge.size.y), Color("#d5a64d"))
        var cooking_progress: float = float(game.cooking_progress())
        var marker_x: float = gauge.position.x + gauge.size.x * cooking_progress
        var marker_color := Color("#fff4dc")
        if game.cooking_timing_attempted:
            marker_color = Color("#ffe08c") if game.cooking_quality >= 2 else (Color("#aee4bd") if game.cooking_quality == 1 else Color("#ffc0a8"))
        draw_rect(Rect2(marker_x - 1.0, gauge.position.y - 2.0, 3.0, gauge.size.y + 4.0), marker_color)
        _text("火候结果：%s" % game.cooking_quality_label(game.cooking_quality) if game.cooking_timing_attempted else "看准指针进入目标区域，再按空格", Vector2(20, 160), 7, C_GREEN if game.cooking_quality > 0 else C_MUTED, 276)
    elif game.raw_stock[game.selected_item] > 0 and game.produce_stock[game.selected_item] > 0:
        _text("原料齐全；Enter 制作，SPACE 把握火候。", Vector2(20, 129), 7, C_GREEN, 276)
        _text(game.panel_feedback, Vector2(20, 145), 7, C_MUTED, 276)
    else:
        _text("作物或辅料不足：回小屋种植收获，或按 B 采购辅料。", Vector2(20, 129), 7, C_RED, 276)
        _text(game.panel_feedback, Vector2(20, 145), 7, C_MUTED, 276)
    var footer: String
    if not game.current_customer.is_empty():
        footer = "1/2/3 选菜 · Enter 制作 · SPACE 把握火候 · B 返回订单"
    elif not game.service_started:
        footer = "1/2/3 选菜 · Enter 制作 · SPACE 把握火候 · B 采购 · F 开张"
    else:
        footer = "1/2/3 选菜 · Enter 制作 · SPACE 把握火候 · B 采购"
    _text(footer, Vector2(20, 166), 6, C_GREEN, 276)

func _draw_settlement_panel() -> void:
    _panel(Rect2(10, 34, 300, 134), C_BG, C_BORDER)
    draw_rect(Rect2(13, 37, 294, 18), Color("#3a3027"))
    _text("第 %d 晚 · 每日结算" % game.night, Vector2(20, 50), 10, C_GOLD, 280)
    draw_line(Vector2(18, 56), Vector2(302, 56), Color("#8d7958"), 1.0)

    var gross_profit: int = game.revenue_total - game.cost_of_goods_sold
    var cash_flow: int = game.revenue_total - game.purchase_spend
    _text("营业时间：20:00 — %s" % game.game_time_text(), Vector2(20, 68), 8, C_CYAN, 276)
    _text("成交 %d  流失 %d  报价尝试 %d" % [game.served, game.lost_customers, game.transaction_attempts], Vector2(20, 78), 7, C_TEXT, 276)
    _text("销售流水       ¥%d" % game.revenue_total, Vector2(20, 88), 7, C_TEXT, 276)
    _text("销货成本       ¥%d" % game.cost_of_goods_sold, Vector2(20, 98), 7, C_TEXT, 276)
    _text("商品毛利       ¥%d" % gross_profit, Vector2(20, 108), 8, C_GREEN, 276)
    _text("本晚进货支出   ¥%d" % game.purchase_spend, Vector2(20, 118), 7, C_TEXT, 276)
    var flow_color := C_GREEN if cash_flow >= 0 else C_RED
    _text("现金流变化     %s¥%d" % ["+" if cash_flow >= 0 else "-", abs(cash_flow)], Vector2(20, 128), 7, flow_color, 276)
    _text("制作 %d份 · 完美火候 %d · 不错火候 %d" % [game.cooked_today, game.perfect_cooks_today, game.good_cooks_today], Vector2(20, 138), 7, C_CYAN, 276)
    _text("现金 ¥%d→¥%d  口碑 %d  库存 %d/%d" % [game.night_start_cash, game.cash, game.reputation, game.total_stock(), game.max_total_stock()], Vector2(20, 148), 7, C_GOLD, 276)
    _text("Enter / 空格：进入下一晚（现金、原料、成品、口碑保留）", Vector2(20, 161), 7, C_GREEN, 276)
