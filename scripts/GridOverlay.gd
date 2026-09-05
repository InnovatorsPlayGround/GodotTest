extends Node2D

const TILE_W := 232.0
const TILE_H := 110.0
const SURFACE_OFFSET := Vector2(-12.0, -55.0)

var grid_enabled := true
var radius := 26
var line_color := Color(1.0, 1.0, 1.0, 0.08)
var axis_color := Color(0.72, 0.92, 1.0, 0.18)

func _ready():
	z_index = -100
	queue_redraw()

func set_enabled(value: bool):
	grid_enabled = value
	visible = value

func _draw():
	if not grid_enabled:
		return

	var lines := PackedVector2Array()
	for gx in range(-radius, radius + 1):
		for gy in range(-radius, radius + 1):
			var c := Vector2((gx - gy) * TILE_W * 0.5, (gx + gy) * TILE_H * 0.5) + SURFACE_OFFSET
			var top := c + Vector2(0.0, -TILE_H * 0.5)
			var right := c + Vector2(TILE_W * 0.5, 0.0)
			var bottom := c + Vector2(0.0, TILE_H * 0.5)
			var left := c + Vector2(-TILE_W * 0.5, 0.0)
			lines.append(top); lines.append(right)
			lines.append(right); lines.append(bottom)
			lines.append(bottom); lines.append(left)
			lines.append(left); lines.append(top)
	draw_multiline(lines, line_color, 1.0, true)

	var c0 := SURFACE_OFFSET
	var origin_poly := PackedVector2Array([
		c0 + Vector2(0.0, -TILE_H * 0.5),
		c0 + Vector2(TILE_W * 0.5, 0.0),
		c0 + Vector2(0.0, TILE_H * 0.5),
		c0 + Vector2(-TILE_W * 0.5, 0.0),
		c0 + Vector2(0.0, -TILE_H * 0.5)
	])
	draw_polyline(origin_poly, axis_color, 2.0, true)
