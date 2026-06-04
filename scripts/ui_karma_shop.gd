extends PanelContainer

signal reincarnate_pressed

## Meta-Dashboard (between-run upgrade shop). Set in _ready(); used by refresh_from_meta().
var insight_label: Label
var _upgrade_entries: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 400
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.06, 0.08, 0.98)
	add_theme_stylebox_override("panel", bg_style)

	var center = CenterContainer.new()
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "META-DASHBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("81d4fa"))
	vbox.add_child(title)

	insight_label = Label.new()
	insight_label.text = "Available Insight: " + str(MetaManager.current_insight)
	insight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(insight_label)

	var shop_hbox = HBoxContainer.new()
	shop_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(shop_hbox)

	var upgrades = [
		{"id": "lens_nitrogen", "name": "Nitrogen Lens Unlock", "cost": 5, "desc": "Unlock nitrogen stress visualization on the lens bar."},
		{"id": "build_honesty_box", "name": "Farm Stand Kit", "cost": 5, "desc": "Unlock honesty-box construction in the build menu."},
		{"id": "seed_comfrey", "name": "Seed: Comfrey", "cost": 2, "desc": "Deep-rooted dynamic accumulator for mineral cycling."},
	]

	_upgrade_entries.clear()
	for upg in upgrades:
		var u_box = VBoxContainer.new()
		u_box.custom_minimum_size = Vector2(200, 0)

		var btn = Button.new()
		btn.text = "%s\n(%d Insight)" % [upg.name, upg.cost]
		btn.custom_minimum_size = Vector2(0, 60)

		var desc = Label.new()
		desc.text = upg.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

		u_box.add_child(btn)
		u_box.add_child(desc)
		shop_hbox.add_child(u_box)

		var uid: String = str(upg.id)
		var ucost: int = int(upg.cost)
		var uname: String = str(upg.name)

		_upgrade_entries.append({"btn": btn, "id": uid, "cost": ucost, "name": uname})

		if MetaManager.has_upgrade(uid):
			btn.disabled = true
			btn.text = "[ Unlocked ]"
		elif MetaManager.current_insight < ucost:
			btn.disabled = true

		btn.pressed.connect(func():
			if MetaManager.has_upgrade(uid):
				return
			if MetaManager.current_insight < ucost:
				return
			MetaManager.current_insight -= ucost
			MetaManager.unlocked_upgrades.append(uid)
			MetaManager.save_meta()
			refresh_from_meta()
		)

	var btn_next = Button.new()
	btn_next.text = "Start New Simulation"
	btn_next.custom_minimum_size = Vector2(0, 50)
	btn_next.pressed.connect(func(): reincarnate_pressed.emit())
	vbox.add_child(btn_next)

	hide()


func refresh_from_meta() -> void:
	if insight_label:
		insight_label.text = "Available Insight: " + str(MetaManager.current_insight)
	for e in _upgrade_entries:
		var btn: Button = e.get("btn") as Button
		if btn == null:
			continue
		var uid: String = str(e.get("id", ""))
		var ucost: int = int(e.get("cost", 0))
		var uname: String = str(e.get("name", ""))
		if MetaManager.has_upgrade(uid):
			btn.disabled = true
			btn.text = "[ Unlocked ]"
		elif MetaManager.current_insight < ucost:
			btn.disabled = true
		else:
			btn.disabled = false
			btn.text = "%s\n(%d Insight)" % [uname, ucost]
