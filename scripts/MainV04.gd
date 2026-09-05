extends Node2D

const TILE_W := 232.0
const TILE_H := 110.0
const HALF_W := TILE_W * 0.5
const HALF_H := TILE_H * 0.5
const IMAGE_ALIGN := Vector2(-12.0, -60.0)
const SURFACE_OFFSET := Vector2(-12.0, -55.0)
const LEVEL_STEP := 110.0
const SAVE_PATH := "user://world.json"
const MAX_HISTORY := 100
const TOP_TOUCH_GUARD := 84.0
const BOTTOM_TOUCH_GUARD := 220.0
const LEFT_TOUCH_GUARD := 96.0
const MAX_AREA_CELLS := 400

var catalog := {}
var assets_by_family := {}
var assets_by_category := {}
var categories: Array = []

var world_root: Node2D
var grid_overlay: Node2D
var camera: Camera2D
var cursor: Node2D
var ghost: Sprite2D

var selected_category := "Terrain"
var selected_family := "grass_center"
var selected_orientation := "S"
var selected_height := 0
var erase_mode := false
var grid_visible := true
var cursor_grid := Vector2i.ZERO
var active_tool := "STAMP"

var placements: Array = []
var nodes_by_id := {}
var next_id := 1
var undo_stack: Array = []
var redo_stack: Array = []

var ui_layer: CanvasLayer
var category_tab_strip: HBoxContainer
var category_tab_group: ButtonGroup
var category_buttons := {}
var asset_strip: HBoxContainer
var asset_scroll: ScrollContainer
var selected_label: Label
var hint_label: Label
var height_label: Label
var erase_button: Button
var grid_button: Button
var undo_button: Button
var redo_button: Button
var rotate_button: Button
var asset_group: ButtonGroup
var tool_group: ButtonGroup
var tool_buttons := {}
var clear_dialog: ConfirmationDialog
var toast_label: Label
var toast_timer: Timer

var touch_points := {}
var touch_start := Vector2.ZERO
var touch_last := Vector2.ZERO
var touch_moved := false
var pinch_active := false
var gesture_consumed := false
var pinch_start_distance := 0.0
var pinch_start_zoom := 1.0
var pinch_start_mid := Vector2.ZERO
var pinch_camera_start := Vector2.ZERO
var build_touch_index := -1
var gesture_start_cell := Vector2i.ZERO
var stroke_commands: Array = []
var stroke_seen := {}

var mouse_dragging := false
var mouse_start := Vector2.ZERO
var mouse_last := Vector2.ZERO
var mouse_moved := false

func _ready():
	_load_catalog()
	_create_world()
	_create_ui()
	_load_or_seed()
	if assets_by_family.has(selected_family):
		_select_asset(selected_family)
	elif not categories.is_empty():
		_select_category(str(categories[0]), true)
	_update_cursor(Vector2i.ZERO)
	_update_history_buttons()
	_set_tool("STAMP")

func _load_catalog():
	var file := FileAccess.open("res://assets/catalog.json", FileAccess.READ)
	if file == null:
		push_error("Could not load asset catalog.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Asset catalog JSON is invalid.")
		return
	catalog = parsed
	categories = catalog.get("categories", [])
	for cat in categories:
		assets_by_category[str(cat)] = []
	for raw_entry in catalog.get("assets", []):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var family := str(entry.get("family", ""))
		var cat := str(entry.get("category", "Decor"))
		assets_by_family[family] = entry
		if not assets_by_category.has(cat):
			assets_by_category[cat] = []
		assets_by_category[cat].append(entry)

func _create_world():
	grid_overlay = Node2D.new()
	grid_overlay.set_script(load("res://scripts/GridOverlay.gd"))
	add_child(grid_overlay)

	world_root = Node2D.new()
	world_root.name = "World"
	world_root.y_sort_enabled = true
	add_child(world_root)

	cursor = Node2D.new()
	cursor.name = "CellCursor"
	cursor.set_script(load("res://scripts/CellCursor.gd"))
	add_child(cursor)

	ghost = Sprite2D.new()
	ghost.name = "Ghost"
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.48)
	ghost.z_index = 100
	add_child(ghost)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	camera.position = Vector2(-12.0, 70.0)
	camera.zoom = Vector2(0.72, 0.72)
	add_child(camera)

func _create_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	var root_control := Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root_control)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.offset_left = 10
	top_margin.offset_top = 8
	top_margin.offset_right = -10
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top_margin)

	var top_panel := PanelContainer.new()
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	top_panel.add_theme_stylebox_override("panel", _style(Color(0.045, 0.055, 0.075, 0.97), 18, Color(1,1,1,0.08), 1))
	top_margin.add_child(top_panel)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	top_panel.add_child(top_bar)

	var title := Label.new()
	title.text = "BUILD  v0.4"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92,0.96,1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(title)

	undo_button = _tool_button("↶", "Undo")
	undo_button.pressed.connect(_undo)
	top_bar.add_child(undo_button)

	redo_button = _tool_button("↷", "Redo")
	redo_button.pressed.connect(_redo)
	top_bar.add_child(redo_button)

	rotate_button = _tool_button("⟳", "Rotate selected piece")
	rotate_button.pressed.connect(_rotate)
	top_bar.add_child(rotate_button)

	var minus_button := _tool_button("−", "Lower build height")
	minus_button.pressed.connect(func(): _change_height(-1))
	top_bar.add_child(minus_button)

	height_label = Label.new()
	height_label.text = "H 0"
	height_label.custom_minimum_size = Vector2(64, 54)
	height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	height_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	height_label.add_theme_color_override("font_color", Color(0.72,0.88,1.0))
	height_label.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(height_label)

	var plus_button := _tool_button("+", "Raise build height")
	plus_button.pressed.connect(func(): _change_height(1))
	top_bar.add_child(plus_button)

	erase_button = _tool_button("⌫", "Erase mode")
	erase_button.toggle_mode = true
	erase_button.toggled.connect(_set_erase_mode)
	top_bar.add_child(erase_button)

	grid_button = _tool_button("◇", "Toggle grid")
	grid_button.toggle_mode = true
	grid_button.button_pressed = true
	grid_button.toggled.connect(_set_grid_visible)
	top_bar.add_child(grid_button)

	var home_button := _tool_button("⌂", "Center camera")
	home_button.pressed.connect(_home_camera)
	top_bar.add_child(home_button)

	var clear_button := _tool_button("NEW", "Start a new world")
	clear_button.custom_minimum_size = Vector2(82,54)
	clear_button.pressed.connect(func(): clear_dialog.popup_centered(Vector2i(520,220)))
	top_bar.add_child(clear_button)

	var rail_margin := MarginContainer.new()
	rail_margin.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	rail_margin.offset_left = 10
	rail_margin.offset_right = 88
	rail_margin.offset_top = -154
	rail_margin.offset_bottom = 154
	rail_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(rail_margin)

	var rail_panel := PanelContainer.new()
	rail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	rail_panel.add_theme_stylebox_override("panel", _style(Color(0.045,0.055,0.075,0.96), 16, Color(1,1,1,0.08), 1))
	rail_margin.add_child(rail_panel)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 5)
	rail_panel.add_child(rail)
	tool_group = ButtonGroup.new()
	for mode in ["MOVE", "STAMP", "PAINT", "LINE", "AREA", "PICK"]:
		var mode_name := str(mode)
		var b := Button.new()
		b.text = mode_name
		b.custom_minimum_size = Vector2(66, 44)
		b.toggle_mode = true
		b.button_group = tool_group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func(): _set_tool(mode_name))
		tool_buttons[mode_name] = b
		rail.add_child(b)

	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.offset_left = 10
	bottom_margin.offset_bottom = -10
	bottom_margin.offset_right = -10
	bottom_margin.offset_top = -210
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(bottom_margin)

	var bottom_panel := PanelContainer.new()
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom_panel.add_theme_stylebox_override("panel", _style(Color(0.045,0.055,0.075,0.98), 18, Color(1,1,1,0.08), 1))
	bottom_margin.add_child(bottom_panel)

	var palette_v := VBoxContainer.new()
	palette_v.add_theme_constant_override("separation", 6)
	bottom_panel.add_child(palette_v)

	var category_scroll := ScrollContainer.new()
	category_scroll.custom_minimum_size = Vector2(0, 48)
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.scroll_deadzone = 12
	palette_v.add_child(category_scroll)

	category_tab_strip = HBoxContainer.new()
	category_tab_strip.add_theme_constant_override("separation", 6)
	category_scroll.add_child(category_tab_strip)
	category_tab_group = ButtonGroup.new()
	for cat in categories:
		var cat_name := str(cat)
		var count: int = int(assets_by_category.get(cat_name, []).size())
		var cb := Button.new()
		cb.text = "%s  %d" % [cat_name, count]
		cb.custom_minimum_size = Vector2(116, 44)
		cb.toggle_mode = true
		cb.button_group = category_tab_group
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		cb.pressed.connect(func(): _select_category(cat_name, true))
		category_buttons[cat_name] = cb
		category_tab_strip.add_child(cb)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 10)
	palette_v.add_child(info_row)

	selected_label = Label.new()
	selected_label.text = "Select a piece"
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_label.add_theme_color_override("font_color", Color(0.90,0.94,0.98))
	selected_label.add_theme_font_size_override("font_size", 15)
	info_row.add_child(selected_label)

	hint_label = Label.new()
	hint_label.text = "Tap to place"
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", Color(0.56,0.65,0.75))
	hint_label.add_theme_font_size_override("font_size", 12)
	info_row.add_child(hint_label)

	asset_scroll = ScrollContainer.new()
	asset_scroll.custom_minimum_size = Vector2(0, 102)
	asset_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	asset_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	asset_scroll.scroll_deadzone = 12
	palette_v.add_child(asset_scroll)

	asset_strip = HBoxContainer.new()
	asset_strip.add_theme_constant_override("separation", 8)
	asset_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_scroll.add_child(asset_strip)

	toast_label = Label.new()
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 15)
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	toast_label.add_theme_stylebox_override("normal", _style(Color(0.08,0.10,0.13,0.94), 12, Color(1,1,1,0.08), 1))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-145, 78)
	toast_label.size = Vector2(290, 42)
	root_control.add_child(toast_label)

	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 1.5
	toast_timer.timeout.connect(func(): toast_label.visible = false)
	add_child(toast_timer)

	clear_dialog = ConfirmationDialog.new()
	clear_dialog.title = "Start a new world?"
	clear_dialog.dialog_text = "This clears the current build and creates a fresh grass platform."
	clear_dialog.ok_button_text = "Start new"
	clear_dialog.cancel_button_text = "Cancel"
	clear_dialog.confirmed.connect(_confirm_new_world)
	ui_layer.add_child(clear_dialog)

	_refresh_category_tabs()
	_refresh_asset_strip()

func _style(bg: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = border
	s.border_width_left = border_width
	s.border_width_top = border_width
	s.border_width_right = border_width
	s.border_width_bottom = border_width
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

func _tool_button(text_value: String, tooltip_value: String) -> Button:
	var b := Button.new()
	b.text = text_value
	b.tooltip_text = tooltip_value
	b.custom_minimum_size = Vector2(56, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	return b

func _set_tool(mode: String):
	active_tool = mode
	if tool_buttons.has(mode):
		var b: Button = tool_buttons[mode]
		b.button_pressed = true
	if mode == "PICK":
		erase_mode = false
		erase_button.button_pressed = false
	_update_selected_label()

func _select_category(category_name: String, choose_first: bool = true):
	if not assets_by_category.has(category_name):
		return
	selected_category = category_name
	_refresh_category_tabs()
	_refresh_asset_strip()
	var entries: Array = assets_by_category.get(selected_category, [])
	if choose_first and not entries.is_empty():
		_select_asset(str(entries[0].get("family", "")))
		_toast("%s • %d pieces" % [selected_category, entries.size()])

func _refresh_category_tabs():
	for cat_name in category_buttons.keys():
		var b: Button = category_buttons[cat_name]
		b.button_pressed = str(cat_name) == selected_category

func _refresh_asset_strip():
	for child in asset_strip.get_children():
		asset_strip.remove_child(child)
		child.queue_free()
	asset_group = ButtonGroup.new()
	var entries: Array = assets_by_category.get(selected_category, [])
	for entry in entries:
		var family := str(entry.get("family", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(142, 94)
		button.toggle_mode = true
		button.button_group = asset_group
		button.focus_mode = Control.FOCUS_NONE
		button.expand_icon = true
		button.icon_max_width = 68
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = str(entry.get("display_name", family))
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = str(entry.get("display_name", family))
		var orientations: Dictionary = entry.get("orientations", {})
		var thumb_path := str(orientations.get("S", orientations.get("N", "")))
		if thumb_path != "":
			button.icon = load(thumb_path)
		button.button_pressed = family == selected_family
		var family_name := family
		button.pressed.connect(func(): _select_asset(family_name))
		asset_strip.add_child(button)
	asset_strip.reset_size()

func _select_asset(family: String):
	if not assets_by_family.has(family):
		return
	selected_family = family
	var entry: Dictionary = assets_by_family[family]
	var asset_category := str(entry.get("category", selected_category))
	if asset_category != selected_category:
		selected_category = asset_category
		_refresh_category_tabs()
		_refresh_asset_strip()
	var orientations: Dictionary = entry.get("orientations", {})
	if orientations.is_empty():
		return
	if not orientations.has(selected_orientation):
		selected_orientation = "S" if orientations.has("S") else str(orientations.keys()[0])
	erase_mode = false
	erase_button.button_pressed = false
	_update_selected_label()
	_update_ghost_texture()
	_refresh_pressed_state_only()

func _refresh_pressed_state_only():
	var display_name := str(assets_by_family.get(selected_family, {}).get("display_name", ""))
	for child in asset_strip.get_children():
		if child is Button:
			var btn: Button = child
			btn.button_pressed = btn.tooltip_text == display_name

func _update_selected_label():
	if selected_label == null:
		return
	var entry: Dictionary = assets_by_family.get(selected_family, {})
	var name := str(entry.get("display_name", selected_family))
	if erase_mode:
		selected_label.text = "%s • ERASER • H %d" % [active_tool, selected_height]
	else:
		selected_label.text = "%s • %s • %s • H %d" % [active_tool, name, selected_orientation, selected_height]
	if hint_label == null:
		return
	match active_tool:
		"MOVE": hint_label.text = "Drag to move • pinch to zoom"
		"STAMP": hint_label.text = "Tap build • drag move • pinch zoom"
		"PAINT": hint_label.text = "Drag to paint • two fingers move/zoom"
		"LINE": hint_label.text = "Drag from start to end"
		"AREA": hint_label.text = "Drag an area to fill"
		"PICK": hint_label.text = "Tap a piece to copy it"
		_: hint_label.text = "Build"

func _rotate():
	if erase_mode or not assets_by_family.has(selected_family):
		return
	var entry: Dictionary = assets_by_family[selected_family]
	var orientations: Dictionary = entry.get("orientations", {})
	var order := ["N", "E", "S", "W"]
	var start := order.find(selected_orientation)
	if start < 0:
		start = 0
	for i in range(1, 5):
		var candidate: String = order[(start + i) % 4]
		if orientations.has(candidate):
			selected_orientation = candidate
			break
	_update_selected_label()
	_update_ghost_texture()

func _change_height(delta: int):
	selected_height = clampi(selected_height + delta, -2, 12)
	height_label.text = "H %d" % selected_height
	_update_cursor(cursor_grid)
	_update_ghost_texture()
	_update_selected_label()

func _set_erase_mode(enabled: bool):
	erase_mode = enabled
	ghost.visible = not enabled
	if enabled and active_tool == "PICK":
		_set_tool("STAMP")
	_update_selected_label()

func _set_grid_visible(enabled: bool):
	grid_visible = enabled
	if grid_overlay.has_method("set_enabled"):
		grid_overlay.set_enabled(enabled)

func _home_camera():
	camera.position = Vector2(-12.0, 70.0)
	camera.zoom = Vector2(0.72, 0.72)
	_save_world()
	_toast("Camera centered")

func _iso_anchor(cell: Vector2i) -> Vector2:
	return Vector2((cell.x - cell.y) * HALF_W, (cell.x + cell.y) * HALF_H)

func _surface_center(cell: Vector2i, height: int = 0) -> Vector2:
	return _iso_anchor(cell) + SURFACE_OFFSET + Vector2(0.0, -height * LEVEL_STEP)

func _sprite_center(cell: Vector2i, height: int = 0) -> Vector2:
	return _iso_anchor(cell) + IMAGE_ALIGN + Vector2(0.0, -height * LEVEL_STEP)

func _world_to_grid(world_pos: Vector2, height: int = 0) -> Vector2i:
	var p := world_pos - SURFACE_OFFSET - Vector2(0.0, -height * LEVEL_STEP)
	var fx := (p.x / HALF_W + p.y / HALF_H) * 0.5
	var fy := (p.y / HALF_H - p.x / HALF_W) * 0.5
	return Vector2i(roundi(fx), roundi(fy))

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _update_cursor(cell: Vector2i):
	cursor_grid = cell
	cursor.position = _surface_center(cell, selected_height)
	ghost.position = _sprite_center(cell, selected_height)

func _update_ghost_texture():
	if erase_mode or not assets_by_family.has(selected_family):
		ghost.visible = false
		return
	var entry: Dictionary = assets_by_family[selected_family]
	var orientations: Dictionary = entry.get("orientations", {})
	var path := str(orientations.get(selected_orientation, ""))
	if path != "":
		ghost.texture = load(path)
		ghost.visible = true
		ghost.position = _sprite_center(cursor_grid, selected_height)

func _make_item(cell: Vector2i) -> Dictionary:
	var entry: Dictionary = assets_by_family.get(selected_family, {})
	var orientations: Dictionary = entry.get("orientations", {})
	var path := str(orientations.get(selected_orientation, ""))
	return {
		"id": next_id,
		"x": cell.x,
		"y": cell.y,
		"height": selected_height,
		"family": selected_family,
		"orientation": selected_orientation,
		"path": path,
		"sequence": next_id
	}

func _act_at_cell(cell: Vector2i, record_history: bool = true) -> Dictionary:
	var command := {}
	if erase_mode:
		var target = _find_top_at(cell)
		if target == null:
			return command
		_remove_item_by_id(int(target.id))
		command = {"type":"erase", "item":target}
	else:
		if not assets_by_family.has(selected_family):
			return command
		var item := _make_item(cell)
		if str(item.path) == "":
			return command
		var old_item = _find_same_family(cell, selected_height, selected_family)
		if old_item != null and str(old_item.orientation) == selected_orientation:
			return command
		next_id += 1
		if old_item != null:
			_remove_item_by_id(int(old_item.id))
			_add_item(item)
			command = {"type":"replace", "old":old_item.duplicate(true), "new":item.duplicate(true)}
		else:
			_add_item(item)
			command = {"type":"add", "item":item.duplicate(true)}

	if not command.is_empty() and record_history:
		_push_history(command)
		_save_world()
	return command

func _add_item(item: Dictionary):
	var path := str(item.get("path", ""))
	if path == "":
		var entry: Dictionary = assets_by_family.get(str(item.get("family","")), {})
		var orientations: Dictionary = entry.get("orientations", {})
		path = str(orientations.get(str(item.get("orientation","S")), ""))
		item["path"] = path
	if path == "":
		return

	var cell := Vector2i(int(item.x), int(item.y))
	var height := int(item.height)
	var wrapper := Node2D.new()
	wrapper.name = "Piece_%d" % int(item.id)
	var tie := float(cell.x) * 0.01 + float(height) * 0.001 + float(int(item.get("sequence", 1)) % 1000) * 0.000001
	wrapper.position = _iso_anchor(cell) + Vector2(0.0, tie)

	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.position = IMAGE_ALIGN + Vector2(0.0, -height * LEVEL_STEP)
	wrapper.add_child(sprite)
	world_root.add_child(wrapper)

	nodes_by_id[int(item.id)] = wrapper
	placements.append(item.duplicate(true))
	next_id = maxi(next_id, int(item.id) + 1)

func _remove_item_by_id(id_value: int) -> Dictionary:
	var removed := {}
	for i in range(placements.size() - 1, -1, -1):
		if int(placements[i].id) == id_value:
			removed = placements[i].duplicate(true)
			placements.remove_at(i)
			break
	if nodes_by_id.has(id_value):
		var node = nodes_by_id[id_value]
		nodes_by_id.erase(id_value)
		if is_instance_valid(node):
			node.queue_free()
	return removed

func _find_same_family(cell: Vector2i, height: int, family: String):
	for i in range(placements.size() - 1, -1, -1):
		var item: Dictionary = placements[i]
		if int(item.x) == cell.x and int(item.y) == cell.y and int(item.height) == height and str(item.family) == family:
			return item.duplicate(true)
	return null

func _find_top_at(cell: Vector2i):
	var best = null
	for item in placements:
		if int(item.x) != cell.x or int(item.y) != cell.y:
			continue
		if best == null:
			best = item
			continue
		var h := int(item.height)
		var bh := int(best.height)
		if h > bh or (h == bh and int(item.sequence) > int(best.sequence)):
			best = item
	return null if best == null else best.duplicate(true)

func _pick_at(cell: Vector2i):
	var item = _find_top_at(cell)
	if item == null:
		_toast("No piece here to pick")
		return
	selected_height = int(item.height)
	height_label.text = "H %d" % selected_height
	selected_orientation = str(item.orientation)
	_select_asset(str(item.family))
	_set_tool("STAMP")
	_update_cursor(cell)
	_toast("Copied %s" % str(assets_by_family.get(selected_family, {}).get("display_name", selected_family)))

func _push_history(command: Dictionary):
	if command.is_empty():
		return
	undo_stack.append(command)
	if undo_stack.size() > MAX_HISTORY:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_history_buttons()

func _undo_command(command: Dictionary):
	var t := str(command.get("type",""))
	if t == "add":
		_remove_item_by_id(int(command.item.id))
	elif t == "erase":
		_add_item(command.item.duplicate(true))
	elif t == "replace":
		_remove_item_by_id(int(command.new.id))
		_add_item(command.old.duplicate(true))
	elif t == "batch":
		var commands: Array = command.get("commands", [])
		for i in range(commands.size() - 1, -1, -1):
			_undo_command(commands[i])

func _redo_command(command: Dictionary):
	var t := str(command.get("type",""))
	if t == "add":
		_add_item(command.item.duplicate(true))
	elif t == "erase":
		_remove_item_by_id(int(command.item.id))
	elif t == "replace":
		_remove_item_by_id(int(command.old.id))
		_add_item(command.new.duplicate(true))
	elif t == "batch":
		var commands: Array = command.get("commands", [])
		for sub in commands:
			_redo_command(sub)

func _undo():
	if undo_stack.is_empty():
		return
	var command: Dictionary = undo_stack.pop_back()
	_undo_command(command)
	redo_stack.append(command)
	_update_history_buttons()
	_save_world()

func _redo():
	if redo_stack.is_empty():
		return
	var command: Dictionary = redo_stack.pop_back()
	_redo_command(command)
	undo_stack.append(command)
	_update_history_buttons()
	_save_world()

func _update_history_buttons():
	if undo_button != null:
		undo_button.disabled = undo_stack.is_empty()
	if redo_button != null:
		redo_button.disabled = redo_stack.is_empty()

func _commit_commands(commands: Array):
	if commands.is_empty():
		return
	if commands.size() == 1:
		_push_history(commands[0])
	else:
		_push_history({"type":"batch", "commands":commands.duplicate(true)})
	_save_world()

func _begin_stroke(cell: Vector2i):
	stroke_commands.clear()
	stroke_seen.clear()
	_stroke_cell(cell)

func _stroke_cell(cell: Vector2i):
	var key := "%d:%d:%d" % [cell.x, cell.y, selected_height]
	if stroke_seen.has(key):
		return
	stroke_seen[key] = true
	var command := _act_at_cell(cell, false)
	if not command.is_empty():
		stroke_commands.append(command)

func _end_stroke():
	_commit_commands(stroke_commands)
	stroke_commands.clear()
	stroke_seen.clear()

func _line_cells(a: Vector2i, b: Vector2i) -> Array:
	var result: Array = []
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		result.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return result

func _smart_orientation_for_line(a: Vector2i, b: Vector2i) -> String:
	if not assets_by_family.has(selected_family):
		return selected_orientation
	var orientations: Dictionary = assets_by_family[selected_family].get("orientations", {})
	if orientations.size() <= 1:
		return selected_orientation
	var delta := b - a
	var candidate := selected_orientation
	if absi(delta.x) >= absi(delta.y):
		candidate = "E" if delta.x >= 0 else "W"
	else:
		candidate = "S" if delta.y >= 0 else "N"
	return candidate if orientations.has(candidate) else selected_orientation

func _place_line(a: Vector2i, b: Vector2i):
	var cells := _line_cells(a, b)
	var commands: Array = []
	var old_orientation := selected_orientation
	selected_orientation = _smart_orientation_for_line(a, b)
	for cell in cells:
		var command := _act_at_cell(cell, false)
		if not command.is_empty():
			commands.append(command)
	selected_orientation = old_orientation
	_update_ghost_texture()
	_update_selected_label()
	_commit_commands(commands)
	if commands.size() > 1:
		_toast("Built %d-piece line" % commands.size())

func _place_area(a: Vector2i, b: Vector2i):
	var min_x := mini(a.x, b.x)
	var max_x := maxi(a.x, b.x)
	var min_y := mini(a.y, b.y)
	var max_y := maxi(a.y, b.y)
	var count := (max_x - min_x + 1) * (max_y - min_y + 1)
	if count > MAX_AREA_CELLS:
		_toast("Area too large • max %d cells" % MAX_AREA_CELLS)
		return
	var commands: Array = []
	for gx in range(min_x, max_x + 1):
		for gy in range(min_y, max_y + 1):
			var command := _act_at_cell(Vector2i(gx, gy), false)
			if not command.is_empty():
				commands.append(command)
	_commit_commands(commands)
	if commands.size() > 1:
		_toast("Filled %d cells" % commands.size())

func _confirm_new_world():
	_clear_all_pieces()
	undo_stack.clear()
	redo_stack.clear()
	next_id = 1
	_seed_platform()
	_home_camera()
	selected_height = 0
	height_label.text = "H 0"
	_update_history_buttons()
	_save_world()
	_toast("Fresh world ready")

func _clear_all_pieces():
	for node in nodes_by_id.values():
		if is_instance_valid(node):
			node.queue_free()
	nodes_by_id.clear()
	placements.clear()

func _seed_platform():
	if not assets_by_family.has("grass_center"):
		return
	var entry: Dictionary = assets_by_family["grass_center"]
	var orientations: Dictionary = entry.get("orientations", {})
	if orientations.is_empty():
		return
	var fallback_path := str(orientations.values()[0])
	var path := str(orientations.get("S", fallback_path))
	var fallback_orientation := str(orientations.keys()[0])
	for gx in range(-3, 4):
		for gy in range(-3, 4):
			var item := {
				"id": next_id,
				"x": gx,
				"y": gy,
				"height": 0,
				"family": "grass_center",
				"orientation": "S" if orientations.has("S") else fallback_orientation,
				"path": path,
				"sequence": next_id
			}
			next_id += 1
			_add_item(item)

func _load_or_seed():
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var saved_placements = parsed.get("placements", [])
				if typeof(saved_placements) == TYPE_ARRAY and saved_placements.size() > 0:
					next_id = int(parsed.get("next_id", 1))
					for item in saved_placements:
						if typeof(item) == TYPE_DICTIONARY:
							_add_item(item)
					var cam = parsed.get("camera", {})
					if typeof(cam) == TYPE_DICTIONARY:
						camera.position = Vector2(float(cam.get("x",-12.0)), float(cam.get("y",70.0)))
						var z := clampf(float(cam.get("zoom",0.72)), 0.35, 2.5)
						camera.zoom = Vector2(z,z)
					return
	_seed_platform()
	_save_world()

func _save_world():
	var data := {
		"version": 2,
		"next_id": next_id,
		"placements": placements,
		"camera": {"x": camera.position.x, "y": camera.position.y, "zoom": camera.zoom.x}
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))

func _toast(message: String):
	if toast_label == null:
		return
	toast_label.text = "  %s  " % message
	toast_label.visible = true
	toast_timer.start()

func _is_ui_touch(screen_pos: Vector2) -> bool:
	var viewport_size := get_viewport_rect().size
	if screen_pos.y <= TOP_TOUCH_GUARD or screen_pos.y >= viewport_size.y - BOTTOM_TOUCH_GUARD:
		return true
	if screen_pos.x <= LEFT_TOUCH_GUARD:
		return true
	return false

func _start_pinch():
	if touch_points.size() < 2:
		return
	pinch_active = true
	gesture_consumed = true
	var pts: Array = touch_points.values()
	var p0 := Vector2(pts[0])
	var p1 := Vector2(pts[1])
	pinch_start_distance = maxf(1.0, p0.distance_to(p1))
	pinch_start_zoom = camera.zoom.x
	pinch_start_mid = (p0 + p1) * 0.5
	pinch_camera_start = camera.position

func _update_pinch():
	if touch_points.size() < 2:
		return
	var pts: Array = touch_points.values()
	var p0 := Vector2(pts[0])
	var p1 := Vector2(pts[1])
	var dist := maxf(1.0, p0.distance_to(p1))
	var z := clampf(pinch_start_zoom * (dist / pinch_start_distance), 0.35, 2.5)
	var mid := (p0 + p1) * 0.5
	camera.zoom = Vector2(z,z)
	camera.position = pinch_camera_start - (mid - pinch_start_mid) / z

func _touch_world_cell(screen_pos: Vector2) -> Vector2i:
	return _world_to_grid(_screen_to_world(screen_pos), selected_height)

func _unhandled_input(event: InputEvent):
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			if _is_ui_touch(event.position):
				return
			touch_points[idx] = event.position
			if touch_points.size() == 1:
				build_touch_index = idx
				touch_start = event.position
				touch_last = event.position
				touch_moved = false
				gesture_consumed = false
				gesture_start_cell = _touch_world_cell(event.position)
				_update_cursor(gesture_start_cell)
				if active_tool == "PAINT":
					_begin_stroke(gesture_start_cell)
			elif touch_points.size() == 2:
				_start_pinch()
		else:
			if not touch_points.has(idx):
				return
			var release_cell := _touch_world_cell(event.position)
			touch_points.erase(idx)
			if pinch_active:
				if touch_points.size() < 2:
					pinch_active = false
					gesture_consumed = true
					_save_world()
			elif idx == build_touch_index:
				match active_tool:
					"PAINT":
						_end_stroke()
					"LINE":
						if not gesture_consumed:
							_place_line(gesture_start_cell, release_cell)
					"AREA":
						if not gesture_consumed:
							_place_area(gesture_start_cell, release_cell)
					"PICK":
						if not gesture_consumed and not touch_moved:
							_pick_at(release_cell)
					"STAMP":
						if not gesture_consumed and not touch_moved:
							_act_at_cell(release_cell, true)
					_:
						pass
			build_touch_index = -1
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		if not touch_points.has(event.index):
			return
		touch_points[event.index] = event.position
		if touch_points.size() >= 2:
			if not pinch_active:
				_start_pinch()
			_update_pinch()
			get_viewport().set_input_as_handled()
			return

		var current_cell := _touch_world_cell(event.position)
		_update_cursor(current_cell)
		var delta: Vector2 = event.position - touch_last
		if event.position.distance_to(touch_start) > 12.0:
			touch_moved = true
		match active_tool:
			"PAINT":
				_stroke_cell(current_cell)
			"LINE", "AREA":
				pass
			"MOVE", "STAMP", "PICK":
				if touch_moved:
					camera.position -= delta / camera.zoom.x
			_:
				pass
		touch_last = event.position
		get_viewport().set_input_as_handled()
		return

	if DisplayServer.is_touchscreen_available():
		return

	if event is InputEventMouseMotion:
		if mouse_dragging:
			var delta: Vector2 = event.position - mouse_last
			if event.position.distance_to(mouse_start) > 6.0:
				mouse_moved = true
			if mouse_moved:
				camera.position -= delta / camera.zoom.x
			mouse_last = event.position
		else:
			_update_cursor(_touch_world_cell(event.position))
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.12)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.12)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				mouse_dragging = true
				mouse_start = event.position
				mouse_last = event.position
				mouse_moved = false
				gesture_start_cell = _touch_world_cell(event.position)
				if active_tool == "PAINT":
					_begin_stroke(gesture_start_cell)
			else:
				var end_cell := _touch_world_cell(event.position)
				if active_tool == "PAINT":
					_end_stroke()
				elif active_tool == "LINE":
					_place_line(gesture_start_cell, end_cell)
				elif active_tool == "AREA":
					_place_area(gesture_start_cell, end_cell)
				elif active_tool == "PICK" and not mouse_moved:
					_pick_at(end_cell)
				elif active_tool == "STAMP" and not mouse_moved:
					_act_at_cell(end_cell, true)
				mouse_dragging = false

func _zoom_by(factor: float):
	var z := clampf(camera.zoom.x * factor, 0.35, 2.5)
	camera.zoom = Vector2(z,z)
	_save_world()
