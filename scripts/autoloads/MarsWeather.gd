# CHANGELOG (2026-11-15): Nonblocking NASA DONKI flare lookup; bounded timeout, validated JSON, offline-safe informational use only.
# API reference: https://api.nasa.gov/ (DONKI / FLR). Observed solar activity is not a Mars surface forecast.
extends Node

signal updated
@export var fetch_live_data: bool = true
@export var api_key: String = "DEMO_KEY"
var status_text := "NASA FACT: Mars receives about 43% of Earth's sunlight."
var last_flare_class := ""
var live_available := false
var _request: HTTPRequest

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or not fetch_live_data:
		return
	_request = HTTPRequest.new()
	_request.timeout = 5.0
	_request.body_size_limit = 1048576
	add_child(_request)
	_request.request_completed.connect(_on_completed)
	var today := Time.get_date_string_from_system(true)
	var err := _request.request("https://api.nasa.gov/DONKI/FLR?startDate=%s&endDate=%s&api_key=%s" % [today, today, api_key.uri_encode()])
	if err != OK:
		updated.emit()

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	live_available = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		updated.emit()
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		updated.emit()
		return
	var data: Variant = json.data
	if not (data is Array):
		updated.emit()
		return
	live_available = true
	last_flare_class = ""
	for item in data:
		if item is Dictionary and item.get("classType") is String:
			last_flare_class = item["classType"].left(24)
	status_text = "NASA DONKI: no solar flares reported today." if last_flare_class.is_empty() else "NASA DONKI: latest reported flare %s. Not a Mars forecast." % last_flare_class
	updated.emit()
