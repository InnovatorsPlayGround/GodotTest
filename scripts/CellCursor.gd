extends Node2D

const TILE_W := 232.0
const TILE_H := 110.0

var cursor_color := Color(0.55, 0.88, 1.0, 0.95)

func _ready():
	z_index = 2000000000
	queue_redraw()

func _draw():
	var points := PackedVector2Array([
		Vector2(0.0, -TILE_H * 0.5),
		Vector2(TILE_W * 0.5, 0.0),
		Vector2(0.0, TILE_H * 0.5),
		Vector2(-TILE_W * 0.5, 0.0),
		Vector2(0.0, -TILE_H * 0.5)
	])
	draw_polyline(points, cursor_color, 3.0, true)
