extends Node3D

@export_group("Required References")
@export var sun : DirectionalLight3D
@export var moon : DirectionalLight3D
@export var world_environment : WorldEnvironment
@export var rain_particles : GPUParticles3D

@export_group("Cycle Settings")
@export var day_length_seconds : float = 300.0
@export_range(0, 1) var time_of_day : float = 0.72

@export_group("Cinematic Colors")
@export var sky_top_night   := Color(0.01, 0.02, 0.05)
@export var sky_top_day     := Color(0.15, 0.35, 0.7)
@export var sunset_horizon  := Color(0.95, 0.35, 0.05)
@export var sunset_glow     := Color(1.0,  0.7,  0.2)

@export_group("Rain Settings")
@export var rain_timer  : float = 500.0
@export var next_rain   : float = 200.0

@export_group("Thunder Settings")
@export var thunder_min_interval : float = 8.0
@export var thunder_max_interval : float = 25.0
@export var lightning_flash_energy : float = 6.0
@export var lightning_duration     : float = 0.08

@export_group("Network Settings")
@export var sync_interval : float = 3.0

var _env      : Environment
var _sky_mat  : ProceduralSkyMaterial
var _rain_mat : ParticleProcessMaterial

var _thunder_timer    : float = 0.0
var _next_thunder     : float = 0.0
var _lightning_active : float = 0.0

var _sync_timer  : float = 0.0
var _target_time : float = 0.0

func _ready() -> void:
	if world_environment and world_environment.environment:
		_env = world_environment.environment
		if _env.sky:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial

	if rain_particles:
		_rain_mat = rain_particles.process_material as ParticleProcessMaterial

	if sun:
		sun.sky_mode           = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
		sun.shadow_enabled     = true
		sun.rotation_degrees.y = 20.0

	if moon:
		moon.sky_mode           = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		moon.shadow_enabled     = false
		moon.light_color        = Color(0.55, 0.65, 0.9)
		moon.light_energy       = 0.0
		moon.rotation_degrees.y = 160.0

	_next_thunder = randf_range(thunder_min_interval, thunder_max_interval)
	
	if OS.has_feature("web"):
		apply_web_low_settings()

func apply_web_low_settings():
	sun.shadow_enabled = false
	world_environment.environment.ssr_enabled = false
	Engine.physics_ticks_per_second = 30

func _process(delta: float) -> void:
	if multiplayer.is_server():
		time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
		_update_rain_logic(delta)
		_update_thunder_logic(delta)

		_sync_timer += delta
		if _sync_timer >= sync_interval:
			_sync_timer = 0.0
			_rpc_sync_state.rpc(time_of_day, rain_particles.emitting if rain_particles else false)
	else:
		time_of_day = lerp(time_of_day, _target_time, delta * 2.0)

	_update_visuals(delta)

func _update_visuals(delta: float) -> void:
	if not sun:
		return

	var x_rot = (time_of_day * 360.0) - 90.0
	sun.rotation_degrees.x = x_rot

	var sun_height      = sin(deg_to_rad(x_rot))
	var daylight_factor = clamp(-sun_height, 0.0, 1.0)

	var sunset_influence = clamp(1.0 - abs(sun_height + 0.1), 0.0, 1.0)
	sunset_influence     = pow(sunset_influence, 6.0)

	sun.light_energy = daylight_factor * 1.8
	sun.visible      = sun_height < 0.15
	sun.light_color  = sunset_glow.lerp(Color.WHITE, daylight_factor)

	if moon:
		moon.rotation_degrees.x = x_rot - 180.0

		var moon_height = sun_height - 180
		moon.visible = moon_height > 0.0
		moon.light_energy = clamp(moon_height, 0.0, 1.0) * 1.0

		if moon_height > 0.0:
			sun.visible = false
			moon.visible = true
			moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
			sun.sky_mode  = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		else:
			moon.visible = false
			sun.visible = true
			moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
			sun.sky_mode  = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

	if _sky_mat:
		_sky_mat.sky_top_color = sky_top_night.lerp(sky_top_day, daylight_factor)

		var sunset_mix  = sunset_horizon.lerp(sunset_glow, sunset_influence * 0.5)
		var day_horizon = Color(0.4, 0.6, 0.9).lerp(sunset_mix, sunset_influence)

		_sky_mat.sky_horizon_color    = sky_top_night.lerp(day_horizon, daylight_factor)
		_sky_mat.sky_curve            = lerp(0.15, 0.05, sunset_influence)
		_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color

	if _env:
		_env.background_energy_multiplier = lerp(0.1, 1.5, daylight_factor + sunset_influence * 0.5)
		_env.ambient_light_energy         = lerp(0.05, 0.8, daylight_factor)

	if rain_particles and rain_particles.emitting:
		_env.ambient_light_energy *= 0.6

	if _lightning_active > 0.0:
		_lightning_active -= delta
		sun.visible      = true
		sun.light_energy = lightning_flash_energy
		if _env:
			_env.ambient_light_energy = 1.8
	elif _lightning_active <= 0.0 and sun_height >= 0.15:
		sun.visible = false

	_process_rain_visuals(daylight_factor, sunset_influence)

func _process_rain_visuals(daylight: float, sunset: float) -> void:
	if not _rain_mat:
		return

	var night_rain  = Color(0.1, 0.1, 0.2, 0.4)
	var sunset_rain = sunset_horizon * 1.5
	var day_rain    = Color(0.8, 0.8, 0.9, 0.6)

	var col = night_rain.lerp(day_rain, daylight)
	col     = col.lerp(sunset_rain, sunset)

	_rain_mat.color = col

func _update_rain_logic(delta: float) -> void:
	if not rain_particles:
		return

	rain_timer += delta
	var is_day = time_of_day > 0.22 and time_of_day < 0.78

	if not is_day:
		rain_particles.emitting = false
		return

	if rain_timer >= next_rain:
		rain_timer = 0.0
		rain_particles.emitting = !rain_particles.emitting
		next_rain = randf_range(200.0, 400.0) if rain_particles.emitting else randf_range(400.0, 800.0)

func _update_thunder_logic(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not rain_particles or not rain_particles.emitting:
		return

	_thunder_timer += delta
	if _thunder_timer >= _next_thunder:
		_thunder_timer = 0.0
		_next_thunder  = randf_range(thunder_min_interval, thunder_max_interval)
		_trigger_lightning.rpc()

@rpc("authority", "call_local", "reliable")
func _trigger_lightning() -> void:
	_lightning_active = lightning_duration

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_state(p_time: float, p_raining: bool) -> void:
	_target_time = p_time

	if rain_particles:
		rain_particles.emitting = p_raining
