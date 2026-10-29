extends Node2D

signal finished_exit(actor: Node2D)

var customer_data: Dictionary = {}
var route: Array[Vector2] = []
var route_index: int = 0
var move_speed: float = 46.0
var activation_delay: float = 0.0
var has_arrived: bool = false
var exiting: bool = false
# Queue movement requests are deferred while the actor follows its entrance path.
# This prevents a queue refresh from overwriting the visible street-entry route.
var pending_slot: Vector2 = Vector2.ZERO
var has_pending_slot: bool = false
var is_walking: bool = false
var walk_clock: float = 0.0
var exit_signal_sent: bool = false
var coat_color: Color = Color("#6f91a3")
var hair_color: Color = Color("#302a3d")
var skin_color: Color = Color("#e4b38f")
var order_color: Color = Color("#d96b56")
var facing: String = "up"

func _ready() -> void:
    # Main.gd advances customer movement centrally; disable autonomous ticking
    # so every customer is updated exactly once per frame.
    set_process(false)
    set_physics_process(false)

const COAT_COLORS := [Color("#6f91a3"), Color("#8c7ba3"), Color("#bc8059"), Color("#547f70"), Color("#b85a58")]
const HAIR_COLORS := [Color("#302a3d"), Color("#4a3234"), Color("#322b28"), Color("#262b39"), Color("#5d3a2c")]
const SKIN_COLORS := [Color("#e4b38f"), Color("#d7a17e"), Color("#edc09a"), Color("#c98f70"), Color("#e8b18b")]

func setup(data: Dictionary, start: Vector2, path_points: Array, palette_index: int, delay: float = 0.0) -> void:
    customer_data = data.duplicate(true)
    position = start
    route.clear()
    for point in path_points:
        route.append(point)
    route_index = 0
    activation_delay = delay
    has_arrived = false
    exiting = false
    has_pending_slot = false
    exit_signal_sent = false
    var palette := posmod(palette_index, COAT_COLORS.size())
    coat_color = COAT_COLORS[palette]
    hair_color = HAIR_COLORS[palette]
    skin_color = SKIN_COLORS[palette]
    order_color = Color("#db765d") if String(customer_data.get("need", "热食")) == "热食" else Color("#75c4cf")
    # Use an absolute draw layer above the stall foreground.
    # The previous relative layer could leave actors obscured by scene-specific depth.
    z_as_relative = false
    z_index = 10
    visible = true
    queue_redraw()

func move_to_slot(slot: Vector2) -> void:
    if exiting:
        return
    pending_slot = slot
    has_pending_slot = true
    # Keep the active entrance route intact. Once the actor reaches the entry
    # route endpoint, it will move to the latest queue slot requested by Main.
    if not has_arrived and route_index < route.size():
        queue_redraw()
        return
    _start_move_to_pending_slot()
    queue_redraw()

func _start_move_to_pending_slot() -> void:
    if not has_pending_slot or exiting:
        return
    var destination := pending_slot
    has_pending_slot = false
    route = [destination]
    route_index = 0
    has_arrived = position.distance_to(destination) <= 1.0
    if has_arrived:
        position = destination.round()
        route_index = route.size()
        is_walking = false
    else:
        is_walking = true

func begin_exit() -> void:
    if exiting:
        return
    exiting = true
    has_arrived = false
    has_pending_slot = false
    var current_x := position.x
    route = [Vector2(current_x, 139), Vector2(300, 139), Vector2(342, 139)]
    route_index = 0
    queue_redraw()

func advance(delta: float) -> void:
    # Called from Main._process, not from this node's own process callback.
    walk_clock += delta
    if activation_delay > 0.0:
        activation_delay = maxf(0.0, activation_delay - delta)
        queue_redraw()
        return

    if route_index < route.size():
        var target: Vector2 = route[route_index]
        var difference: Vector2 = target - position
        if difference.length() <= move_speed * delta + 0.5:
            position = target.round()
            route_index += 1
            if route_index >= route.size():
                is_walking = false
                if exiting:
                    if not exit_signal_sent:
                        exit_signal_sent = true
                        finished_exit.emit(self)
                        queue_free()
                elif has_pending_slot and position.distance_to(pending_slot) > 1.0:
                    # The actor finished entering; now walk to its newest queue slot.
                    _start_move_to_pending_slot()
                else:
                    has_pending_slot = false
                    has_arrived = true
        else:
            var direction := difference.normalized()
            # Do not round the position on every frame. At high FPS, one frame
            # can move less than 0.5 logical pixels; rounding each tiny step
            # sends the actor back to the same coordinate forever. Keep the
            # fractional progress and snap only when the waypoint is reached.
            position += direction * move_speed * delta
            is_walking = true
            if absf(direction.x) > absf(direction.y):
                facing = "right" if direction.x > 0.0 else "left"
            else:
                facing = "down" if direction.y > 0.0 else "up"
    else:
        is_walking = false
        if not exiting:
            if has_pending_slot and position.distance_to(pending_slot) > 1.0:
                _start_move_to_pending_slot()
            else:
                has_pending_slot = false
                has_arrived = true
    queue_redraw()

func _draw() -> void:
    var bob := 0
    if is_walking:
        bob = int(walk_clock * 12.0) % 2
    elif not exiting and has_arrived and sin(walk_clock * 2.6) > 0.8:
        bob = 1

    # Shadow and alternating feet.
    draw_rect(Rect2(-5, -2, 10, 3), Color("#17212a"))
    var leg_shift := 0
    if is_walking:
        leg_shift = 1 if int(walk_clock * 10.0) % 2 == 0 else -1
    draw_rect(Rect2(-4, -4 + bob, 3, 4 + max(leg_shift, 0)), Color("#25334a"))
    draw_rect(Rect2(1, -4 + bob, 3, 4 + max(-leg_shift, 0)), Color("#25334a"))
    # Coat and arms.
    draw_rect(Rect2(-5, -10 + bob, 10, 7), coat_color)
    draw_rect(Rect2(-6, -9 + bob, 2, 5), coat_color.darkened(0.12))
    draw_rect(Rect2(4, -9 + bob, 2, 5), coat_color.darkened(0.12))
    # Head, hair and a tiny face that follows the facing direction.
    draw_rect(Rect2(-4, -16 + bob, 8, 7), skin_color)
    draw_rect(Rect2(-5, -17 + bob, 10, 3), hair_color)
    draw_rect(Rect2(-5, -15 + bob, 2, 3), hair_color)
    if facing == "down":
        draw_rect(Rect2(-2, -12 + bob, 1, 1), Color("#27303d"))
        draw_rect(Rect2(2, -12 + bob, 1, 1), Color("#27303d"))
    elif facing == "left":
        draw_rect(Rect2(-3, -12 + bob, 1, 1), Color("#27303d"))
    elif facing == "right":
        draw_rect(Rect2(2, -12 + bob, 1, 1), Color("#27303d"))

    # A readable order bubble tells the player which product category this
    # customer wants before opening the counter interaction.
    if has_arrived and not exiting:
        draw_rect(Rect2(-11, -29 + bob, 22, 9), Color("#fff0cb"))
        draw_rect(Rect2(-10, -28 + bob, 20, 7), Color("#fff8e8"))
        var need_label := "热食" if String(customer_data.get("need", "热食")) == "热食" else "饮品"
        draw_string(ThemeDB.fallback_font, Vector2(-10, -22 + bob), need_label, HORIZONTAL_ALIGNMENT_CENTER, 20, 5, order_color)
        draw_rect(Rect2(-2, -20 + bob, 4, 2), Color("#fff0cb"))
