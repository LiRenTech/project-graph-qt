class_name TextNode
extends Entity

@onready var collision_shape: CollisionShape2D = %CollisionShape
@onready var label: Label = %Label
@onready var text_edit: TextEdit = %TextEdit

@export var text: String = "":
	set(value):
		text = value
		if is_node_ready():
			label.text = value
			call_deferred("_update_collision_shape")

var _text_before_edit := ""


func _ready() -> void:
	super()
	label.text = text
	call_deferred("_update_collision_shape")


func _on_label_gui_input(event: InputEvent) -> void:
	# 进入编辑模式
	if label.visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			enter_edit_mode()
			get_viewport().set_input_as_handled()
			return

	super._on_input_event(get_viewport(), event, 0)


func _on_text_edit_gui_input(event: InputEvent) -> void:
  # 处理文本编辑框的回车键：Enter 保存并退出编辑，Shift+Enter 保留默认的换行行为。
  # 后续需要改为可以在设置项里更改的方式。
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.shift_pressed:
		return
	if key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER:
		return

	text_edit.accept_event()
	exit_edit_mode()


func _unhandled_input(event: InputEvent) -> void:
	if text_edit.visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not text_edit.get_global_rect().has_point(event.global_position):
				exit_edit_mode()
				get_viewport().set_input_as_handled()


func enter_edit_mode() -> void:
	_text_before_edit = text
	text_edit.text = text
	text_edit.text_changed.emit()

	label.hide()
	text_edit.show()

	text_edit.grab_focus()
	text_edit.select_all()


func exit_edit_mode() -> void:
	if label.visible:
		return

	if text != text_edit.text:
		if _history != null:
			_history.begin_transaction()
		text = text_edit.text
		if _history != null:
			_history.commit()

	text_edit.hide()
	label.show()


func _update_collision_shape() -> void:
	var shape := RectangleShape2D.new()
	shape.size = label.size
	collision_shape.shape = shape
