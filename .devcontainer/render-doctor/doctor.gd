extends Node3D
## Draws a lit box on a colored background, saves the frame and checks that
## the box pixels (center) differ from the background (corner). A blank or
## uniform frame fails. Exit code 0 = real frame drawn.

const BACKGROUND := Color(0.1, 0.1, 0.4)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3)
	add_child(camera)
	camera.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)

	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.1)
	box.material_override = material
	box.rotation_degrees = Vector3(20, 35, 0)
	add_child(box)

	for i in 5:
		await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var out := "user://frame.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	image.save_png(out)

	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var corner := image.get_pixel(4, 4)
	var drawn := _differs(center, corner)
	print("RENDER_DOCTOR size=%dx%d center=%s corner=%s drawn=%s" % [
		image.get_width(), image.get_height(), center, corner, drawn])
	get_tree().quit(0 if drawn else 2)


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1
