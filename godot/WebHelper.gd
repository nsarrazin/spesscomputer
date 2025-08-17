extends Node
# Autoload this singleton via Project Settings -> Autoload (Name: WebDX, Path: res://WebHelper.gd)

# Keep active JavaScript callbacks alive (prevents garbage collection)
var _callbacks: Dictionary = {}
var _thunks: Dictionary = {}

# Small helper that adapts a normal GDScript function to the JS callback shape.
# Small helper that adapts a normal GDScript function to the JS callback shape.
class BridgeThunk:
	extends RefCounted
	var target: Object
	var method: String

	func _init(t: Object, m: String) -> void:
		target = t
		method = m

	func bridge_cb(args: Array) -> void:
		# Our JS wrapper doesn't pass resolve/reject anymore — only real args.
		var argv = args

		if !is_instance_valid(target) or !target.has_method(method):
			return

		var result = target.callv(method, argv)

		# Marshal: primitives go through; complex -> JSON string.
		var to_js: Variant = result
		match typeof(result):
			TYPE_NIL:
				to_js = null
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY:
				pass
			_:
				to_js = JSON.stringify(result)

		# Stash on window under <name>__result for the wrapper to read.
		var js_name := method.substr(3) if method.begins_with("js_") else method
		var win = JavaScriptBridge.get_interface("window")
		win[js_name + "__result"] = to_js

# Expose a GDScript method to JS as window[name](...)
func expose(target: Object, method_name: String) -> void:
	if not OS.has_feature("web"):
		return

	var js_name := method_name.substr(3) if method_name.begins_with("js_") else method_name

	var thunk := BridgeThunk.new(target, method_name)
	var cb = JavaScriptBridge.create_callback(Callable(thunk, "bridge_cb"))

	_thunks[js_name] = thunk
	_callbacks[js_name] = cb

	var win = JavaScriptBridge.get_interface("window")
	win[js_name + "__cb"] = cb

	# Promise wrapper: invoke raw, then read <name>__result on the next microtask.
	JavaScriptBridge.eval("""
	(function(name){
	  const raw = name + "__cb";
	  const key = name + "__result";
	  if (typeof window[name] === "function" && window[name].__gdx) return;

	  window[name] = (...args) => new Promise((resolve, reject) => {
		try {
		  delete window[key];
		  window[raw](...args);
		  queueMicrotask(() => {
			const v = window[key];
			if (typeof v === "string") {
			  try { resolve(JSON.parse(v)); } catch { resolve(v); }
			} else {
			  resolve(v ?? null);
			}
		  });
		} catch (e) { reject(e); }
	  });
	  window[name].__gdx = true;
	})("%s");
	""" % js_name, true)
	
# Batch-expose all methods prefixed with 'js_'
func expose_all(target: Object) -> void:
	print("Exposing all")

	for mdict in target.get_method_list():
		if mdict["name"].begins_with("js_"):
			print("Exposing " + mdict["name"])
			expose(target, mdict["name"])

## Remove callback when owner exits scene tree
func _on_owner_freed(cb_name: String) -> void:
	_callbacks.erase(cb_name)
