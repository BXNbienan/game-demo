extends Node2D

const ITEMS := [
    {"name": "烤饭团", "cost": 5, "base": 12, "fav": "热食", "prep_seconds": 2.6, "recipe": "米饭 ×1 + 海苔 ×1"},
    {"name": "热汤", "cost": 7, "base": 16, "fav": "热食", "prep_seconds": 4.2, "recipe": "汤底 ×1 + 蔬菜 ×1"},
    {"name": "柠檬茶", "cost": 3, "base": 10, "fav": "饮品", "prep_seconds": 1.8, "recipe": "柠檬 ×1 + 茶底 ×1"},
]
const CUSTOMERS := [
    {"name": "夜班护士", "need": "热食", "budget": 20, "likes": 0, "patience": 3, "style": "赶时间", "quote": "麻烦快一点，想吃热的。", "reject_patience_loss": 2, "premium_averse": false},
    {"name": "赶末班车的学生", "need": "饮品", "budget": 15, "likes": 2, "patience": 2, "style": "精打细算", "quote": "来杯划算的饮料。", "reject_patience_loss": 1, "premium_averse": true},
    {"name": "深夜加班族", "need": "热食", "budget": 23, "likes": 1, "patience": 3, "style": "口味优先", "quote": "今晚想喝口热汤。", "reject_patience_loss": 1, "premium_averse": false},
    {"name": "雨夜旅人", "need": "饮品", "budget": 15, "likes": 2, "patience": 2, "style": "随和旅人", "quote": "来杯清爽的柠檬茶。", "reject_patience_loss": 1, "premium_averse": false},
    {"name": "夜钓爱好者", "need": "热食", "budget": 16, "likes": 0, "patience": 3, "style": "熟客", "quote": "老样子，烤饭团。", "reject_patience_loss": 1, "premium_averse": false},
]
const PRICE_MULTIPLIERS := [0.8, 1.0, 1.35]
const PRICE_LABELS := ["亲民价", "标准价", "溢价"]
const CUSTOMER_SCENE := preload("res://customer_actor.tscn")
# Customers queue across the stall frontage; the first slot is centered at the counter.
# Followers wait to the left and step right into the front slot after a sale.
const QUEUE_SLOTS := [Vector2(202, 108), Vector2(178, 108), Vector2(154, 108)]
const MAX_QUEUE_SIZE := 3
const REPLENISH_DELAY := 1.05
const MAX_TOTAL_STOCK := 15
const MAX_ITEM_STOCK := 8
const MAX_PURCHASE_BATCH := 5

@onready var player: CharacterBody2D = $Player

# Finished dishes are the only items that can be served. Raw ingredient packs
# must be purchased and manually cooked at the prep station first.
var stock: Array[int] = [0, 0, 0] # finished servings ready for sale
var raw_stock: Array[int] = [0, 0, 0] # ingredient packs, one pack makes one serving
var cooking_item: int = -1
var cooking_time_remaining: float = 0.0
var cooking_time_total: float = 0.0
var cooked_today: int = 0
var cash: int = 40
var reputation: int = 50
var served: int = 0
var lost_customers: int = 0
var transaction_attempts: int = 0
var revenue_total: int = 0
var cost_of_goods_sold: int = 0
var purchase_spend: int = 0
# Extra service metrics used by the daily settlement panel.
var preferred_item_sales: int = 0
var discount_sales_count: int = 0
var premium_sales_count: int = 0
var refused_offers_count: int = 0
var night: int = 1
var night_start_cash: int = 40
var game_time_minutes: int = 20 * 60
var game_minute_fraction: float = 0.0
var settlement_open: bool = false
var selected_item: int = 0
var price_tier: int = 1
var requested_stock_qty: int = 1
var panel_open: bool = false
var panel_mode: String = "sale" # "sale" or "stock"
var current_customer: Dictionary = {}
var panel_feedback: String = ""
var last_result: String = "按 B 采购原料，走到左侧备菜台按 C 制作；至少做好一份成品后按 F 开张。"
var result_clock: float = 5.0
var game_finished: bool = false
# Customers and the in-game clock remain paused during the stocking phase.
var service_started: bool = false

# Queue order is front (closest to the stall) to back.
var customer_queue: Array[Node2D] = []
var exiting_customers: Array[Node2D] = []
var spawned_customer_count: int = 0
var replenish_clock: float = -1.0

func item_data(index: int) -> Dictionary:
    return ITEMS[clampi(index, 0, ITEMS.size() - 1)]

func price_multiplier(index: int) -> float:
    return PRICE_MULTIPLIERS[clampi(index, 0, PRICE_MULTIPLIERS.size() - 1)]

func price_label(index: int) -> String:
    return PRICE_LABELS[clampi(index, 0, PRICE_LABELS.size() - 1)]

func price_for_item(item_index: int, tier: int) -> int:
    var item: Dictionary = item_data(item_index)
    return int(round(float(item.base) * price_multiplier(tier)))

func total_customers() -> int:
    return CUSTOMERS.size()

func completed_customers() -> int:
    return served + lost_customers

func queue_count() -> int:
    return customer_queue.size()

func total_stock() -> int:
    # Shared storage is occupied by both raw packs and finished dishes.
    var total := 0
    for amount in stock:
        total += amount
    for amount in raw_stock:
        total += amount
    return total

func total_ready_stock() -> int:
    var total := 0
    for amount in stock:
        total += amount
    return total

func item_total_stock(index: int) -> int:
    var safe_index := clampi(index, 0, ITEMS.size() - 1)
    return stock[safe_index] + raw_stock[safe_index]

func stock_space_left() -> int:
    return maxi(0, MAX_TOTAL_STOCK - total_stock())

func max_total_stock() -> int:
    return MAX_TOTAL_STOCK

func max_item_stock() -> int:
    return MAX_ITEM_STOCK

func front_customer_ready() -> bool:
    if customer_queue.is_empty():
        return false
    return bool(customer_queue[0].get("has_arrived")) and not bool(customer_queue[0].get("exiting"))

func _ready() -> void:
    _add_collision_rect(Vector2(160, -4), Vector2(320, 8))
    _add_collision_rect(Vector2(160, 184), Vector2(320, 8))
    _add_collision_rect(Vector2(-4, 90), Vector2(8, 180))
    _add_collision_rect(Vector2(324, 90), Vector2(8, 180))
    _add_collision_rect(Vector2(202, 61), Vector2(82, 19))
    _add_collision_rect(Vector2(155, 43), Vector2(18, 8))
    _add_collision_rect(Vector2(136, 81), Vector2(24, 8))
    # Do not spawn customers at game startup. They enter only after stocking ends.
    queue_redraw()

func _process(delta: float) -> void:
    result_clock = maxf(0.0, result_clock - delta)
    # Cooking uses real-time progress. The finished dish is added only when the
    # recipe timer completes; closing the panel does not silently cancel it.
    if not settlement_open:
        _update_cooking(delta)
    # Drive customer actors from the same active loop as the game clock.
    _update_customer_actors(delta)
    if not game_finished and service_started:
        _update_game_clock(delta)
        _update_customer_replenishment(delta)

func _update_customer_actors(delta: float) -> void:
    # Use a snapshot because a customer can finish exiting and remove itself from
    # exiting_customers during advance().
    var actors_to_update: Array[Node2D] = []
    actors_to_update.append_array(customer_queue)
    actors_to_update.append_array(exiting_customers)
    for actor in actors_to_update:
        if is_instance_valid(actor) and actor.has_method("advance"):
            actor.call("advance", delta)

func customer_arrival_count() -> int:
    var count := 0
    for actor in customer_queue:
        if is_instance_valid(actor) and not bool(actor.get("has_arrived")) and not bool(actor.get("exiting")):
            count += 1
    return count

func _update_game_clock(delta: float) -> void:
    # Five in-game minutes pass per real second. The clock is for the current
    # shift and remains visible in menus; it stops when daily settlement opens.
    game_minute_fraction += delta * 5.0
    var minutes_to_add := int(game_minute_fraction)
    if minutes_to_add > 0:
        game_minute_fraction -= float(minutes_to_add)
        game_time_minutes = posmod(game_time_minutes + minutes_to_add, 24 * 60)

func game_time_text() -> String:
    var safe_minutes := posmod(game_time_minutes, 24 * 60)
    return "%02d:%02d" % [floori(float(safe_minutes) / 60.0), safe_minutes % 60]

func _update_customer_replenishment(delta: float) -> void:
    if game_finished or not service_started or spawned_customer_count >= CUSTOMERS.size() or customer_queue.size() >= MAX_QUEUE_SIZE:
        replenish_clock = -1.0
        return
    if replenish_clock < 0.0:
        replenish_clock = REPLENISH_DELAY
        return
    replenish_clock = maxf(0.0, replenish_clock - delta)
    if replenish_clock <= 0.0:
        _spawn_customer(customer_queue.size(), 0.0)
        if spawned_customer_count < CUSTOMERS.size() and customer_queue.size() < MAX_QUEUE_SIZE:
            replenish_clock = 0.75
        else:
            replenish_clock = -1.0

func _spawn_customer(slot_index: int, delay: float = 0.0) -> void:
    if spawned_customer_count >= CUSTOMERS.size() or customer_queue.size() >= MAX_QUEUE_SIZE:
        return
    slot_index = clampi(slot_index, 0, MAX_QUEUE_SIZE - 1)
    var customer_data: Dictionary = CUSTOMERS[spawned_customer_count].duplicate(true)
    customer_data["patience_max"] = int(customer_data.get("patience", 2))
    var actor := CUSTOMER_SCENE.instantiate() as Node2D
    add_child(actor)
    actor.connect("finished_exit", Callable(self, "_on_customer_finished_exit"))
    var slot: Vector2 = QUEUE_SLOTS[slot_index]
    # Every customer visibly enters from the bottom-center street entrance.
    # Queue repositioning is stored as a pending destination, so it cannot erase
    # this multi-point arrival route.
    var spawn_point := Vector2(202, 176)
    var path_points: Array[Vector2] = [Vector2(202, 148), Vector2(slot.x, 128), slot]
    actor.call("setup", customer_data, spawn_point, path_points, spawned_customer_count, delay)
    customer_queue.append(actor)
    spawned_customer_count += 1
    _reposition_queue()

func _reposition_queue() -> void:
    for i in range(customer_queue.size()):
        if i >= QUEUE_SLOTS.size():
            break
        var actor: Node2D = customer_queue[i]
        if bool(actor.get("exiting")):
            continue
        actor.call("move_to_slot", QUEUE_SLOTS[i])

func _send_front_customer_away() -> void:
    if customer_queue.is_empty():
        return
    var actor: Node2D = customer_queue.pop_front()
    exiting_customers.append(actor)
    actor.call("begin_exit")
    _reposition_queue()
    replenish_clock = REPLENISH_DELAY

func _on_customer_finished_exit(actor: Node2D) -> void:
    exiting_customers.erase(actor)

func _add_collision_rect(center: Vector2, size: Vector2) -> void:
    var body := StaticBody2D.new()
    body.position = center
    add_child(body)
    var shape_node := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = size
    shape_node.shape = shape
    body.add_child(shape_node)

func _near_stall() -> bool:
    return player.global_position.distance_to(Vector2(202, 88)) <= 34.0

func _near_prep_station() -> bool:
    # The prep table is visually separate, to the left of the main counter.
    return player.global_position.distance_to(Vector2(136, 91)) <= 28.0

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    var key := event as InputEventKey

    if settlement_open:
        if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
            _start_next_night()
        get_viewport().set_input_as_handled()
        return

    if panel_open:
        if key.keycode == KEY_ESCAPE:
            if not current_customer.is_empty() and panel_mode != "sale":
                panel_mode = "sale"
                panel_feedback = "继续为 %s 选商品和价格。" % String(current_customer.get("name", "顾客"))
            else:
                panel_open = false
                if not service_started:
                    last_result = "准备阶段：B 采购原料，C 制作成品，准备好后按 F 开张。"
                    result_clock = 4.0
        elif panel_mode == "stock":
            if key.keycode == KEY_C:
                panel_mode = "prep"
                panel_feedback = "选择菜品后按 Enter 开始制作。原料包不能直接出售。"
            elif key.keycode == KEY_F and current_customer.is_empty() and not service_started:
                _finish_stocking_and_start_service()
            elif key.keycode == KEY_B:
                if not current_customer.is_empty():
                    panel_mode = "sale"
                    panel_feedback = "继续为 %s 选商品和价格。" % String(current_customer.get("name", "顾客"))
                else:
                    panel_open = false
            elif key.keycode == KEY_1:
                selected_item = 0
            elif key.keycode == KEY_2:
                selected_item = 1
            elif key.keycode == KEY_3:
                selected_item = 2
            elif key.keycode == KEY_LEFT:
                requested_stock_qty = maxi(1, requested_stock_qty - 1)
            elif key.keycode == KEY_RIGHT:
                requested_stock_qty = mini(MAX_PURCHASE_BATCH, requested_stock_qty + 1)
            elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
                _buy_stock()
        elif panel_mode == "prep":
            if key.keycode == KEY_B:
                if not current_customer.is_empty():
                    panel_mode = "sale"
                    panel_feedback = "继续为 %s 选商品和价格。" % String(current_customer.get("name", "顾客"))
                else:
                    panel_mode = "stock"
                    panel_feedback = "选择原料包数量，按 Enter 采购；C 可返回制作台。"
            elif key.keycode == KEY_F and current_customer.is_empty() and not service_started:
                _finish_stocking_and_start_service()
            elif key.keycode == KEY_1:
                selected_item = 0
            elif key.keycode == KEY_2:
                selected_item = 1
            elif key.keycode == KEY_3:
                selected_item = 2
            elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
                _start_cooking()
        else: # sale mode
            if key.keycode == KEY_B:
                panel_mode = "stock"
                requested_stock_qty = 1
                panel_feedback = "采购原料期间顾客暂停等待；按 C 制作，按 B 返回订单。"
            elif key.keycode == KEY_C:
                panel_mode = "prep"
                panel_feedback = "选择原料并按 Enter 制作；成品完成后再上菜。"
            elif key.keycode == KEY_1:
                selected_item = 0
            elif key.keycode == KEY_2:
                selected_item = 1
            elif key.keycode == KEY_3:
                selected_item = 2
            elif key.keycode == KEY_LEFT:
                price_tier = maxi(0, price_tier - 1)
            elif key.keycode == KEY_RIGHT:
                price_tier = mini(2, price_tier + 1)
            elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
                _serve_customer()
        get_viewport().set_input_as_handled()
        return

    if game_finished:
        return

    if key.keycode == KEY_B and _near_stall():
        panel_open = true
        panel_mode = "stock"
        requested_stock_qty = 1
        panel_feedback = "采购的是原料包；按 C 制作成品，按 F 开张。"
        get_viewport().set_input_as_handled()
        return

    if key.keycode == KEY_C and _near_prep_station():
        panel_open = true
        panel_mode = "prep"
        panel_feedback = "每份原料包只能制作一份成品；选菜品后按 Enter。"
        get_viewport().set_input_as_handled()
        return

    if key.keycode == KEY_F and _near_stall() and not service_started:
        if total_ready_stock() > 0:
            _finish_stocking_and_start_service()
        else:
            last_result = "请先按 B 采购原料，再按 C 制作至少一份成品。"
            result_clock = 3.5
        get_viewport().set_input_as_handled()
        return

    if key.keycode == KEY_E and _near_stall():
        if not service_started:
            last_result = "准备阶段：按 B 采购原料，按 C 制作；至少制作一份成品后按 F 开张。"
            result_clock = 3.5
            get_viewport().set_input_as_handled()
            return
        if current_customer.is_empty():
            if customer_queue.is_empty():
                last_result = "街口暂时没人，等下一位顾客走进来。"
                result_clock = 2.5
                get_viewport().set_input_as_handled()
                return
            if not front_customer_ready():
                last_result = "顾客还在走过来，请稍等一下。"
                result_clock = 2.5
                get_viewport().set_input_as_handled()
                return
            var front_data: Dictionary = customer_queue[0].get("customer_data")
            current_customer = front_data.duplicate(true)
            selected_item = int(current_customer.get("likes", 0))
            price_tier = 1
        panel_open = true
        panel_mode = "sale"
        panel_feedback = "顾客说：「%s」" % String(current_customer.get("quote", "先匹配需求，再考虑偏好、预算和售价。"))
        get_viewport().set_input_as_handled()

func _finish_stocking_and_start_service() -> void:
    if service_started:
        panel_open = false
        return
    if total_ready_stock() <= 0:
        panel_feedback = "还没有制作好的成品。按 C 进入制作台，选择菜品后按 Enter 制作。"
        last_result = panel_feedback
        result_clock = 4.0
        return

    service_started = true
    panel_open = false
    panel_mode = "sale"
    current_customer = {}
    replenish_clock = REPLENISH_DELAY
    last_result = "备菜完成！开始营业，第一位顾客正在从街口走向摊位。"
    result_clock = 4.0
    _spawn_customer(0, 0.0)
    queue_redraw()

func _buy_stock() -> void:
    var item: Dictionary = item_data(selected_item)
    var unit_cost: int = int(item.cost)
    var affordable := int(floor(float(cash) / float(unit_cost)))
    var per_item_space := maxi(0, MAX_ITEM_STOCK - item_total_stock(selected_item))
    var amount := mini(requested_stock_qty, mini(affordable, mini(stock_space_left(), per_item_space)))
    if amount <= 0:
        if stock_space_left() <= 0:
            panel_feedback = "原料与成品总库存已满（%d/%d）。" % [total_stock(), MAX_TOTAL_STOCK]
        elif per_item_space <= 0:
            panel_feedback = "%s 的原料+成品已达到单品上限 %d。" % [String(item.name), MAX_ITEM_STOCK]
        else:
            panel_feedback = "现金不足：%s 原料包每份 ¥%d。" % [String(item.name), unit_cost]
        return

    var total_cost := amount * unit_cost
    raw_stock[selected_item] += amount
    cash -= total_cost
    purchase_spend += total_cost
    panel_feedback = "原料进货成功：%s 原料包 ×%d，支出 ¥%d；现金剩余 ¥%d。" % [String(item.name), amount, total_cost, cash]
    last_result = panel_feedback
    result_clock = 3.0

func _start_cooking() -> void:
    if cooking_item >= 0:
        panel_feedback = "正在制作%s，还需 %.1f 秒。" % [String(item_data(cooking_item).name), maxf(0.0, cooking_time_remaining)]
        return
    if raw_stock[selected_item] <= 0:
        panel_feedback = "%s 原料不足！按 B 采购原料包。" % String(item_data(selected_item).name)
        return

    var item: Dictionary = item_data(selected_item)
    raw_stock[selected_item] -= 1
    cooking_item = selected_item
    cooking_time_total = float(item.get("prep_seconds", 2.5))
    cooking_time_remaining = cooking_time_total
    panel_feedback = "开始制作%s：%s。完成前不能直接上菜。" % [String(item.name), String(item.get("recipe", "原料包 ×1"))]
    last_result = "正在制作%s……" % String(item.name)
    result_clock = 3.0

func _update_cooking(delta: float) -> void:
    if cooking_item < 0:
        return
    cooking_time_remaining = maxf(0.0, cooking_time_remaining - delta)
    if cooking_time_remaining > 0.0:
        return

    var completed_item := cooking_item
    cooking_item = -1
    cooking_time_remaining = 0.0
    cooking_time_total = 0.0
    stock[completed_item] += 1
    cooked_today += 1
    var cooked_name := String(item_data(completed_item).name)
    panel_feedback = "制作完成：%s ×1，成品已放入可售库存。" % cooked_name
    last_result = panel_feedback
    result_clock = 3.5
    if completed_customers() >= total_customers():
        _finish_night()
    queue_redraw()

func cooking_progress() -> float:
    if cooking_item < 0 or cooking_time_total <= 0.0:
        return 0.0
    return clampf(1.0 - cooking_time_remaining / cooking_time_total, 0.0, 1.0)

func _offer_hint(item_index: int, tier: int) -> String:
    if current_customer.is_empty():
        return "先接待队首顾客。"
    if stock[item_index] <= 0:
        if raw_stock[item_index] > 0:
            return "有原料但还没做成品：按 C 打开制作台，完成后才能上菜。"
        return "成品售罄：按 B 采购原料，再按 C 制作；缺货不会消耗顾客耐心。"
    var customer: Dictionary = current_customer
    var item: Dictionary = item_data(item_index)
    var ask_price := price_for_item(item_index, tier)
    if String(item.fav) != String(customer.get("need", "")):
        return "商品不符合需求：顾客会拒绝，耐心 -1。"
    if ask_price > int(customer.get("budget", 0)):
        return "售价超过预算 ¥%d：顾客会拒绝，耐心 -1。" % int(customer.budget)
    if tier == 2 and bool(customer.get("premium_averse", false)):
        return "这位顾客比较看重价格，不接受溢价；耐心会下降。"
    if tier == 2 and item_index != int(customer.get("likes", -1)):
        return "非偏好商品不接受溢价：顾客会拒绝，耐心下降。"
    var profit := ask_price - int(item.cost)
    if item_index == int(customer.get("likes", -1)):
        return "需求匹配 + 偏好商品；预计毛利 ¥%d。" % profit
    if tier == 0:
        return "需求匹配 + 亲民价；预计毛利 ¥%d。" % profit
    return "需求匹配且在预算内；预计毛利 ¥%d。" % profit

func _serve_customer() -> void:
    if current_customer.is_empty():
        panel_feedback = "当前没有待服务顾客。"
        return
    var item: Dictionary = item_data(selected_item)
    if stock[selected_item] <= 0:
        if raw_stock[selected_item] > 0:
            panel_feedback = "%s 还有原料，但还没制作成品。按 C 打开制作台；不会扣耐心。" % String(item.name)
        else:
            panel_feedback = "%s 成品售罄！按 B 采购原料，再按 C 制作；不会扣耐心。" % String(item.name)
        return

    transaction_attempts += 1
    var customer: Dictionary = current_customer
    var asking_price := price_for_item(selected_item, price_tier)
    var category_match := String(item.fav) == String(customer.get("need", ""))
    var favorite_match := selected_item == int(customer.get("likes", -1))
    var refusal := ""
    if not category_match:
        refusal = "顾客需要%s，不想买%s" % [String(customer.get("need", "商品")), String(item.name)]
    elif price_tier == 2 and bool(customer.get("premium_averse", false)):
        refusal = "%s比较看重价格，不接受溢价" % String(customer.get("style", "顾客"))
    elif asking_price > int(customer.get("budget", 0)):
        refusal = "售价 ¥%d 超过顾客预算 ¥%d" % [asking_price, int(customer.get("budget", 0))]
    elif price_tier == 2 and not favorite_match:
        refusal = "顾客只愿意为偏好商品支付溢价"

    if not refusal.is_empty():
        _reject_offer(refusal)
        return

    stock[selected_item] -= 1
    served += 1
    cash += asking_price
    revenue_total += asking_price
    cost_of_goods_sold += int(item.cost)
    var gross_profit := asking_price - int(item.cost)

    # Track the kind of sale so the player can learn from each night.
    if favorite_match:
        preferred_item_sales += 1
    if price_tier == 0:
        discount_sales_count += 1
    elif price_tier == 2:
        premium_sales_count += 1

    # Base reputation gains preserve previous rules; personality adds a small,
    # readable bonus for the matching service style.
    var reputation_gain := 1
    if favorite_match:
        reputation_gain += 2
    if price_tier == 0:
        reputation_gain += 1
    if String(customer.get("style", "")) == "精打细算" and price_tier == 0:
        reputation_gain += 1
    if String(customer.get("style", "")) == "熟客" and favorite_match:
        reputation_gain += 1
    reputation = mini(100, reputation + reputation_gain)

    last_result = "成交！%s 买下%s，收入 ¥%d，毛利 ¥%d，口碑 +%d。" % [String(customer.name), String(item.name), asking_price, gross_profit, reputation_gain]
    if String(customer.get("style", "")) == "精打细算" and price_tier == 0:
        last_result += " 实惠价获得额外好评。"
    elif String(customer.get("style", "")) == "熟客" and favorite_match:
        last_result += " 熟客很满意。"
    result_clock = 4.0
    panel_feedback = "交易成功。库存 -1，现金 +¥%d。" % asking_price
    current_customer = {}
    panel_open = false
    _send_front_customer_away()
    _maybe_finish_night()

func _reject_offer(reason: String) -> void:
    var customer_name := String(current_customer.get("name", "顾客"))
    refused_offers_count += 1
    var patience_loss := maxi(1, int(current_customer.get("reject_patience_loss", 1)))
    var patience := maxi(0, int(current_customer.get("patience", 1)) - patience_loss)
    current_customer["patience"] = patience
    if patience <= 0:
        reputation = maxi(0, reputation - 2)
        lost_customers += 1
        last_result = "%s失去耐心后离开了（口碑 -2）。原因：%s。" % [customer_name, reason]
        result_clock = 5.0
        current_customer = {}
        panel_open = false
        _send_front_customer_away()
        _maybe_finish_night()
        return
    panel_feedback = "%s；耐心 -%d，剩余 %d/%d。换商品或降价再试。" % [reason, patience_loss, patience, int(current_customer.get("patience_max", 2))]

func _maybe_finish_night() -> void:
    if completed_customers() >= CUSTOMERS.size() and cooking_item < 0:
        _finish_night()

func _finish_night() -> void:
    if game_finished:
        return
    game_finished = true
    settlement_open = true
    panel_open = false
    current_customer = {}
    last_result = "第 %d 晚营业结束，查看每日结算。" % night
    result_clock = 999.0

func _start_next_night() -> void:
    # Carry cash, remaining inventory and reputation forward between shifts.
    night += 1
    night_start_cash = cash
    served = 0
    lost_customers = 0
    transaction_attempts = 0
    revenue_total = 0
    cost_of_goods_sold = 0
    purchase_spend = 0
    preferred_item_sales = 0
    discount_sales_count = 0
    premium_sales_count = 0
    refused_offers_count = 0
    cooked_today = 0
    game_time_minutes = 20 * 60
    game_minute_fraction = 0.0
    spawned_customer_count = 0
    replenish_clock = -1.0
    current_customer = {}
    panel_open = false
    panel_mode = "stock"
    service_started = false
    game_finished = false
    settlement_open = false
    # Clean up any last customer still walking off-screen from the previous night.
    for actor in exiting_customers:
        if is_instance_valid(actor):
            actor.queue_free()
    exiting_customers.clear()
    customer_queue.clear()
    panel_feedback = "新一晚开始了。按 B 采购原料，按 C 制作成品，制作好后按 F 开始营业。"
    last_result = "第 %d 晚准备营业：先采购原料，再手工制作菜品。" % night
    result_clock = 4.0
    queue_redraw()

func _draw() -> void:
    _draw_world()
    _draw_stall()
    _draw_street_props()

func _draw_world() -> void:
    draw_rect(Rect2(0, 0, 320, 180), Color("#243044"))
    # Grass/dirt tiles with fixed pixel-sized variation.
    for y in range(0, 180, 16):
        for x in range(0, 320, 16):
            # Convert tile coordinates explicitly to integers without implicit
            # integer-division warnings in Godot 4.7.
            var tile_x: int = floori(float(x) / 16.0)
            var tile_y: int = floori(float(y) / 16.0)
            var v: int = (tile_x * 7 + tile_y * 3) % 4
            var col := Color("#354b4b") if v == 0 else (Color("#304447") if v == 1 else Color("#2c4144"))
            draw_rect(Rect2(x, y, 15, 15), col)
            if v == 2:
                draw_rect(Rect2(x + 4, y + 5, 2, 2), Color("#425553"))
    # Walkway tiles.
    for y in range(96, 180, 16):
        for x in range(0, 320, 32):
            draw_rect(Rect2(x, y, 30, 14), Color("#67594b"))
            draw_rect(Rect2(x + 2, y + 2, 26, 1), Color("#89725a"))
    # Fence and dark upper hedge.
    draw_rect(Rect2(0, 22, 320, 12), Color("#1b2938"))
    for x in range(4, 320, 16):
        draw_rect(Rect2(x, 18, 4, 20), Color("#6b5042"))
        draw_rect(Rect2(x - 1, 18, 6, 3), Color("#a57855"))
    # Little puddles / weeds.
    draw_rect(Rect2(42, 70, 12, 3), Color("#486276"))
    draw_rect(Rect2(45, 68, 7, 2), Color("#58768a"))
    draw_rect(Rect2(38, 134, 3, 3), Color("#91a36a"))
    draw_rect(Rect2(278, 122, 4, 3), Color("#91a36a"))
    draw_rect(Rect2(27, 108, 4, 2), Color("#91a36a"))
    # Warm lamps.
    _draw_lamp(Vector2(66, 48))
    _draw_lamp(Vector2(276, 48))

func _draw_lamp(p: Vector2) -> void:
    draw_rect(Rect2(p.x - 6, p.y - 2, 12, 12), Color("#7c6448"))
    draw_rect(Rect2(p.x - 3, p.y - 12, 6, 15), Color("#b98b51"))
    draw_rect(Rect2(p.x - 6, p.y - 15, 12, 5), Color("#f7d990"))
    draw_rect(Rect2(p.x - 4, p.y - 14, 8, 3), Color("#fff0bc"))
    draw_rect(Rect2(p.x - 10, p.y - 7, 20, 18), Color("#eab96c"), false, 1.0)

func _draw_stall() -> void:
    # Small, visible prep counter at the left of the selling counter.
    draw_rect(Rect2(123, 80, 26, 9), Color("#1b252e"))
    draw_rect(Rect2(125, 77, 22, 5), Color("#6d4637"))
    draw_rect(Rect2(126, 76, 20, 3), Color("#a46a47"))
    draw_rect(Rect2(128, 72, 7, 4), Color("#d8ddd0"))
    draw_rect(Rect2(129, 73, 5, 2), Color("#8aaf96"))
    draw_rect(Rect2(137, 72, 7, 4), Color("#e8b96f"))
    draw_rect(Rect2(138, 73, 5, 2), Color("#b94d50"))
    draw_string(ThemeDB.fallback_font, Vector2(127, 70), "备菜", HORIZONTAL_ALIGNMENT_LEFT, 20, 5, Color("#fff1c8"))
    # Main stall shadow and legs.
    draw_rect(Rect2(157, 73, 94, 18), Color("#1b252e"))
    draw_rect(Rect2(165, 70, 7, 20), Color("#6d4637"))
    draw_rect(Rect2(236, 70, 7, 20), Color("#6d4637"))
    # canopy: pixel stripe awning.
    draw_rect(Rect2(154, 39, 99, 23), Color("#e8b96f"))
    for i in range(7):
        var x := 156 + i * 14
        var stripe := Color("#b94d50") if i % 2 == 0 else Color("#f1d49b")
        draw_rect(Rect2(x, 40, 12, 20), stripe)
        draw_rect(Rect2(x, 57, 12, 4), Color("#7b373f") if i % 2 == 0 else Color("#c7a06b"))
    draw_rect(Rect2(154, 60, 99, 6), Color("#52383a"))
    draw_rect(Rect2(158, 66, 91, 12), Color("#7c4c39"))
    draw_rect(Rect2(161, 67, 84, 8), Color("#a46a47"))
    # Counter products / sign.
    draw_rect(Rect2(170, 47, 17, 10), Color("#fff0be"))
    draw_rect(Rect2(172, 49, 13, 6), Color("#e5a94c"))
    draw_rect(Rect2(193, 47, 12, 10), Color("#d9e4d0"))
    draw_rect(Rect2(195, 49, 8, 6), Color("#8aaf96"))
    draw_rect(Rect2(218, 47, 18, 10), Color("#f3ddab"))
    draw_rect(Rect2(221, 49, 12, 6), Color("#d15b4f"))
    draw_rect(Rect2(182, 27, 46, 12), Color("#f4dba6"))
    draw_rect(Rect2(184, 29, 42, 8), Color("#74433a"))
    draw_string(ThemeDB.fallback_font, Vector2(188, 35), "MIDNIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("#fff1c8"))

func _draw_person(p: Vector2, coat: Color, hair: Color) -> void:
    draw_rect(Rect2(p.x - 5, p.y - 1, 10, 3), Color("#1c2732"))
    draw_rect(Rect2(p.x - 4, p.y - 11, 8, 8), Color("#e4b38f"))
    draw_rect(Rect2(p.x - 5, p.y - 12, 10, 3), hair)
    draw_rect(Rect2(p.x - 5, p.y - 5, 10, 6), coat)
    draw_rect(Rect2(p.x - 4, p.y + 1, 3, 3), Color("#26354d"))
    draw_rect(Rect2(p.x + 1, p.y + 1, 3, 3), Color("#26354d"))

func _draw_street_props() -> void:
    # Replace static pedestrian-like decorations with props; actual customers
    # should be the only non-player characters in this test lane.
    draw_rect(Rect2(43, 116, 18, 12), Color("#4b3b34"))
    draw_rect(Rect2(44, 117, 16, 2), Color("#8f6b4e"))
    draw_line(Vector2(52, 117), Vector2(52, 127), Color("#76513b"), 1.0)
    draw_rect(Rect2(271, 98, 15, 12), Color("#3e504c"))
    draw_rect(Rect2(270, 97, 17, 2), Color("#a98658"))
    draw_line(Vector2(274, 100), Vector2(283, 100), Color("#8b6e49"), 1.0)
