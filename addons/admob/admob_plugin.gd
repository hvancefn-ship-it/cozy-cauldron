@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = load("res://addons/admob/android/poing_godot_admob_ads.gd").new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
	_export_plugin = null
