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
    game.get_node("StallOccluder").visible = not game.panel_open and not game.settlement_open

func _draw() -> void:
    _draw_hud()
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
    # Large, high-contrast two-line HUD. Cash and time are fixed in the top-right.
    _panel(Rect2(4, 3, 196, 30), C_BG, Color("#566775"))
    _panel(Rect2(204, 3, 112, 14), Color("#2d2930"), Color("#b58c52"))
    _panel(Rect2(204, 19, 112, 14), Color("#1d303b"), Color("#568797"))

    _text("午夜小摊", Vector2(10, 15), 10, C_GOLD, 86)
    _text("第 %d 晚" % game.night, Vector2(104, 15), 9, C_TEXT, 86)
    _text("口碑 %d 成交 %d/%d 队 %d 入场 %d" % [game.reputation, game.served, game.total_customers(), game.queue_count(), game.customer_arrival_count()], Vector2(10, 28), 7, C_GREEN, 186)
    _text("现金 ¥%d" % game.cash, Vector2(209, 14), 9, C_GOLD, 102, HORIZONTAL_ALIGNMENT_RIGHT)
    _text("时间 %s" % game.game_time_text(), Vector2(209, 30), 9, C_CYAN, 102, HORIZONTAL_ALIGNMENT_RIGHT)

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
    _draw_panel_frame("原料采购 · 原料不能直接出售")
    var selected: Dictionary = game.item_data(game.selected_item)
    var total_cost: int = int(selected.cost) * game.requested_stock_qty
    _text("现金 ¥%d   仓储 %d/%d（原料+成品）" % [game.cash, game.total_stock(), game.max_total_stock()], Vector2(20, 68), 8, C_GOLD, 276)
    _text("1 饭团原料 ¥5  原料 %d  成品 %d" % [game.raw_stock[0], game.stock[0]], Vector2(20, 81), 8, C_TEXT if game.selected_item == 0 else C_MUTED, 276)
    _text("2 汤料包   ¥7  原料 %d  成品 %d" % [game.raw_stock[1], game.stock[1]], Vector2(20, 93), 8, C_TEXT if game.selected_item == 1 else C_MUTED, 276)
    _text("3 茶饮原料 ¥3  原料 %d  成品 %d" % [game.raw_stock[2], game.stock[2]], Vector2(20, 105), 8, C_TEXT if game.selected_item == 2 else C_MUTED, 276)
    _text("采购：%s 原料包 × %d = ¥%d" % [String(selected.name), game.requested_stock_qty, total_cost], Vector2(20, 119), 8, C_GOLD, 276)
    _text("← / → 调数量（1–5） · 单品总量上限 %d" % game.max_item_stock(), Vector2(20, 132), 7, C_MUTED, 276)
    _text(game.panel_feedback, Vector2(20, 145), 7, C_GREEN, 276)
    var footer: String
    if not game.current_customer.is_empty():
        footer = "Enter 进原料 · C 制作台 · B 返回订单"
    elif not game.service_started:
        footer = "Enter 进原料 · C 制作台 · F 开张（需成品）"
    else:
        footer = "Enter 进原料 · C 制作台 · Esc 关闭"
    _text(footer, Vector2(20, 159), 7, C_GREEN, 276)

func _draw_prep_panel() -> void:
    _draw_panel_frame("手工制作台 · 原料必须先做成菜")
    var selected: Dictionary = game.item_data(game.selected_item)
    _text("现金 ¥%d   原料 %d份   成品 %d份" % [game.cash, game.raw_stock[game.selected_item], game.stock[game.selected_item]], Vector2(20, 68), 8, C_GOLD, 276)
    _text("1 烤饭团  原料 %d → 成品 %d（%.1f秒）" % [game.raw_stock[0], game.stock[0], float(game.item_data(0).get("prep_seconds", 2.6))], Vector2(20, 81), 7, C_TEXT if game.selected_item == 0 else C_MUTED, 276)
    _text("2 热汤    原料 %d → 成品 %d（%.1f秒）" % [game.raw_stock[1], game.stock[1], float(game.item_data(1).get("prep_seconds", 4.2))], Vector2(20, 93), 7, C_TEXT if game.selected_item == 1 else C_MUTED, 276)
    _text("3 柠檬茶  原料 %d → 成品 %d（%.1f秒）" % [game.raw_stock[2], game.stock[2], float(game.item_data(2).get("prep_seconds", 1.8))], Vector2(20, 105), 7, C_TEXT if game.selected_item == 2 else C_MUTED, 276)
    _text("配方：%s" % String(selected.get("recipe", "原料包 ×1")), Vector2(20, 118), 8, C_CYAN, 276)
    if game.cooking_item >= 0:
        var cooking_name: String = String(game.item_data(game.cooking_item).name)
        _text("正在制作：%s · 剩余 %.1f 秒" % [cooking_name, maxf(0.0, game.cooking_time_remaining)], Vector2(20, 130), 8, C_GOLD, 276)
        var bar := Rect2(20, 135, 276, 4)
        draw_rect(bar, Color("#3d4b58"))
        draw_rect(Rect2(bar.position, Vector2(bar.size.x * game.cooking_progress(), bar.size.y)), C_GREEN)
    elif game.raw_stock[game.selected_item] > 0:
        _text("按 Enter 开始制作；计时结束后成品自动入库。", Vector2(20, 132), 7, C_GREEN, 276)
    else:
        _text("该菜品原料不足，按 B 采购原料包。", Vector2(20, 132), 7, C_RED, 276)
    _text(game.panel_feedback, Vector2(20, 145), 7, C_MUTED, 276)
    var footer: String
    if not game.current_customer.is_empty():
        footer = "1/2/3 选菜 · Enter 制作 · B 返回订单"
    elif not game.service_started:
        footer = "1/2/3 选菜 · Enter 制作 · B 采购 · F 开张"
    else:
        footer = "1/2/3 选菜 · Enter 制作 · B 原料采购"
    _text(footer, Vector2(20, 159), 7, C_GREEN, 276)

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
    _text("制作 %d份  偏好 %d  亲民 %d  溢价 %d" % [game.cooked_today, game.preferred_item_sales, game.discount_sales_count, game.premium_sales_count], Vector2(20, 138), 7, C_CYAN, 276)
    _text("现金 ¥%d→¥%d  口碑 %d  库存 %d/%d" % [game.night_start_cash, game.cash, game.reputation, game.total_stock(), game.max_total_stock()], Vector2(20, 148), 7, C_GOLD, 276)
    _text("Enter / 空格：进入下一晚（现金、原料、成品、口碑保留）", Vector2(20, 161), 7, C_GREEN, 276)
