extends "res://scripts/MainV04.gd"

# Android/Godot 4.4.1-safe asset palette implementation.
# MainV04's first pass used Button.icon_max_width, which is not a runtime
# property on Godot 4.4.1 Button. Keeping this override small lets the mobile
# build retain the full v0.4 toolset while using only supported Control APIs.
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
