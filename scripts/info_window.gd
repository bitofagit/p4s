extends PanelContainer

@onready var topic_list: ItemList = $VBoxContainer/HSplitContainer/Topic_List
@onready var content_text: RichTextLabel = $VBoxContainer/HSplitContainer/MarginContainer/Content_Text
@onready var close_button: Button = $VBoxContainer/HBoxContainer/Close_Button
@onready var title_label: Label = $VBoxContainer/HBoxContainer/Label

var current_data: Dictionary = {}


func _ready() -> void:
	MapScrollBlockerUtil.tag_control_tree(self)
	close_button.pressed.connect(hide)
	topic_list.item_selected.connect(_on_topic_selected)
	topic_list.gui_input.connect(_forward_scroll_block)
	content_text.gui_input.connect(_forward_scroll_block)
	hide()


func _forward_scroll_block(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [
			MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT,
		]:
			UIInputUtil.safe_set_input_handled(self)


func load_data(title: String, data: Dictionary) -> void:
	title_label.text = title.to_upper()
	current_data = data
	topic_list.clear()
	content_text.text = ""

	for key in data.keys():
		topic_list.add_item(key)

	if topic_list.item_count > 0:
		topic_list.select(0)
		_on_topic_selected(0)

	show()


func _on_topic_selected(index: int) -> void:
	var key := topic_list.get_item_text(index)
	if not current_data.has(key):
		return
	var val = current_data[key]
	if val is Dictionary:
		content_text.text = str(val)
	else:
		content_text.text = val
