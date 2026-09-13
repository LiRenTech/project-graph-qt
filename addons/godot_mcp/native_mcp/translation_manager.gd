class_name MCPTranslationManager
extends RefCounted

const TRANSLATIONS_DIR: String = "res://addons/godot_mcp/translations/"
const DEFAULT_LOCALE: String = "en"

var _translations: Dictionary = {}
var _current_locale: String = DEFAULT_LOCALE

func load_all() -> void:
	_translations.clear()
	var available: Array[String] = _discover_locales()
	for locale in available:
		_translations[locale] = _load_csv(locale)

func load_locale(locale: String) -> Dictionary:
	var data: Dictionary = _load_csv(locale)
	if not data.is_empty():
		_translations[locale] = data
	return data

func get_text(key: String) -> String:
	if not _translations.has(_current_locale):
		return key
	var locale_data: Dictionary = _translations[_current_locale]
	return locale_data.get(key, key)

func set_locale(locale: String) -> void:
	if _translations.has(locale) or not _load_csv(locale).is_empty():
		_current_locale = locale

func get_locale() -> String:
	return _current_locale

func get_available_locales() -> Array:
	return _translations.keys()

func _discover_locales() -> Array[String]:
	var locales: Array[String] = []
	var dir: DirAccess = DirAccess.open(TRANSLATIONS_DIR)
	if not dir:
		push_warning("MCPTranslationManager: Translations directory not found: " + TRANSLATIONS_DIR)
		return locales

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".csv"):
			var file: FileAccess = FileAccess.open(TRANSLATIONS_DIR + file_name, FileAccess.READ)
			if file:
				var header: String = file.get_line()
				file.close()
				var columns: PackedStringArray = header.split(",")
				for col in columns:
					col = col.strip_edges()
					if col != "key" and col != "source" and not col in locales:
						locales.append(col)
		file_name = dir.get_next()
	dir.list_dir_end()
	return locales

func _load_csv(locale: String) -> Dictionary:
	var result: Dictionary = {}
	var dir: DirAccess = DirAccess.open(TRANSLATIONS_DIR)
	if not dir:
		return result

	var files_to_try: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".csv"):
			files_to_try.append(TRANSLATIONS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	for file_path in files_to_try:
		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			continue

		var header_line: String = file.get_line()
		var columns: PackedStringArray = header_line.split(",")
		var source_idx: int = columns.find("source")
		var translation_idx: int = columns.find(locale)
		var key_idx: int = columns.find("key")
		if key_idx < 0 or source_idx < 0:
			file.close()
			continue
		if translation_idx < 0:
			push_warning("MCPTranslationManager: Locale '%s' not found in %s, falling back to '%s'" % [locale, file_path.get_file(), DEFAULT_LOCALE])
			translation_idx = columns.find(DEFAULT_LOCALE)
		if translation_idx < 0:
			translation_idx = columns.find("translation")

		while not file.eof_reached():
			var line: String = file.get_line().strip_edges()
			if line.is_empty():
				continue
			var fields: PackedStringArray = _parse_csv_line(line)
			if fields.size() <= key_idx:
				continue
			var key: String = fields[key_idx].strip_edges()
			if key.is_empty():
				continue
			var source_text: String = fields[source_idx].strip_edges() if fields.size() > source_idx else ""
			if translation_idx >= 0 and fields.size() > translation_idx:
				var translated: String = fields[translation_idx].strip_edges()
				result[key] = translated if not translated.is_empty() else source_text
			else:
				result[key] = source_text

		file.close()

	return result

func _parse_csv_line(line: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current: String = ""
	var in_quotes: bool = false
	for i in range(line.length()):
		var c: String = line[i]
		if c == "\"":
			in_quotes = not in_quotes
		elif c == "," and not in_quotes:
			result.append(current)
			current = ""
		else:
			current += c
	result.append(current)
	return result