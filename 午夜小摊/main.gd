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
const FARM_CROPS := [
    {"name": "稻米", "seed_name": "稻种", "seed_cost": 2, "growth_days": 3, "harvest_yield": 2, "regrow_days": 0, "color": Color("#d8c16f")},
    {"name": "蔬菜", "seed_name": "菜种", "seed_cost": 3, "growth_days": 2, "harvest_yield": 2, "regrow_days": 0, "color": Color("#74a85d")},
    {"name": "柠檬", "seed_name": "柠檬苗", "seed_cost": 4, "growth_days": 3, "harvest_yield": 2, "regrow_days": 2, "color": Color("#d9d75e")},
]
const FARM_PLOT_POSITIONS := [Vector2(49, 100), Vector2(78, 100), Vector2(107, 100), Vector2(49, 130), Vector2(78, 130), Vector2(107, 130)]
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
var raw_stock: Array[int] = [0, 0, 0] # purchased supporting ingredients: seaweed / soup base / tea base
var produce_stock: Array[int] = [0, 0, 0] # farmed crops: rice / vegetables / lemons
var produce_cost_stock: Array = [[], [], []] # FIFO unit costs for farm produce used in recipes
var cooked_produce_cost_stock: Array = [[], [], []] # crop cost attached to each finished serving
var cooking_produce_cost: float = 0.0

# Daytime cottage farm. The first three plots start with harvestable crops so the
# first night is playable; crops harvested later enter produce_stock and are
# consumed by the corresponding recipes at the stall.
var home_mode: bool = true
var farm_day: int = 1
var day_time_minutes: int = 8 * 60
var day_minute_fraction: float = 0.0
var selected_crop: int = 0
var requested_seed_qty: int = 1
var seed_stock: Array[int] = [2, 2, 2] # starter seed packets
var seed_cost_queue: Array = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
var farm_plots: Array[Dictionary] = []
var farm_feedback: String = "白天：收获成熟作物、开垦空地、播种并浇水。按 F 前往夜市。"
var cooking_item: int = -1
var cooking_time_remaining: float = 0.0
var cooking_time_total: float = 0.0
var cooked_today: int = 0
# Quality is attached to each finished serving (FIFO), so the cooking mini-game
# affects the exact dish later served rather than a global temporary score.
var quality_stock: Array = [[], [], []] # 0=普通, 1=不错, 2=完美
var cooking_timing_attempted: bool = false
var cooking_quality: int = 0
var cooking_timing_message: String = "等待火候时机"
var cooking_visual_clock: float = 0.0
var cooking_flash_timer: float = 0.0
var perfect_cooks_today: int = 0
var good_cooks_today: int = 0
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
var last_result: String = "白天收获作物，夜市按 B 采购辅料、按 C 制作；按 F 开张。"
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

func crop_data(index: int) -> Dictionary:
    return FARM_CROPS[clampi(index, 0, FARM_CROPS.size() - 1)]

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
    for amount in produce_stock:
        total += amount
    return total

func total_ready_stock() -> int:
    var total := 0
    for amount in stock:
        total += amount
    return total

func item_total_stock(index: int) -> int:
    var safe_index := clampi(index, 0, ITEMS.size() - 1)
    return stock[safe_index] + raw_stock[safe_index] + produce_stock[safe_index]

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
    # The campaign starts during daytime at the cottage. Three starter crops are
    # ready to harvest so the player can supply the first night-market recipes.
    _setup_farm()
    home_mode = true
    player.position = Vector2(160, 151)
    get_node("StallOccluder").visible = false
    # Do not spawn customers at game startup. They enter only after stocking ends.
    queue_redraw()

func _process(delta: float) -> void:
    result_clock = maxf(0.0, result_clock - delta)
    if cooking_item >= 0:
        cooking_visual_clock += delta
        cooking_flash_timer = maxf(0.0, cooking_flash_timer - delta)
        # The world-space pot has pixel steam, heat and ingredient effects.
        queue_redraw()
    # Cooking continues in real time. Closing the panel does not cancel the dish.
    if not settlement_open and not home_mode:
        _update_cooking(delta)
    # Drive customer actors from the same active loop as the game clock.
    if not home_mode:
        _update_customer_actors(delta)
        if not game_finished and service_started:
            _update_game_clock(delta)
            _update_customer_replenishment(delta)
    else:
        _update_day_clock(delta)
    queue_redraw()

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
    var safe_minutes := posmod(day_time_minutes if home_mode else game_time_minutes, 24 * 60)
    return "%02d:%02d" % [floori(float(safe_minutes) / 60.0), safe_minutes % 60]

func _update_day_clock(delta: float) -> void:
    # Daylight runs from 08:00 to 18:00; the player chooses when to leave for
    # the night market. Farming growth is resolved only when the next day begins.
    day_minute_fraction += delta * 5.0
    var minutes_to_add: int = int(day_minute_fraction)
    if minutes_to_add > 0:
        day_minute_fraction -= float(minutes_to_add)
        day_time_minutes = mini(18 * 60, day_time_minutes + minutes_to_add)

func _setup_farm() -> void:
    farm_plots.clear()
    for i in range(FARM_PLOT_POSITIONS.size()):
        var plot: Dictionary = {
            "pos": FARM_PLOT_POSITIONS[i],
            "tilled": i < 3,
            "crop": i if i < 3 else -1,
            "growth": int(FARM_CROPS[i].growth_days) if i < 3 else 0,
            "watered": false,
            "plant_cost": 0.0,
        }
        farm_plots.append(plot)

func _nearest_farm_plot() -> int:
    var best_index: int = -1
    var best_distance: float = 19.0
    for i in range(farm_plots.size()):
        var plot: Dictionary = farm_plots[i]
        var distance: float = player.position.distance_to(plot.pos)
        if distance <= best_distance:
            best_distance = distance
            best_index = i
    return best_index

func _interact_farm_plot() -> void:
    var plot_index: int = _nearest_farm_plot()
    if plot_index < 0:
        farm_feedback = "走到一块田地旁边（约 19 像素内）再按 E。"
        result_clock = 3.0
        queue_redraw()
        return

    var plot: Dictionary = farm_plots[plot_index]
    var crop_index: int = int(plot.crop)
    if crop_index >= 0:
        var crop: Dictionary = FARM_CROPS[crop_index]
        if int(plot.growth) >= int(crop.growth_days):
            _harvest_farm_plot(plot_index)
            return
        if not bool(plot.watered):
            plot.watered = true
            farm_plots[plot_index] = plot
            farm_feedback = "已为%s浇水。明天早晨结算时会推进 1 天生长。" % String(crop.name)
        else:
            farm_feedback = "%s今天已经浇过水了。明天进入小屋时查看生长变化。" % String(crop.name)
    elif not bool(plot.tilled):
        plot.tilled = true
        farm_plots[plot_index] = plot
        farm_feedback = "土地已开垦。再次靠近并按 E，即可播种当前选择的%s。" % String(FARM_CROPS[selected_crop].name)
    else:
        if seed_stock[selected_crop] <= 0:
            farm_feedback = "%s不足。按 B 打开种子箱购买种子。" % String(FARM_CROPS[selected_crop].seed_name)
        else:
            seed_stock[selected_crop] -= 1
            var seed_cost: float = 0.0
            if seed_cost_queue[selected_crop].size() > 0:
                seed_cost = float(seed_cost_queue[selected_crop].pop_front())
            plot.crop = selected_crop
            plot.growth = 0
            plot.watered = false
            plot.plant_cost = seed_cost
            plot.tilled = true
            farm_plots[plot_index] = plot
            farm_feedback = "播种完成：%s。再按 E 浇水；每天浇水，作物才会生长。" % String(FARM_CROPS[selected_crop].name)
    last_result = farm_feedback
    result_clock = 3.5
    queue_redraw()

func _harvest_farm_plot(plot_index: int) -> void:
    var plot: Dictionary = farm_plots[plot_index]
    var crop_index: int = int(plot.crop)
    if crop_index < 0:
        return
    var crop: Dictionary = FARM_CROPS[crop_index]
    var yield_count: int = int(crop.harvest_yield)
    var amount: int = yield_count
    if stock_space_left() < yield_count:
        farm_feedback = "收获需要 %d 格库存，目前只剩 %d 格。先去夜市消耗作物或成品，再回来收获。" % [yield_count, stock_space_left()]
        last_result = farm_feedback
        result_clock = 3.5
        queue_redraw()
        return

    var planted_cost: float = float(plot.get("plant_cost", 0.0))
    var unit_cost: float = planted_cost / float(yield_count)
    produce_stock[crop_index] += amount
    for unit in range(amount):
        produce_cost_stock[crop_index].append(unit_cost)

    if int(crop.get("regrow_days", 0)) > 0:
        # Lemon plants remain in the soil and can be harvested again after a
        # short watered regrowth period, like a perennial crop.
        plot.growth = maxi(0, int(crop.growth_days) - int(crop.regrow_days))
        plot.watered = false
        plot.plant_cost = 0.0
        farm_feedback = "收获%s ×%d！植株保留下来，继续浇水，约 %d 天后可再次收获。" % [String(crop.name), amount, int(crop.regrow_days)]
    else:
        plot.crop = -1
        plot.growth = 0
        plot.watered = false
        plot.plant_cost = 0.0
        farm_feedback = "收获%s ×%d！已放入小摊原料库存；这块地仍可再次播种。" % [String(crop.name), amount]
    farm_plots[plot_index] = plot
    last_result = farm_feedback
    result_clock = 4.0
    queue_redraw()

func _advance_farm_day() -> void:
    for i in range(farm_plots.size()):
        var plot: Dictionary = farm_plots[i]
        var crop_index: int = int(plot.crop)
        if crop_index >= 0 and int(plot.growth) < int(FARM_CROPS[crop_index].growth_days):
            if bool(plot.watered):
                plot.growth = mini(int(FARM_CROPS[crop_index].growth_days), int(plot.growth) + 1)
        plot.watered = false
        farm_plots[i] = plot
    farm_feedback = "第 %d 天：浇过水的作物已生长；成熟作物可以收获。E 操作土地。" % farm_day

func _buy_seeds() -> void:
    var crop: Dictionary = FARM_CROPS[selected_crop]
    var unit_cost: int = int(crop.seed_cost)
    var affordable: int = int(floor(float(cash) / float(unit_cost)))
    var capacity: int = maxi(0, 9 - seed_stock[selected_crop])
    var amount: int = mini(requested_seed_qty, mini(affordable, capacity))
    if amount <= 0:
        farm_feedback = "无法购买：可能是现金不足或该种子已达到 9 包上限。"
    else:
        var total_cost: int = amount * unit_cost
        cash -= total_cost
        purchase_spend += total_cost
        for unit in range(amount):
            seed_cost_queue[selected_crop].append(float(unit_cost))
        seed_stock[selected_crop] += amount
        farm_feedback = "购买%s ×%d，支出 ¥%d。" % [String(crop.seed_name), amount, total_cost]
    last_result = farm_feedback
    result_clock = 3.0
    queue_redraw()

func _begin_night_market() -> void:
    home_mode = false
    panel_open = false
    panel_mode = "stock"
    player.position = Vector2(92, 122)
    game_time_minutes = 20 * 60
    game_minute_fraction = 0.0
    service_started = false
    game_finished = false
    settlement_open = false
    current_customer = {}
    farm_feedback = ""
    last_result = "第 %d 晚：种植收获、采购辅料和成品共用库存。按 B 采购辅料，按 C 备菜。" % night
    result_clock = 4.0
    get_node("StallOccluder").visible = true
    queue_redraw()

func _return_to_home_for_farming() -> void:
    if service_started or spawned_customer_count > 0 or not current_customer.is_empty() or cooking_item >= 0:
        return
    home_mode = true
    panel_open = false
    settlement_open = false
    player.position = Vector2(160, 151)
    day_time_minutes = 8 * 60
    day_minute_fraction = 0.0
    get_node("StallOccluder").visible = false
    farm_feedback = "返回小屋。按 E 收获、浇水或播种；按 F 可再次前往夜市，T 可睡到明天。"
    last_result = farm_feedback
    result_clock = 4.0
    queue_redraw()

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
            _start_next_day()
        get_viewport().set_input_as_handled()
        return

    # Daytime cottage controls are handled separately from night-market panels.
    if home_mode:
        if panel_open:
            if key.keycode == KEY_ESCAPE or key.keycode == KEY_B:
                panel_open = false
                farm_feedback = "种子箱已关闭。1/2/3 选种，E 操作土地，F 前往夜市。"
            elif key.keycode == KEY_1:
                selected_crop = 0
            elif key.keycode == KEY_2:
                selected_crop = 1
            elif key.keycode == KEY_3:
                selected_crop = 2
            elif key.keycode == KEY_LEFT:
                requested_seed_qty = maxi(1, requested_seed_qty - 1)
            elif key.keycode == KEY_RIGHT:
                requested_seed_qty = mini(5, requested_seed_qty + 1)
            elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
                _buy_seeds()
            get_viewport().set_input_as_handled()
            queue_redraw()
            return

        if key.keycode == KEY_1:
            selected_crop = 0
            farm_feedback = "已选择稻种。靠近空地按 E 开垦或播种。"
        elif key.keycode == KEY_2:
            selected_crop = 1
            farm_feedback = "已选择菜种。靠近空地按 E 开垦或播种。"
        elif key.keycode == KEY_3:
            selected_crop = 2
            farm_feedback = "已选择柠檬苗。成熟后可反复收获。"
        elif key.keycode == KEY_E:
            _interact_farm_plot()
        elif key.keycode == KEY_B:
            panel_open = true
            panel_mode = "seeds"
            requested_seed_qty = 1
            farm_feedback = "购买种子后，选择空地按 E 开垦，再按 E 播种。"
        elif key.keycode == KEY_F:
            _begin_night_market()
        elif key.keycode == KEY_T:
            farm_day += 1
            _advance_farm_day()
            day_time_minutes = 8 * 60
            day_minute_fraction = 0.0
            farm_feedback = "睡到第 %d 天。只有前一天浇过水的作物会生长。" % farm_day
            last_result = farm_feedback
            result_clock = 4.0
        get_viewport().set_input_as_handled()
        queue_redraw()
        return

    if panel_open:
        if key.keycode == KEY_H and not service_started and spawned_customer_count == 0 and current_customer.is_empty() and cooking_item < 0:
            _return_to_home_for_farming()
            get_viewport().set_input_as_handled()
            return
        if key.keycode == KEY_ESCAPE:
            if not current_customer.is_empty() and panel_mode != "sale":
                panel_mode = "sale"
                panel_feedback = "继续为 %s 选商品和价格。" % String(current_customer.get("name", "顾客"))
            else:
                panel_open = false
                if not service_started:
                    last_result = "准备阶段：B 采购辅料，C 制作成品，准备好后按 F 开张。"
                    result_clock = 4.0
        elif panel_mode == "stock":
            if key.keycode == KEY_C:
                panel_mode = "prep"
                panel_feedback = "选择菜品后按 Enter 开始制作；必须同时有自种作物和采购辅料。"
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
                    panel_feedback = "选择辅料数量，按 Enter 采购；C 可返回制作台。"
            elif key.keycode == KEY_F and current_customer.is_empty() and not service_started:
                _finish_stocking_and_start_service()
            elif key.keycode == KEY_1:
                selected_item = 0
            elif key.keycode == KEY_2:
                selected_item = 1
            elif key.keycode == KEY_3:
                selected_item = 2
            elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
                if cooking_item >= 0:
                    panel_feedback = "正在制作%s；请在火候指针进入目标区时按 SPACE。" % String(item_data(cooking_item).name)
                else:
                    _start_cooking()
            elif key.keycode == KEY_SPACE:
                if cooking_item >= 0:
                    _attempt_cooking_timing()
                else:
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

    if key.keycode == KEY_H and not service_started and spawned_customer_count == 0 and current_customer.is_empty() and cooking_item < 0:
        _return_to_home_for_farming()
        get_viewport().set_input_as_handled()
        return

    if key.keycode == KEY_B and _near_stall():
        panel_open = true
        panel_mode = "stock"
        requested_stock_qty = 1
        panel_feedback = "采购辅料；按 C 制作成品，备好后按 F 开张。"
        get_viewport().set_input_as_handled()
        return

    if key.keycode == KEY_C and _near_prep_station():
        panel_open = true
        panel_mode = "prep"
        panel_feedback = "每份自种作物 + 一份辅料可制作一份成品；按 Enter 开始制作。"
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
            last_result = "准备阶段：按 B 采购辅料，按 C 制作；至少制作一份成品后按 F 开张。"
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
            panel_feedback = "作物、辅料与成品总库存已满（%d/%d）。" % [total_stock(), MAX_TOTAL_STOCK]
        elif per_item_space <= 0:
            panel_feedback = "%s 的作物、辅料与成品已达到单品上限 %d。" % [String(item.name), MAX_ITEM_STOCK]
        else:
            panel_feedback = "现金不足：%s 辅料包每份 ¥%d。" % [String(item.name), unit_cost]
        return

    var total_cost := amount * unit_cost
    raw_stock[selected_item] += amount
    cash -= total_cost
    purchase_spend += total_cost
    panel_feedback = "辅料进货成功：%s 辅料包 ×%d，支出 ¥%d；现金剩余 ¥%d。" % [String(item.name), amount, total_cost, cash]
    last_result = panel_feedback
    result_clock = 3.0

func _start_cooking() -> void:
    if cooking_item >= 0:
        panel_feedback = "正在制作%s，还需 %.1f 秒。制作中按 SPACE 把握火候。" % [String(item_data(cooking_item).name), maxf(0.0, cooking_time_remaining)]
        return
    if produce_stock[selected_item] <= 0:
        panel_feedback = "%s自种原料不足！白天回小屋种植并收获后，才能制作这道菜。" % String(FARM_CROPS[selected_item].name)
        return
    if raw_stock[selected_item] <= 0:
        panel_feedback = "%s辅料不足！按 B 采购辅料包。" % String(item_data(selected_item).name)
        return

    var item: Dictionary = item_data(selected_item)
    raw_stock[selected_item] -= 1
    produce_stock[selected_item] -= 1
    cooking_produce_cost = float(produce_cost_stock[selected_item].pop_front()) if produce_cost_stock[selected_item].size() > 0 else 0.0
    cooking_item = selected_item
    cooking_time_total = float(item.get("prep_seconds", 2.5))
    cooking_time_remaining = cooking_time_total
    cooking_timing_attempted = false
    cooking_quality = 0
    cooking_timing_message = "指针进入金色区域时按 SPACE；绿色区域也能获得不错火候。"
    cooking_visual_clock = 0.0
    cooking_flash_timer = 0.0
    panel_feedback = "开始制作%s：%s。准备在合适时机按 SPACE。" % [String(item.name), String(item.get("recipe", "自种作物 ×1 + 辅料 ×1"))]
    last_result = "正在制作%s……把握火候可提升成品口碑。" % String(item.name)
    result_clock = 3.0
    queue_redraw()

func _attempt_cooking_timing() -> void:
    if cooking_item < 0:
        panel_feedback = "目前没有正在制作的菜品。"
        return
    if cooking_timing_attempted:
        panel_feedback = "这份菜的火候已经判定：%s。等待制作完成即可。" % cooking_quality_label(cooking_quality)
        return

    cooking_timing_attempted = true
    var progress := cooking_progress()
    var distance := absf(progress - 0.62)
    if distance <= 0.045:
        cooking_quality = 2
        cooking_timing_message = "完美火候！这份菜出售后额外获得口碑 +2。"
        panel_feedback = cooking_timing_message
    elif distance <= 0.14:
        cooking_quality = 1
        cooking_timing_message = "火候不错！这份菜出售后额外获得口碑 +1。"
        panel_feedback = cooking_timing_message
    else:
        cooking_quality = 0
        cooking_timing_message = "火候普通；仍可正常出售，但没有额外口碑加成。"
        panel_feedback = cooking_timing_message
    cooking_flash_timer = 0.6
    last_result = cooking_timing_message
    result_clock = 2.5
    queue_redraw()

func cooking_quality_label(grade: int) -> String:
    if grade >= 2:
        return "完美"
    if grade == 1:
        return "不错"
    return "普通"

func _update_cooking(delta: float) -> void:
    if cooking_item < 0:
        return
    cooking_time_remaining = maxf(0.0, cooking_time_remaining - delta)
    if cooking_time_remaining > 0.0:
        return

    var completed_item := cooking_item
    var completed_quality := cooking_quality if cooking_timing_attempted else 0
    cooking_item = -1
    cooking_time_remaining = 0.0
    cooking_time_total = 0.0
    stock[completed_item] += 1
    quality_stock[completed_item].append(completed_quality)
    cooked_produce_cost_stock[completed_item].append(cooking_produce_cost)
    cooking_produce_cost = 0.0
    cooked_today += 1
    if completed_quality >= 2:
        perfect_cooks_today += 1
    elif completed_quality == 1:
        good_cooks_today += 1
    var cooked_name := String(item_data(completed_item).name)
    var grade_name := cooking_quality_label(completed_quality)
    panel_feedback = "制作完成：%s ×1，火候%s，成品已入库。" % [cooked_name, grade_name]
    last_result = panel_feedback
    result_clock = 3.5
    cooking_timing_attempted = false
    cooking_quality = 0
    cooking_visual_clock = 0.0
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
        if raw_stock[item_index] > 0 and produce_stock[item_index] > 0:
            return "辅料与自种原料齐全：按 C 制作成品后才能上菜。"
        if produce_stock[item_index] <= 0:
            return "自种原料不足：白天回小屋收获%s；缺货不会消耗顾客耐心。" % String(FARM_CROPS[item_index].name)
        return "辅料不足：按 B 采购辅料，再按 C 制作；缺货不会消耗顾客耐心。"
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
        if produce_stock[selected_item] <= 0:
            panel_feedback = "%s自种原料不足；白天回小屋种植或收获。不会扣耐心。" % String(FARM_CROPS[selected_item].name)
        elif raw_stock[selected_item] <= 0:
            panel_feedback = "%s辅料不足；按 B 采购辅料，再按 C 制作。不会扣耐心。" % String(item.name)
        else:
            panel_feedback = "%s有原料但还没制作成品。按 C 打开备菜台；不会扣耐心。" % String(item.name)
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

    var served_quality := 0
    if quality_stock[selected_item].size() > 0:
        served_quality = int(quality_stock[selected_item].pop_front())
    stock[selected_item] -= 1
    var farm_crop_cost: float = 0.0
    if cooked_produce_cost_stock[selected_item].size() > 0:
        farm_crop_cost = float(cooked_produce_cost_stock[selected_item].pop_front())
    served += 1
    cash += asking_price
    revenue_total += asking_price
    var dish_cost: int = int(item.cost) + int(round(farm_crop_cost))
    cost_of_goods_sold += dish_cost
    var gross_profit := asking_price - dish_cost

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
    var cook_quality_bonus := 0
    if served_quality >= 2:
        cook_quality_bonus = 2
    elif served_quality == 1:
        cook_quality_bonus = 1
    reputation_gain += cook_quality_bonus
    reputation = mini(100, reputation + reputation_gain)

    last_result = "成交！%s 买下%s，收入 ¥%d，毛利 ¥%d，口碑 +%d。" % [String(customer.name), String(item.name), asking_price, gross_profit, reputation_gain]
    if served_quality >= 2:
        last_result += " 完美火候，额外口碑 +2。"
    elif served_quality == 1:
        last_result += " 火候不错，额外口碑 +1。"
    else:
        last_result += " 火候普通。"
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

func _start_next_day() -> void:
    # Advance the farm only at dawn, based on whether each planted crop was
    # watered during the previous daytime session.
    farm_day += 1
    night += 1
    _advance_farm_day()

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
    perfect_cooks_today = 0
    good_cooks_today = 0
    game_time_minutes = 20 * 60
    game_minute_fraction = 0.0
    day_time_minutes = 8 * 60
    day_minute_fraction = 0.0
    spawned_customer_count = 0
    replenish_clock = -1.0
    current_customer = {}
    panel_open = false
    panel_mode = "seeds"
    requested_seed_qty = 1
    service_started = false
    game_finished = false
    settlement_open = false
    home_mode = true

    for actor in customer_queue:
        if is_instance_valid(actor):
            actor.queue_free()
    for actor in exiting_customers:
        if is_instance_valid(actor):
            actor.queue_free()
    exiting_customers.clear()
    customer_queue.clear()

    player.position = Vector2(160, 151)
    get_node("StallOccluder").visible = false
    farm_feedback = "第 %d 天：收获成熟作物，给需要生长的田地浇水，再按 F 前往夜市。" % farm_day
    panel_feedback = ""
    last_result = farm_feedback
    result_clock = 5.0
    queue_redraw()

func _draw() -> void:
    if home_mode:
        _draw_home_world()
    else:
        _draw_world()
        _draw_stall()
        _draw_street_props()

func _draw_home_world() -> void:
    draw_rect(Rect2(0, 0, 320, 180), Color("#6b8a55"))
    for y in range(0, 180, 16):
        for x in range(0, 320, 16):
            var tile_x: int = floori(float(x) / 16.0)
            var tile_y: int = floori(float(y) / 16.0)
            var variation: int = (tile_x * 5 + tile_y * 3) % 4
            var grass_color: Color = Color("#83a967") if variation == 0 else (Color("#789d60") if variation == 1 else Color("#73965a"))
            draw_rect(Rect2(x, y, 15, 15), grass_color)
            if variation == 2:
                draw_rect(Rect2(x + 4, y + 5, 2, 2), Color("#a0b879"))
            elif variation == 1:
                draw_rect(Rect2(x + 10, y + 4, 1, 3), Color("#90af6b"))
                draw_rect(Rect2(x + 11, y + 6, 2, 1), Color("#5e8249"))
            else:
                draw_rect(Rect2(x + 3, y + 11, 2, 1), Color("#5d7e48"))
    # Small, deliberately sparse flower/grass clusters add texture without
    # overlapping interactive crop beds or the path to the cottage.
    for flower in [Vector2(18, 48), Vector2(31, 76), Vector2(145, 51), Vector2(183, 82), Vector2(190, 145), Vector2(27, 158), Vector2(300, 154)]:
        draw_rect(Rect2(flower.x, flower.y, 2, 4), Color("#496f42"))
        draw_rect(Rect2(flower.x - 2, flower.y, 2, 2), Color("#e7c8a4"))
        draw_rect(Rect2(flower.x + 2, flower.y - 1, 2, 2), Color("#f2d77b"))
        draw_rect(Rect2(flower.x, flower.y - 2, 2, 2), Color("#f2e5c4"))
    # A pale stone path connects the cottage door to the lower edge of the map.
    for y in range(96, 180, 16):
        draw_rect(Rect2(238, y, 28, 14), Color("#c4b99b"))
        draw_rect(Rect2(241, y + 2, 22, 1), Color("#ded3b6"))
    # Fence and cottage.
    draw_rect(Rect2(0, 22, 320, 5), Color("#684c36"))
    for x in range(4, 320, 16):
        draw_rect(Rect2(x, 18, 3, 12), Color("#956b45"))
    # Cottage shadow, roof rim and layered brickwork.
    draw_rect(Rect2(207, 84, 102, 11), Color("#3c5138"))
    draw_rect(Rect2(211, 43, 94, 49), Color("#e4d1a3"))
    draw_rect(Rect2(211, 43, 94, 3), Color("#f4e3bb"))
    draw_rect(Rect2(206, 38, 104, 13), Color("#774a3a"))
    draw_rect(Rect2(208, 39, 100, 2), Color("#9a6546"))
    draw_rect(Rect2(211, 34, 94, 10), Color("#a65b49"))
    for roof_x in range(216, 302, 12):
        draw_rect(Rect2(roof_x, 36, 2, 6), Color("#c8785a"))
    draw_rect(Rect2(219, 52, 78, 33), Color("#c9ae7d"))
    draw_rect(Rect2(219, 52, 78, 2), Color("#e6d19c"))
    draw_rect(Rect2(219, 83, 78, 2), Color("#a78a5e"))
    draw_rect(Rect2(250, 64, 18, 28), Color("#4b342b"))
    draw_rect(Rect2(253, 66, 12, 24), Color("#896044"))
    draw_rect(Rect2(260, 77, 2, 2), Color("#f2d382"))
    draw_rect(Rect2(222, 53, 14, 13), Color("#2b4d57"))
    draw_rect(Rect2(224, 55, 10, 9), Color("#91c7c7"))
    draw_rect(Rect2(279, 53, 14, 13), Color("#2b4d57"))
    draw_rect(Rect2(281, 55, 10, 9), Color("#91c7c7"))
    draw_string(ThemeDB.fallback_font, Vector2(220, 31), "小屋", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("#fff1c8"))
    # Seed box next to the porch.
    draw_rect(Rect2(275, 98, 17, 12), Color("#704b31"))
    draw_rect(Rect2(277, 100, 13, 8), Color("#b5854f"))
    draw_rect(Rect2(281, 96, 5, 3), Color("#4f6d42"))
    draw_string(ThemeDB.fallback_font, Vector2(272, 117), "种子箱 B", HORIZONTAL_ALIGNMENT_LEFT, 44, 5, Color("#fff1c8"))
    # Garden plots.
    for i in range(farm_plots.size()):
        _draw_farm_plot(i)
    # Farm tools and a small water bucket.
    draw_rect(Rect2(150, 119, 12, 8), Color("#557c87"))
    draw_rect(Rect2(151, 117, 10, 2), Color("#9ccbd0"))
    draw_line(Vector2(166, 115), Vector2(172, 128), Color("#754d32"), 2.0)
    draw_rect(Rect2(164, 113, 5, 3), Color("#b4b6aa"))

func _draw_farm_plot(plot_index: int) -> void:
    var plot: Dictionary = farm_plots[plot_index]
    var p: Vector2 = plot.pos
    var rect := Rect2(p.x - 10, p.y - 8, 20, 16)
    # Soft ground shadow and clean borders make each farm tile readable at scale.
    draw_rect(Rect2(rect.position.x - 1, rect.position.y + 1, 22, 17), Color("#3e5b36", 0.45))
    if not bool(plot.tilled):
        draw_rect(rect, Color("#5b8049"))
        draw_rect(Rect2(rect.position.x, rect.position.y, 20, 2), Color("#93b76c"))
        draw_rect(Rect2(rect.position.x + 1, rect.position.y + 1, 18, 1), Color("#7eaa5e"))
        draw_rect(Rect2(rect.position.x + 2, rect.position.y + 4, 3, 2), Color("#b0c57a"))
        draw_rect(Rect2(rect.position.x + 15, rect.position.y + 11, 2, 2), Color("#6c954c"))
        return

    var watered: bool = bool(plot.watered)
    draw_rect(rect, Color("#49382c") if not watered else Color("#3a3028"))
    draw_rect(Rect2(rect.position.x, rect.position.y, 20, 1), Color("#886447") if not watered else Color("#567783"))
    draw_rect(Rect2(rect.position.x, rect.position.y + 15, 20, 1), Color("#322820"))
    for row in range(3):
        draw_line(Vector2(p.x - 8, p.y - 5 + row * 5), Vector2(p.x + 8, p.y - 5 + row * 5), Color("#7e5940") if not watered else Color("#63808a"), 1.0)
    var crop_index: int = int(plot.crop)
    if crop_index >= 0:
        var crop: Dictionary = FARM_CROPS[crop_index]
        var grown: int = int(plot.growth)
        var maturity: int = int(crop.growth_days)
        if grown >= maturity:
            if crop_index == 0:
                draw_rect(Rect2(p.x - 1, p.y - 13, 2, 12), Color("#698449"))
                draw_rect(Rect2(p.x - 5, p.y - 11, 4, 3), Color("#d8c16f"))
                draw_rect(Rect2(p.x + 1, p.y - 15, 4, 4), Color("#e3cf82"))
                draw_rect(Rect2(p.x + 2, p.y - 9, 4, 3), Color("#d8c16f"))
            elif crop_index == 1:
                draw_rect(Rect2(p.x - 1, p.y - 12, 2, 10), Color("#356c42"))
                draw_rect(Rect2(p.x - 6, p.y - 10, 5, 4), Color("#5f9b52"))
                draw_rect(Rect2(p.x + 1, p.y - 13, 6, 4), Color("#7cb65d"))
                draw_rect(Rect2(p.x - 4, p.y - 5, 5, 3), Color("#91c86a"))
            else:
                draw_rect(Rect2(p.x - 1, p.y - 12, 2, 10), Color("#3f7547"))
                draw_rect(Rect2(p.x - 6, p.y - 13, 5, 5), Color("#d8d74f"))
                draw_rect(Rect2(p.x + 2, p.y - 15, 5, 5), Color("#e6df64"))
                draw_rect(Rect2(p.x + 1, p.y - 7, 5, 4), Color("#c8c64d"))
            draw_rect(Rect2(p.x - 8, p.y - 18, 16, 5), Color("#fff0c8"))
            draw_string(ThemeDB.fallback_font, Vector2(p.x - 7, p.y - 14), "收", HORIZONTAL_ALIGNMENT_LEFT, 14, 5, Color("#7a4934"))
        else:
            draw_rect(Rect2(p.x - 1, p.y - 6, 2, 5), Color("#4f8a4a"))
            draw_rect(Rect2(p.x - 4, p.y - 7, 3, 2), Color("#79ae5c"))
            draw_rect(Rect2(p.x + 1, p.y - 9, 3, 2), Color("#8dbc67"))
            if watered:
                draw_rect(Rect2(p.x + 6, p.y + 2, 2, 2), Color("#77c4d2"))
                draw_rect(Rect2(p.x + 5, p.y + 1, 1, 1), Color("#d1f4f4"))
            draw_string(ThemeDB.fallback_font, Vector2(p.x - 9, p.y + 6), "%d/%d" % [grown, maturity], HORIZONTAL_ALIGNMENT_LEFT, 18, 4, Color("#f2dfb6"))
    elif bool(plot.tilled):
        draw_rect(Rect2(p.x - 2, p.y - 3, 4, 2), Color("#a67b52"))

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
            draw_rect(Rect2(x, y, 15, 1), Color("#435b58", 0.55))
            draw_rect(Rect2(x, y + 14, 15, 1), Color("#20363b", 0.55))
            if v == 2:
                draw_rect(Rect2(x + 4, y + 5, 2, 2), Color("#425553"))
                draw_rect(Rect2(x + 11, y + 10, 2, 1), Color("#22393d"))
            elif v == 1:
                draw_rect(Rect2(x + 8, y + 3, 2, 1), Color("#3e5551"))
    # Walkway tiles.
    for y in range(96, 180, 16):
        for x in range(0, 320, 32):
            draw_rect(Rect2(x, y, 30, 14), Color("#67594b"))
            draw_rect(Rect2(x, y, 30, 1), Color("#8f7860"))
            draw_rect(Rect2(x + 2, y + 2, 26, 1), Color("#89725a"))
            draw_rect(Rect2(x + 3, y + 7, 8, 1), Color("#5b4c41"))
            draw_rect(Rect2(x + 18, y + 10, 6, 1), Color("#76624f"))
            draw_rect(Rect2(x, y + 13, 30, 1), Color("#483f38"))
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
    # Stepped translucent glow: crisp pixel-art lighting without a blurry filter.
    draw_rect(Rect2(p.x - 14, p.y - 18, 28, 26), Color("#eab96c", 0.045))
    draw_rect(Rect2(p.x - 10, p.y - 16, 20, 22), Color("#eab96c", 0.075))
    draw_rect(Rect2(p.x - 7, p.y - 15, 14, 18), Color("#f2c979", 0.09))
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
    draw_rect(Rect2(127, 76, 18, 1), Color("#d39a61"))
    draw_rect(Rect2(128, 79, 15, 1), Color("#7f5138"))
    draw_string(ThemeDB.fallback_font, Vector2(121, 70), "备菜", HORIZONTAL_ALIGNMENT_LEFT, 20, 5, Color("#fff1c8"))
    _draw_cooking_pot()
    # Main stall shadow and legs.
    draw_rect(Rect2(157, 73, 94, 18), Color("#1b252e"))
    draw_rect(Rect2(165, 70, 7, 20), Color("#6d4637"))
    draw_rect(Rect2(236, 70, 7, 20), Color("#6d4637"))
    # canopy: pixel stripe awning.
    draw_rect(Rect2(153, 38, 101, 25), Color("#f3d49d"))
    draw_rect(Rect2(154, 39, 99, 23), Color("#e8b96f"))
    draw_rect(Rect2(154, 39, 99, 2), Color("#ffe5af"))
    for i in range(7):
        var x := 156 + i * 14
        var stripe := Color("#b94d50") if i % 2 == 0 else Color("#f1d49b")
        draw_rect(Rect2(x, 40, 12, 20), stripe)
        draw_rect(Rect2(x, 40, 1, 17), Color("#fff0c3", 0.5))
        draw_rect(Rect2(x + 10, 40, 2, 17), Color("#46353b", 0.18))
        draw_rect(Rect2(x, 57, 12, 4), Color("#7b373f") if i % 2 == 0 else Color("#c7a06b"))
    draw_rect(Rect2(154, 60, 99, 6), Color("#52383a"))
    draw_rect(Rect2(154, 60, 99, 1), Color("#75504a"))
    draw_rect(Rect2(158, 66, 91, 12), Color("#7c4c39"))
    draw_rect(Rect2(161, 67, 84, 8), Color("#a46a47"))
    draw_rect(Rect2(163, 68, 80, 1), Color("#c18458"))
    for grain_x in [169, 181, 196, 210, 228, 238]:
        draw_rect(Rect2(grain_x, 72, 5, 1), Color("#8a553d", 0.8))
    # Counter products / sign.
    draw_rect(Rect2(169, 46, 19, 12), Color("#806148"))
    draw_rect(Rect2(170, 47, 17, 10), Color("#fff0be"))
    draw_rect(Rect2(172, 48, 13, 1), Color("#fff8db"))
    draw_rect(Rect2(172, 49, 13, 6), Color("#e5a94c"))
    draw_rect(Rect2(174, 50, 8, 1), Color("#f5cf79"))
    draw_rect(Rect2(192, 46, 14, 12), Color("#806148"))
    draw_rect(Rect2(193, 47, 12, 10), Color("#d9e4d0"))
    draw_rect(Rect2(195, 48, 8, 1), Color("#eff7dc"))
    draw_rect(Rect2(195, 49, 8, 6), Color("#8aaf96"))
    draw_rect(Rect2(217, 46, 20, 12), Color("#806148"))
    draw_rect(Rect2(218, 47, 18, 10), Color("#f3ddab"))
    draw_rect(Rect2(221, 48, 12, 1), Color("#fff2d1"))
    draw_rect(Rect2(221, 49, 12, 6), Color("#d15b4f"))
    draw_rect(Rect2(182, 27, 46, 12), Color("#f4dba6"))
    draw_rect(Rect2(184, 29, 42, 8), Color("#74433a"))
    draw_string(ThemeDB.fallback_font, Vector2(188, 35), "MIDNIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("#fff1c8"))

func _draw_cooking_pot() -> void:
    # Pixel-art wok/pot sits on the prep counter. Contents, heat and steam animate
    # while cooking; the small flash makes a timing input visibly register.
    draw_rect(Rect2(134, 75, 9, 2), Color("#8b9696")) # handle
    draw_rect(Rect2(130, 74, 7, 2), Color("#a5b2ad")) # rim
    draw_rect(Rect2(131, 75, 6, 4), Color("#26333a")) # pot body
    draw_rect(Rect2(132, 76, 4, 2), Color("#626e68"))
    if cooking_item >= 0:
        var contents_color := Color("#d89b4c")
        if cooking_item == 1:
            contents_color = Color("#d7c28c")
        elif cooking_item == 2:
            contents_color = Color("#8ebc8b")
        var wobble := int(sin(cooking_visual_clock * 17.0))
        draw_rect(Rect2(132 + wobble, 76, 4, 2), contents_color)
        draw_rect(Rect2(131, 80, 2, 2), Color("#e7a14b"))
        draw_rect(Rect2(135, 80, 2, 2), Color("#d85c45") if int(cooking_visual_clock * 8.0) % 2 == 0 else Color("#f2c16a"))
        for i in range(3):
            var phase := cooking_visual_clock * 5.0 + float(i) * 2.1
            var drift := int(sin(phase) * 1.5)
            var rise := int(fposmod(cooking_visual_clock * 6.0 + float(i) * 2.0, 7.0))
            draw_rect(Rect2(132 + i * 2 + drift, 72 - rise, 1, 2), Color("#d7e8db"))
        if cooking_flash_timer > 0.0:
            var flash_color := Color("#ffe08c") if cooking_quality >= 2 else (Color("#aee4bd") if cooking_quality == 1 else Color("#e3a28b"))
            draw_rect(Rect2(128, 72, 2, 2), flash_color)
            draw_rect(Rect2(139, 71, 2, 2), flash_color)
    else:
        draw_rect(Rect2(132, 76, 4, 2), Color("#8aaf96"))

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
