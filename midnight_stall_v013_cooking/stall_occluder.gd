extends Node2D

# This node redraws the stall on a higher layer. The Player moves between
# z_index 1 (behind the stall) and z_index 3 (in front of the stall).
# The parent hides this node when the interaction panel is open so it never
# paints over the UI.
func _draw() -> void:
    # Shadow and legs.
    draw_rect(Rect2(157, 73, 94, 18), Color("#1b252e"))
    draw_rect(Rect2(165, 70, 7, 20), Color("#6d4637"))
    draw_rect(Rect2(236, 70, 7, 20), Color("#6d4637"))
    # Canopy and striped awning.
    draw_rect(Rect2(154, 39, 99, 23), Color("#e8b96f"))
    for i in range(7):
        var x := 156 + i * 14
        var stripe := Color("#b94d50") if i % 2 == 0 else Color("#f1d49b")
        draw_rect(Rect2(x, 40, 12, 20), stripe)
        draw_rect(Rect2(x, 57, 12, 4), Color("#7b373f") if i % 2 == 0 else Color("#c7a06b"))
    draw_rect(Rect2(154, 60, 99, 6), Color("#52383a"))
    draw_rect(Rect2(158, 66, 91, 12), Color("#7c4c39"))
    draw_rect(Rect2(161, 67, 84, 8), Color("#a46a47"))
    # Food display and shop sign.
    draw_rect(Rect2(170, 47, 17, 10), Color("#fff0be"))
    draw_rect(Rect2(172, 49, 13, 6), Color("#e5a94c"))
    draw_rect(Rect2(193, 47, 12, 10), Color("#d9e4d0"))
    draw_rect(Rect2(195, 49, 8, 6), Color("#8aaf96"))
    draw_rect(Rect2(218, 47, 18, 10), Color("#f3ddab"))
    draw_rect(Rect2(221, 49, 12, 6), Color("#d15b4f"))
    draw_rect(Rect2(182, 27, 46, 12), Color("#f4dba6"))
    draw_rect(Rect2(184, 29, 42, 8), Color("#74433a"))
    draw_string(ThemeDB.fallback_font, Vector2(188, 35), "MIDNIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("#fff1c8"))
