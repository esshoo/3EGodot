@tool
extends EditorPlugin

const MENU_ID := 15965
const USDZ_MIME := "model/vnd.usdz+zip"
const UsdzExporter := preload("res://addons/3e_usdz_exporter/usdz_exporter.gd")

var _export_as_menu: PopupMenu
var _file_dialog: FileDialog
var _pending_root: Node


func _enter_tree() -> void:
	_export_as_menu = get_export_as_menu()
	if _export_as_menu == null:
		push_error("3E USDZ Exporter: Scene > Export As menu is unavailable.")
		return

	# Avoid duplicates after script/plugin reloads.
	var old_index := _export_as_menu.get_item_index(MENU_ID)
	if old_index >= 0:
		_export_as_menu.remove_item(old_index)

	_export_as_menu.add_item("USDZ Scene...", MENU_ID)
	var index := _export_as_menu.get_item_index(MENU_ID)
	_export_as_menu.set_item_metadata(index, Callable(self, "_on_export_requested"))

	if not OS.has_feature("web"):
		_file_dialog = FileDialog.new()
		_file_dialog.title = "Export Scene to USDZ File"
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.usdz ; USDZ Scene"])
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)


func _exit_tree() -> void:
	if _export_as_menu != null:
		var index := _export_as_menu.get_item_index(MENU_ID)
		if index >= 0:
			_export_as_menu.remove_item(index)
	_export_as_menu = null

	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	_file_dialog = null
	_pending_root = null


func _on_export_requested() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("3E USDZ Exporter: Open or create a scene before exporting USDZ.")
		return

	_pending_root = root
	var filename := _suggested_filename(root)

	if OS.has_feature("web"):
		_export_to_web(root, filename)
		return

	if _file_dialog == null:
		push_error("3E USDZ Exporter: Save dialog is unavailable.")
		return

	_file_dialog.current_file = filename
	_file_dialog.popup_file_dialog()


func _on_file_selected(path: String) -> void:
	if _pending_root == null:
		return

	var export_path := path
	if export_path.get_extension().to_lower() != "usdz":
		export_path += ".usdz"

	var bytes := UsdzExporter.build_scene_package(_pending_root)
	if bytes.is_empty():
		push_error("3E USDZ Exporter: Failed to build USDZ package.")
		return

	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		push_error("3E USDZ Exporter: Could not open '%s' for writing (error %s)." % [export_path, FileAccess.get_open_error()])
		return

	file.store_buffer(bytes)
	file.close()
	print("3E USDZ Exporter: Wrote %s (%d bytes)." % [export_path, bytes.size()])


func _export_to_web(root: Node, filename: String) -> void:
	var bytes := UsdzExporter.build_scene_package(root)
	if bytes.is_empty():
		push_error("3E USDZ Exporter: Failed to build USDZ package.")
		return

	if not Engine.has_singleton("JavaScriptBridge"):
		push_error("3E USDZ Exporter: JavaScriptBridge is unavailable in this Web editor build.")
		return

	var bridge := Engine.get_singleton("JavaScriptBridge")
	bridge.download_buffer(bytes, filename, USDZ_MIME)
	print("3E USDZ Exporter: Requested browser download for %s (%d bytes)." % [filename, bytes.size()])


func _suggested_filename(root: Node) -> String:
	var basename := root.name
	var scene_path := root.scene_file_path
	if not scene_path.is_empty():
		basename = scene_path.get_file().get_basename()
	basename = _safe_filename(basename)
	if basename.is_empty():
		basename = "scene"
	return basename + ".usdz"


func _safe_filename(value: String) -> String:
	var result := ""
	for index in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95
		result += value.substr(index, 1) if valid else "_"
	return result
