extends Node
# Autoload this singleton via Project Settings -> Autoload (Name: WebDX, Path: res://WebHelper.gd)

# Keep active JavaScript callbacks alive (prevents garbage collection)
var _callbacks: Dictionary = {}
var _thunks: Dictionary = {}

# Small helper that adapts a normal GDScript function to the JS callback shape.
# Small helper that adapts a normal GDScript function to the JS callback shape.

# ---- Thunk: adapts a normal GDScript method to the JS callback shape ----
class BridgeThunk:
	extends RefCounted
	var target: Object
	var method: String

	func _init(t: Object, m: String) -> void:
		target = t
		method = m

	# Called from JS as: __raw[name](call_id, ...args)
	func bridge_cb(args: Array) -> void:
		var call_id = args[0] if args.size() > 0 else 0
		var argv = args.slice(1, args.size()) if args.size() > 1 else []

		if !is_instance_valid(target) or !target.has_method(method):
			return

		var result = target.callv(method, argv)

		# Marshal: primitives pass; complex -> JSON string
		var to_js: Variant = result
		match typeof(result):
			TYPE_NIL:
				to_js = null
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY:
				pass
			_:
				to_js = JSON.stringify(result)

		var js_name := method.substr(3) if method.begins_with("js_") else method

		# Stash under window.WebHelper.__results[js_name][call_id]
		var ns = JavaScriptBridge.get_interface("WebHelper")
		if ns == null:
			# Shouldn't happen (namespace created in expose), but be defensive
			JavaScriptBridge.eval("window.WebHelper ??= {}; window.WebHelper.__results ??= {};", true)
			ns = JavaScriptBridge.get_interface("WebHelper")

		if ns.__results == null:
			ns.__results = JavaScriptBridge.create_object("Object")
		var bucket = ns.__results[js_name]
		if bucket == null:
			bucket = JavaScriptBridge.create_object("Object")
			ns.__results[js_name] = bucket
		bucket[str(call_id)] = to_js


# ---- Public API ----

# Expose a GDScript method to JS as window.WebHelper[name](...)
func expose(target: Object, method_name: String) -> void:
	if not OS.has_feature("web"):
		return

	var js_name := method_name.substr(3) if method_name.begins_with("js_") else method_name
	# Ensure namespace objects exist once
	JavaScriptBridge.eval("""
		window.WebHelper ??= {};
		WebHelper.__raw ??= {};
		WebHelper.__results ??= {};
	""", true)

	# Per-method thunk & raw callback
	var thunk := BridgeThunk.new(target, method_name)
	var cb = JavaScriptBridge.create_callback(Callable(thunk, "bridge_cb"))

	_thunks[js_name] = thunk
	_callbacks[js_name] = cb

	# Register raw callback under WebHelper.__raw[name]
	var ns = JavaScriptBridge.get_interface("WebHelper")
	ns.__raw[js_name] = cb

	# Promise wrapper under WebHelper[name]
	JavaScriptBridge.eval("""
	(function(name){
	  const NS = window.WebHelper;
	  if (typeof NS[name] === "function" && NS[name].__gdx) return;

	  NS[name] = (...args) => new Promise((resolve, reject) => {
		try {
		  const id = (NS[name].__seq = (NS[name].__seq || 0) + 1);
		  NS.__results[name] ??= {};
		  delete NS.__results[name][String(id)];
		  NS.__raw[name](id, ...args);
		  queueMicrotask(() => {
			const v = NS.__results[name][String(id)];
			delete NS.__results[name][String(id)];
			if (typeof v === "string") {
			  try { resolve(JSON.parse(v)); } catch { resolve(v); }
			} else {
			  resolve(v ?? null);
			}
		  });
		} catch (e) { reject(e); }
	  });
	  NS[name].__gdx = true;
	})("%s");
	""" % js_name, true)

	# Cleanup this method when the owner leaves the tree
	target.tree_exited.connect(func():
		_unexpose(js_name),
		CONNECT_ONE_SHOT
	)

# Expose all methods prefixed with 'js_'
func expose_all(target: Object) -> void:
	for mdict in target.get_method_list():
		if mdict["name"].begins_with("js_"):
			expose(target, mdict["name"])

# Remove a single exposed method
func _unexpose(js_name: String) -> void:
	if not OS.has_feature("web"):
		return
	_callbacks.erase(js_name)
	_thunks.erase(js_name)

	JavaScriptBridge.eval("""
		(function(name){
		  if (!window.WebHelper) return;
		  try { delete WebHelper[name]; } catch (_) {}
		  try { if (WebHelper.__raw) delete WebHelper.__raw[name]; } catch (_) {}
		  try { if (WebHelper.__results) delete WebHelper.__results[name]; } catch (_) {}
		})("%s");
	""" % js_name, true)
