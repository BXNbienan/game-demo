extends CharacterBody2D

@export var speed: float = 58.0

var facing_name: String = "down"
var is_walking: bool = false
var idle_clock: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
    _build_sprite_frames()
    sprite.position = Vector2(0, -10) # Keep the sprite's feet at the body origin.
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _update_animation()

func _physics_process(_delta: float) -> void:
    # Keyboard movement: WASD or arrow keys.
    var x_axis := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
    var y_axis := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
    var direction := Vector2(float(x_axis), float(y_axis))
    if direction.length() > 1.0:
        direction = direction.normalized()

    is_walking = direction.length() > 0.0
    if is_walking:
        velocity = direction * speed
        if absf(direction.x) > absf(direction.y):
            facing_name = "right" if direction.x > 0.0 else "left"
        else:
            facing_name = "down" if direction.y > 0.0 else "up"
    else:
        velocity = Vector2.ZERO

    move_and_slide()
    global_position = global_position.round()
    _update_depth_sort()
    _update_animation()
    _update_idle_motion(_delta)

func _build_sprite_frames() -> void:
    var sheet: Texture2D = load("res://assets/player_sheet.png")
    var frames := SpriteFrames.new()

    # The sprite sheet is a 4x4 grid of 16x20 pixel frames.
    # Rows: down, up, left, right. Columns: the four animation poses.
    var directions: Array[String] = ["down", "up", "left", "right"]
    for row in range(directions.size()):
        var direction: String = directions[row]
        var idle_name := "idle_" + direction
        var walk_name := "walk_" + direction

        frames.add_animation(idle_name)
        frames.set_animation_speed(idle_name, 1.0)
        frames.set_animation_loop(idle_name, true)

        frames.add_animation(walk_name)
        frames.set_animation_speed(walk_name, 8.0)
        frames.set_animation_loop(walk_name, true)

        var idle_texture := AtlasTexture.new()
        idle_texture.atlas = sheet
        idle_texture.region = Rect2(0, row * 20, 16, 20)
        frames.add_frame(idle_name, idle_texture)

        for column in range(4):
            var frame_texture := AtlasTexture.new()
            frame_texture.atlas = sheet
            frame_texture.region = Rect2(column * 16, row * 20, 16, 20)
            frames.add_frame(walk_name, frame_texture)

    sprite.sprite_frames = frames
    sprite.animation = "idle_down"

func _update_animation() -> void:
    var target_animation := ("walk_" if is_walking else "idle_") + facing_name
    if sprite.animation != target_animation or not sprite.is_playing():
        sprite.play(target_animation)

func _update_depth_sort() -> void:
    # The stall occluder is at z_index 2. Behind the counter we render at 1;
    # in front of it we render at 3. This is a small, scene-specific depth rule.
    var in_stall_back_zone := global_position.x >= 150.0 and global_position.x <= 258.0 and global_position.y < 79.0
    z_index = 1 if in_stall_back_zone else 3

func _update_idle_motion(delta: float) -> void:
    # A subtle one-pixel breathing bob keeps the character from looking frozen.
    # Reset the sprite's anchor while walking so movement animation stays crisp.
    if is_walking:
        idle_clock = 0.0
        sprite.position.y = -10.0
    else:
        idle_clock += delta
        var bob_up := sin(idle_clock * 2.0) > 0.82
        sprite.position.y = -11.0 if bob_up else -10.0

func _draw() -> void:
    # Draw the shadow first; the AnimatedSprite2D child is rendered on top.
    draw_rect(Rect2(-5, -2, 10, 3), Color("#172334"))
