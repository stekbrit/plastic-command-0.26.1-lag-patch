extends Node3D
class_name BattleWorld
const Figure=preload("res://scripts/figure_animation.gd")
const Surfaces=preload("res://scripts/plastic_surfaces.gd")
var surfaces=Surfaces.new()
const Debris=preload("res://scripts/plastic_debris.gd")
var debris
const Soundscape=preload("res://scripts/soundscape.gd")
const Diorama=preload("res://scripts/diorama.gd")
const Districts=preload("res://scripts/battlefield_details.gd")
var district_details
const CivilianView=preload("res://scripts/civilian_view.gd")
var civilian_view
const CharacterMarkers=preload("res://scripts/character_markers.gd")
var character_markers
var soundscape
const CombatFX=preload("res://scripts/combat_fx.gd")
var combat_fx
var city_root
var fade_nodes=[]
var local_team=0
var occlusion_timer=0.0
var sim
var models: Dictionary={}
var actors: Dictionary={}
var selected: Dictionary={}
var gate_leaves: Array=[]
var objective_flags: Array=[]
var shot_nodes: Dictionary={}
var impact_seen: Dictionary={}
var wreck_seen: Dictionary={}
var effect_nodes: Array=[]
var wreck_nodes: Array=[]
var command_markers: Array=[]
var audio_nodes: Array=[]
var audio_cache: Dictionary={}
var sound_clock=0.0
var unit_materials: Dictionary={}
var sun: DirectionalLight3D
var environment: WorldEnvironment
var camera: Camera3D
var audio_listener: AudioListener3D
var team_colors=[Color("427d36"),Color("b49862")]
var ring_material: StandardMaterial3D
var shell_material: StandardMaterial3D
var camera_center=Vector3(64,0,151)
var camera_target=Vector3(64,0,151)
var camera_distance=105.0
var distance_target=105.0
var bearing=.68
var pitch=.66
var desired_bearing=.68
var desired_pitch=.66
var cinematic=false
var direct_camera=false
var remote_client=false
var last_clock=0.0
var visual_clock=0.0
var projectile_meshes={}
var shot_pool=[]
var audio_pool=[]
var burst_pool=[]
const MAX_BURSTS=24
var profile_frames=false
var frame_phases={}
var profile_stamp=0
var high_detail=true
func frame_mark(label: String):
	if profile_frames:
		var now=Time.get_ticks_usec();frame_phases[label]=now-profile_stamp;profile_stamp=now

var track_shader=preload("res://scripts/tank_tracks.gdshader")

func material(color: Color, rough: float=.36, glow: float=0.0) -> StandardMaterial3D:
	var m=StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=rough
	m.metallic_specular=.55
	m.clearcoat_enabled=rough<.55
	m.clearcoat=.6
	m.clearcoat_roughness=.25
	if glow>0:
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled=true
		m.emission=color
		m.emission_energy_multiplier=glow
	return m

func mesh_node(mesh: Mesh, mat: Material, parent: Node3D, position_value: Vector3=Vector3.ZERO) -> MeshInstance3D:
	var n=MeshInstance3D.new()
	n.mesh=mesh
	n.material_override=mat
	n.position=position_value
	parent.add_child(n)
	return n

func box(size: Vector3, mat: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mesh=BoxMesh.new();mesh.size=size
	return mesh_node(mesh,mat,parent,pos)

func label3d(text: String, pos: Vector3, size: float, parent: Node3D, color: Color=Color("ecedd0")) -> Label3D:
	var label=Label3D.new();label.text=text;label.font_size=72;label.pixel_size=size/72;label.modulate=color;label.outline_size=3;label.position=pos
	parent.add_child(label)
	return label

func fetch_model(name: String) -> PackedScene:
	if not models.has(name): models[name]=load("res://assets/models/"+name+".glb")
	return models[name]

func instance_model(name: String, parent: Node3D) -> Node3D:
	var scene=fetch_model(name)
	if scene==null: return Node3D.new()
	var root=scene.instantiate()
	parent.add_child(root)
	var character=sim.types.get(name.get_slice("_",0),{}).get("infantry",false)
	for child in root.find_children("*","MeshInstance3D",true,false):
		child.lod_bias=.45 if name.begins_with("base_decor") else .85 if character else 1.1
		if character and not name.begins_with("commando") and not name.begins_with("swat"):
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if name!="city" and not name.begins_with("base_decor"):surfaces.apply(child,character)
	return root

func build(source, progress: Callable):
	sim=source
	environment=WorldEnvironment.new()
	var env=Environment.new();environment.environment=env
	var sky_material=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("6b97ba")
	sky_material.sky_horizon_color=Color("d5dce1")
	# Warm ground bounce lifts the underside of helmets and equipment while
	# retaining directional sunlight and real building/character shadows.
	sky_material.ground_bottom_color=Color("71664e")
	sky_material.ground_horizon_color=Color("969789")
	sky_material.sun_angle_max=12
	var sky=Sky.new();sky.sky_material=sky_material
	env.sky=sky;env.background_mode=Environment.BG_SKY
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	# Ambient illumination comes entirely from the sky, including ground bounce.
	env.ambient_light_sky_contribution=1.0
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=.94
	env.fog_enabled=true;env.fog_light_color=Color("bcc8c9");env.fog_density=.00022
	# Contact shading should define joints, not darken the whole toy figure.
	env.ssao_enabled=true;env.ssao_radius=.52;env.ssao_intensity=1.10
	env.glow_enabled=true;env.glow_intensity=.32
	add_child(environment)
	sun=DirectionalLight3D.new();sun.light_color=Color("fff7e6");sun.light_energy=1.25;sun.rotation_degrees=Vector3(-52,-35,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=240;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.shadow_bias=.035;sun.shadow_normal_bias=.25;add_child(sun)
	camera=Camera3D.new();camera.fov=40;camera.near=.1;camera.far=1000;camera.current=true;add_child(camera)
	audio_listener=AudioListener3D.new();add_child(audio_listener);audio_listener.make_current()
	make_terrain()
	ring_material=material(Color("deef9b"),.6,1.2)
	shell_material=material(Color("ffb546"),.4,3.0)
	progress.call("Building the city streets",.12)
	await get_tree().process_frame
	city_root=instance_model("city",self)
	for n in city_root.find_children("Building_*","MeshInstance3D",true,false):fade_nodes.append(n)
	for team in [0,1]:
		progress.call("Assembling the "+("green" if team==0 else "sand")+" military base",.2+team*.16)
		await get_tree().process_frame
		var base=instance_model("base_decor_"+str(team),self)
		base.position=Vector3(420 if team else 0,.18,300 if team else 0)
		base.rotation.y=PI if team else 0
		for side in [-1,1]:
			var leaf=instance_model("gate_leaf_"+str(team),self)
			leaf.position=Vector3(sim.gates[team].x,.18,150+side*5)
			gate_leaves.append({"node":leaf,"team":team,"side":side})
		var sign=label3d("GREEN COMMAND" if team==0 else "SAND COMMAND",Vector3(sim.gates[team].x+(.9 if team==0 else -.9),8.7,150),.9,self)
		sign.rotation.y=PI/2 if team==0 else -PI/2
	# Headquarters are the battle objectives; city plazas are ordinary terrain.
	for i in range(sim.units.size()):
		var u=sim.units[i]
		make_actor(u)
		if i%24==0:
			progress.call("Deploying molded-plastic troops and vehicles",.52+i/float(sim.units.size())*.42)
			await get_tree().process_frame
	make_city_signs()
	Diorama.new(self).build()
	district_details=Districts.new();add_child(district_details);district_details.build(self)
	civilian_view=CivilianView.new();add_child(civilian_view);civilian_view.build(self)
	character_markers=CharacterMarkers.new();add_child(character_markers);character_markers.build(self)
	debris=Debris.new();add_child(debris);debris.build(self)
	soundscape=Soundscape.new();soundscape.world=self;add_child(soundscape)
	# Load one-shot resources before play, rather than on the first gunshot.
	for kind in ["rifle","shotgun","gunner","sniper","rocket","cannon","mortar","explosion","impact","step_road","step_sand","reload"]:
		audio_cache[kind]=load("res://assets/audio/"+kind+".wav")
	for kind in ["bullet","heavy"]:
		var projectile=CylinderMesh.new();projectile.top_radius=.017 if kind=="bullet" else .095;projectile.bottom_radius=projectile.top_radius;projectile.height=.8 if kind=="bullet" else .7;projectile.radial_segments=8
		projectile_meshes[kind]=projectile
	combat_fx=CombatFX.new();add_child(combat_fx);combat_fx.build(self)
	for i in range(16):
		var player=AudioStreamPlayer3D.new();player.unit_size=24;player.max_distance=220;add_child(player);audio_pool.append(player)
	for i in range(48):
		var tracer=mesh_node(projectile_meshes.bullet,shell_material,self);tracer.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;tracer.hide();shot_pool.append(tracer)
	for i in range(MAX_BURSTS):burst(Vector3.ZERO,1.0)
	for effect in effect_nodes:effect.root.hide();burst_pool.append(effect)
	effect_nodes.clear();combat_fx.reset()
	for kind in sim.types:
		if not sim.types[kind].get("structure",false):
			debris.get_parts(kind,0);debris.get_parts(kind,1)
			await get_tree().process_frame
	update_camera(1.0)
	# Submit each shared effect mesh behind the loading screen, so first fire
	# does not need to create a material or compile its initial render pipeline.
	var warm_position=camera.position-camera.basis.z*5
	for kind in combat_fx.BUDGET:combat_fx.emit(kind,warm_position,Vector3.ZERO,.02,1,Color.WHITE,camera.basis.z)
	combat_fx.update(0)
	await get_tree().process_frame
	await get_tree().process_frame
	combat_fx.reset()
	progress.call("Ready for your orders",1.0)

func make_terrain():
	var mesh=SurfaceTool.new();mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step=4.0
	for z in range(-60,360,4):
		for x in range(-60,480,4):
			for q in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]:
				var p=Vector2(x,z)+q*step
				mesh.set_uv(p/9)
				mesh.add_vertex(Vector3(p.x,sim.ground_height(p.x,p.y),p.y))
	mesh.generate_normals();mesh.index()
	var sand=ShaderMaterial.new();sand.shader=preload("res://scripts/battlefield_surface.gdshader")
	sand.set_shader_parameter("ground_noise",preload("res://assets/ground_noise.tres"))
	mesh_node(mesh.commit(),sand,self)
	var rock_mat=material(Color("b99a74"),.9)
	var rng=RandomNumberGenerator.new();rng.seed=7331
	var rocks=MultiMesh.new();rocks.transform_format=MultiMesh.TRANSFORM_3D
	var sphere=SphereMesh.new();sphere.radial_segments=8;sphere.rings=4;sphere.radius=1;sphere.height=2;rocks.mesh=sphere;rocks.instance_count=600
	for i in range(600):
		var p=Vector3(rng.randf_range(-30,450),0,rng.randf_range(-30,330))
		if p.x>110 and p.x<310: p.z=-rng.randf_range(6,40) if i%2 else rng.randf_range(305,335)
		if p.x<110 and abs(p.z-150)<85: p.x=-rng.randf_range(4,45)
		if p.x>310 and abs(p.z-150)<85: p.x=rng.randf_range(425,470)
		p.y=sim.ground_height(p.x,p.z)
		var s=rng.randf_range(.12,.75)
		rocks.set_instance_transform(i,Transform3D(Basis.from_euler(Vector3(0,rng.randf()*TAU,0)).scaled(Vector3(s,s*.55,s*.8)),p))
	var gravel=MultiMeshInstance3D.new();gravel.multimesh=rocks;gravel.material_override=rock_mat;add_child(gravel)

func make_objective(index: int):
	var p=sim.points[index]
	var root=Node3D.new();add_child(root);root.position=Vector3(p.x,.35,p.z)
	var pole=CylinderMesh.new();pole.top_radius=.10;pole.bottom_radius=.13;pole.height=9
	mesh_node(pole,material(Color("d4d0b7"),.4),root,Vector3(0,4.5,0))
	var flag=box(Vector3(3,1.6,.07),material(Color("f1dfb8")),root,Vector3(1.5,8,0))
	var marker=label3d(["A · MARKET SQUARE","B · CENTRAL PLAZA","C · WATER TOWERS"][index],Vector3(0,12,0),1.3,root)
	marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.no_depth_test=true
	var ring=TorusMesh.new();ring.inner_radius=4.8;ring.outer_radius=5.1;ring.rings=32;ring.ring_segments=6
	var circle=mesh_node(ring,material(Color("e6dbab"),.5,1),root,Vector3(0,.05,0));circle.scale.y=.07
	objective_flags.append({"flag":flag,"circle":circle})

func make_city_signs():
	for b in sim.data.buildings:
		if b.kind!="shops": continue
		var name=["AL NOOR MARKET","GULF CAFE","PALM PHARMACY","SOUQ STORES"][int(b.variant)%4]
		var label=label3d(name,Vector3(b.x,3.47,b.z+b.d*.5+.34),.50,self,Color("eaf0d4"))
		label.visibility_range_end=120;label.visibility_range_end_margin=12

func make_actor(u: Dictionary):
	var root=Node3D.new();root.name="Unit_"+str(u.id);add_child(root)
	var name=u.type+"_"+str(u.team)
	if u.type=="rifle": name+="_"+(u.pose if u.pose!="" else "standing")
	var regular=sim.types[u.type].get("infantry",false) and not sim.is_playable(u)
	var model_root=Node3D.new() if u.type=="gate" or regular else instance_model(name,root)
	if u.type=="gate" or regular:root.add_child(model_root)
	var info={"root":root,"model":model_root,"legs":[],"rotors":[],"ring":null,"flash":null,"march":null,"rig":{},"march_rig":{},"meshes":[],"recoil":0.0,"crouch":null,"crouch_rig":{}}
	info.rig=rig_for(model_root)
	if info.rig.has("MountedGun"):info.gun_origin_z=info.rig.MountedGun.position.z
	info.meshes=model_root.find_children("*","MeshInstance3D",true,false)
	if regular:
		for mesh in info.meshes:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if u.type=="tank":info.tracks=make_tracks(root,u.team)
	for n in model_root.find_children("*","Node3D",true,false):
		if n.name.begins_with("Leg_"): info.legs.append(n)
		if n.name.begins_with("Rotor_") or n.name=="TailRotor": info.rotors.append(n)
	if not sim.types[u.type].get("structure",false):
		var ring=TorusMesh.new();ring.inner_radius=sim.types[u.type].radius+.18;ring.outer_radius=ring.inner_radius+.10;ring.rings=24;ring.ring_segments=6
		info.ring=mesh_node(ring,ring_material,root,Vector3(0,.13,0));info.ring.scale.y=.07;info.ring.visible=false;info.ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flash=CylinderMesh.new();flash.top_radius=.015;flash.bottom_radius=.13;flash.height=.62;flash.radial_segments=8
		info.flash=mesh_node(flash,shell_material,root,Vector3(0,1.5,1.7));info.flash.visible=false;info.flash.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if u.type in ["jeep","commando","swat"]:
		info.firelight=OmniLight3D.new();info.firelight.light_color=Color("ffb55f");info.firelight.omni_range=4;info.firelight.light_energy=0;root.add_child(info.firelight)
	if u.type in ["tank","jeep"]:info.dust=make_dust(root)
	root.position=Vector3(u.x,sim.ground_height(u.x,u.z)+u.altitude,u.z);root.rotation.y=u.hull_angle if u.type in ["tank","jeep"] else u.angle
	if sim.is_playable(u):info.figure=Figure.new(model_root,info.rig,true)
	if sim.types[u.type].get("infantry",false) and not sim.is_playable(u):
		info.march=instance_model(u.type+"_"+str(u.team)+"_marching",root);info.march.hide();info.march_rig=rig_for(info.march);info.figure=Figure.new(info.march,info.march_rig)
	info.seen_fire=u.last_fire;info.shot_age=100.0
	actors[u.id]=info

func update_camera(dt: float):
	if direct_camera:return
	camera_target.x=clampf(camera_target.x,4,416);camera_target.z=clampf(camera_target.z,4,296)
	camera_center=camera_center.lerp(camera_target,1-exp(-dt*12))
	camera_distance=lerpf(camera_distance,distance_target,1-exp(-dt*10))
	bearing=lerp_angle(bearing,desired_bearing,1-exp(-dt*12));pitch=lerpf(pitch,desired_pitch,1-exp(-dt*10))
	camera.position=camera_center+Vector3(sin(bearing)*cos(pitch),sin(pitch),cos(bearing)*cos(pitch))*camera_distance
	camera.look_at(camera_center)
	if audio_listener!=null:
		audio_listener.position=camera_center+Vector3.UP*12;audio_listener.basis=camera.basis

func ground_at_screen(screen: Vector2, level: float=0.18) -> Vector3:
	var ray=camera.project_ray_normal(screen)
	var from=camera.project_ray_origin(screen)
	if abs(ray.y)<.00001: return camera_target
	var t=(level-from.y)/ray.y
	if t<0: return camera_target
	return from+ray*t

func zoom_at(factor: float,screen: Vector2):
	if not is_finite(factor) or factor<=0:return
	var next=clampf(distance_target*factor,7,540)
	var anchor=ground_at_screen(screen,camera_center.y)
	camera_target+=(anchor-camera_center)*(1-next/distance_target)
	distance_target=next

func pan_drag(from: Vector2,to: Vector2):
	camera_target+=ground_at_screen(from,camera_center.y)-ground_at_screen(to,camera_center.y)
	camera_center=camera_target
	update_camera(1)

func home(team: int):
	camera_target=Vector3(64 if team==0 else 356,0,150);distance_target=105;desired_pitch=.66;desired_bearing=.68 if team==0 else -2.46

func focus(ids: Array):
	var center=Vector3.ZERO;var count=0;var positions=[]
	for id in ids:
		if actors.has(id): center+=actors[id].root.position;positions.append(actors[id].root.position);count+=1
	if count>0:
		camera_target=center/count+Vector3.UP*1.4
		var radius=0.0
		for p in positions:radius=maxf(radius,p.distance_to(center/count))
		distance_target=clampf(18+radius*3.4,18,330)
		desired_pitch=.5

func update_view(dt: float, selection: Array):
	if profile_frames:frame_phases={};profile_stamp=Time.get_ticks_usec()
	# Extrapolate only the cosmetic clock between authoritative 100 ms ticks.
	# Combat, damage, cooldowns and network state continue to use sim.clock.
	if sim.clock!=last_clock:visual_clock=sim.clock;last_clock=sim.clock
	elif not sim.paused:visual_clock=minf(sim.clock+.1,visual_clock+dt)
	var present: Dictionary={}
	for u in sim.units:
		present[u.id]=true
		if not actors.has(u.id):
			if sim.match_rules.enabled():make_actor(u)
			else:continue
		var a=actors[u.id]
		if a.seen_fire!=u.last_fire:
			a.seen_fire=u.last_fire;a.shot_age=0.0 if sim.clock-u.last_fire<=.2 else 100.0
		elif not sim.paused:a.shot_age+=dt
		var authoritative=Vector3(u.x,sim.ground_height(u.x,u.z)+u.altitude,u.z)
		var immediate=u.get("direct",false) and u.team==local_team and not remote_client
		if not a.has("render_to") or immediate or sim.paused or a.root.position.distance_squared_to(authoritative)>36:
			a.render_from=authoritative;a.render_to=authoritative;a.walk_from=u.distance_walked;a.walk_to=u.distance_walked;a.render_tick=sim.clock
		elif a.render_tick!=sim.clock:
			a.render_from=a.render_to;a.render_to=authoritative;a.walk_from=a.walk_to;a.walk_to=u.distance_walked;a.render_tick=sim.clock
		var blend=1.0 if immediate or sim.paused else clampf((visual_clock-sim.clock)/.1,0,1)
		a.root.position=a.render_from.lerp(a.render_to,blend)
		var walk=lerpf(a.walk_from,a.walk_to,blend)
		a.root.visible=sim.tactics.can_see(local_team,u)
		if not a.root.visible:continue
		var cam_d2=camera.global_position.distance_squared_to(a.root.position)
		var on_screen=immediate or camera.is_position_in_frustum(a.root.position+Vector3.UP) or cam_d2<400
		if not on_screen:
			if a.has("dust"):a.dust.emitting=false
			continue
		var hull=u.hull_angle if u.type in ["tank","jeep"] else u.angle
		a.root.rotation.y=hull if immediate else lerp_angle(a.root.rotation.y,hull,1-exp(-dt*14))
		var infantry=sim.types[u.type].get("infantry",false)
		if a.has("dust"):
			a.dust.emitting=u.moving and not sim.paused and cam_d2<3600
			a.dust.speed_scale=0.0 if sim.paused else 1.0
		if u.type=="tank":a.tracks.set_shader_parameter("travel",walk)
		# Regular infantry now keep one articulated figure for every action.
		var using_march=a.march!=null
		var crouched=u.get("crouching",false) and a.crouch!=null
		if a.march!=null:a.march.visible=using_march and not crouched
		a.model.visible=not using_march and not crouched
		if a.crouch!=null:a.crouch.visible=crouched
		var rig=a.crouch_rig if crouched else a.march_rig if using_march else a.rig
		var cycle=walk*(3.2 if sim.is_playable(u) else 4.6)*u.get("stride",1.0)
		var fired=a.shot_age
		var recoil=maxf(0,1-fired*7)
		var animate=immediate or DisplayServer.get_name()=="headless" or cam_d2<900 or camera.is_position_in_frustum(a.root.position+Vector3.UP)
		for key in rig:
			if not animate:break
			if not high_detail and cam_d2>2500 and not immediate:break
			var n=rig[key]
			if u.type=="mortar" or (sim.is_playable(u)) or (infantry and a.has("figure") and using_march):continue
			if key.begins_with("Leg_"):n.rotation.x=sin(cycle+(0 if key.ends_with("L") else PI))*(.20 if u.get("crouching",false) else .45) if u.moving else 0.0
			elif key.begins_with("Shin_"):n.rotation.x=maxf(0,-sin(cycle+(0 if key.ends_with("L") else PI)))*.5 if u.moving else 0.0
			elif key=="Upper":n.rotation.z=sin(cycle)*.045 if u.moving else 0;n.rotation.x=-recoil*.065
			elif key=="Head":n.rotation.y=sin(visual_clock*.7+u.id)*.08 if not u.moving and fired>2 else 0
			elif key=="Turret":n.rotation.y=lerp_angle(n.rotation.y,angle_difference(a.root.rotation.y,u.angle),1-exp(-dt*9));n.position.z=-.2-recoil*.1
			elif key=="GunnerMount":n.rotation.y=lerp_angle(n.rotation.y,angle_difference(a.root.rotation.y,u.angle),1-exp(-dt*14))
			elif key=="MountedGun":n.position.z=a.gun_origin_z-recoil*.085;n.rotation.x=-u.get("aim_pitch",0.0) if u.get("direct",false) else 0.0
			elif key=="TankBarrel":n.rotation.x=-u.get("aim_pitch",0.0) if u.get("direct",false) else 0.0
			elif key=="GunBolt":n.position.z=.18+sin(fired*65)*recoil*.09
			elif key=="GunnerBody":n.position.z=-.36-recoil*.085;n.rotation.x=0;n.rotation.z=0
			elif key.begins_with("Wheel_"):n.rotation.x=-walk/(.48 if u.type=="jeep" else .265)
		if a.has("figure"):
			if not animate:
				a.figure.previous=a.figure.root.global_position;a.figure.feet.clear();a.animation_elapsed=0.0
			elif not sim.paused:
				a.animation_elapsed=a.get("animation_elapsed",0.0)+dt
				var interval=.12 if cam_d2>6400 else .07 if cam_d2>2500 else .033 if cam_d2>900 else 0.0
				if not high_detail and not immediate:interval=maxf(interval,.05)
				if DisplayServer.get_name()=="headless" or immediate:interval=0.0
				if a.animation_elapsed>=interval or a.shot_age==0:
					a.figure.update(a.animation_elapsed,u,sim,visual_clock,a.shot_age);a.animation_elapsed=0.0
		if u.get("direct",false) and a.has("figure") and not sim.paused:
			var step=int(a.figure.phase*2)
			if u.moving and step!=a.get("sound_step",step):play_sound("step_road" if absf(u.z-150)<9 or absf(u.x-210)<8 else "step_sand",a.root.position,-17,"Ambience")
			a.sound_step=step
			if u.reload_time>a.get("sound_reload",0.0):play_sound("reload",a.root.position+Vector3.UP*1.4,-12)
			a.sound_reload=u.reload_time
		if a.ring!=null:
			a.ring.visible=u.id in selection and not u.get("direct",false);a.ring.position.y=.13-u.altitude
			a.flash.visible=fired<.065 and (immediate or cam_d2<3600)
			var muzzle=muzzle_offset(u)
			if u.type in ["tank","jeep"]:
				var pivot=Vector3(0,1.55,-.2) if u.type=="tank" else Vector3(0,2.1,-.36)
				muzzle=pivot+Basis(Vector3.UP,angle_difference(a.root.rotation.y,u.angle))*(muzzle-pivot)
			if sim.is_playable(u) or (u.get("direct",false) and infantry):muzzle=a.root.to_local(sim.muzzle_position(u))
			a.flash.position=muzzle
			if a.flash.visible:
				var direction=Vector3(sin(u.angle)*cos(u.get("aim_pitch",0.0)),sin(u.get("aim_pitch",0.0)),cos(u.angle)*cos(u.get("aim_pitch",0.0)))
				a.flash.quaternion=Quaternion(Vector3.UP,a.root.basis.inverse()*direction)
				var flash_size=3.2 if u.type=="tank" else 1.8 if u.type in ["mortar","bazooka","helicopter"] else 1.25 if u.type in ["swat","jeep"] else .85
				a.flash.scale=Vector3.ONE*flash_size*maxf(.15,1.0-fired*10)
				a.flash.position+=a.root.basis.inverse()*direction*.2*flash_size
			if a.has("firelight"):
				a.firelight.position=muzzle;a.firelight.light_energy=2.2 if fired<.08 else 0
		for rotor in a.rotors:
			if u.launched and not sim.paused:
				if rotor.name=="TailRotor":rotor.rotation.x+=dt*34
				else:rotor.rotation.y+=dt*27
		if u.type=="helicopter" and u.launched:
			a.model.position.y=sin(sim.clock*2+u.id)*.14
			a.model.rotation.x=lerpf(a.model.rotation.x,-.12 if u.moving else 0,dt*4)
			a.model.rotation.z=lerpf(a.model.rotation.z,clampf(angle_difference(a.root.rotation.y,u.angle)*-.4,-.25,.25),dt*4)
		elif infantry and not a.has("figure"):
			var active_model=a.crouch if crouched else a.march if a.march!=null and u.moving else a.model
			active_model.position.y=absf(sin(cycle))*.045 if u.moving else 0

	frame_mark("actors")
	for id in actors.keys():
		if not present.has(id): actors[id].root.queue_free();actors.erase(id)
	for g in gate_leaves:
		g.node.position.z=150+g.side*(5+sim.gates[g.team].open*10.35)
		g.node.visible=not sim.gates[g.team].get("destroyed",false)
	for i in range(objective_flags.size()):
		var p=sim.points[i];var color=team_colors[int(p.owner)] if p.owner>=0 else Color("e6dbab")
		objective_flags[i].flag.material_override.albedo_color=color
		objective_flags[i].flag.rotation.y=sin(sim.clock*2+i)*.11
		objective_flags[i].circle.material_override.albedo_color=color
	frame_mark("gates")
	if civilian_view!=null and (high_detail or Engine.get_process_frames()%2==0):civilian_view.update_view(dt)
	frame_mark("civilians")
	if character_markers!=null:character_markers.update_view()
	frame_mark("markers")
	update_effects(0 if sim.paused else dt)
	frame_mark("effects")
	update_camera(dt)
	frame_mark("camera")
	occlusion_timer-=dt
	if occlusion_timer<=0:
		occlusion_timer=.35;update_occlusion(selection)
	frame_mark("occlusion")

func burst(p: Vector3, size: float):
	if effect_nodes.size()>=MAX_BURSTS:
		var oldest=effect_nodes.pop_front();oldest.root.hide();burst_pool.append(oldest)
	var effect
	if not burst_pool.is_empty():effect=burst_pool.pop_back()
	else:
		var holder=Node3D.new();add_child(holder)
		var light=OmniLight3D.new();light.light_color=Color("ffb46c");light.shadow_enabled=false;holder.add_child(light)
		effect={"root":holder,"age":0.0,"light":light}
	effect.root.position=p;effect.root.show();effect.age=0.0;effect.light.light_energy=3.0;effect.light.omni_range=size*3
	combat_fx.explosion(p,size)
	effect_nodes.append(effect)

func update_effects(dt: float):
	sound_clock=maxf(0,sound_clock-dt)
	for marker in command_markers:
		marker.age+=dt
		marker.node.scale=Vector3.ONE*(1.0+marker.age*.5)
		marker.node.material_override.albedo_color.a=maxf(0,1-marker.age/1.6)
		if marker.age>=1.6:marker.node.queue_free()
	command_markers=command_markers.filter(func(m):return m.age<1.6)
	var live={}
	for s in sim.shots:
		if not sim.tactics.point_visible(local_team,s.a) and s.team!=local_team:continue
		live[s.id]=true
		if not shot_nodes.has(s.id):
			var node=shot_pool.pop_back() if not shot_pool.is_empty() else mesh_node(projectile_meshes.bullet,shell_material,self)
			node.mesh=projectile_meshes.bullet if s.kind=="bullet" else projectile_meshes.heavy;node.scale=Vector3.ONE;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.set_meta("shot_age",-dt);node.set_meta("impact_played",false);node.set_meta("trail_age",0.0)
			if s.get("sound",true):combat_fx.muzzle(s)
			shot_nodes[s.id]=node
			if s.get("sound",true) and not sim.paused and (sound_clock<=0 or sim.lookup.get(s.get("source",-1),{}).get("direct",false)):
				play_sound("shotgun" if s.attacker=="swat" else "gunner" if s.attacker=="jeep" else s.attacker if s.attacker in ["sniper","gunner","mortar"] else "rifle" if s.kind=="bullet" else "rocket" if s.kind=="rocket" else "cannon",s.a,-11 if s.kind=="bullet" else -6,"Weapons",sim.lookup.get(s.get("source",-1),{}).get("direct",false) and s.team==local_team)
				sound_clock=.08
		var n=shot_nodes[s.id]
		n.set_meta("shot_age",float(n.get_meta("shot_age"))+dt)
		var p=sim.shot_position(s,visual_clock);n.position=p
		var direction=(s.b-s.a).normalized()
		if direction.length()>.1: n.quaternion=Quaternion(Vector3.UP,direction)
		n.visible=float(n.get_meta("shot_age"))<.085 if s.kind=="bullet" else not s.done
		if s.kind=="bullet":
			var age=float(n.get_meta("shot_age"));var distance=s.a.distance_to(s.b)
			var tip=minf(distance,maxf(.5,distance*clampf((age+.012)/.06,0,1)))
			var length=minf(tip,2.2 if s.attacker!="swat" else 1.2)
			n.position=s.a+direction*(tip-length*.5);n.scale=Vector3(1,length/.8,1)
			if age>=.035 and not n.get_meta("impact_played"):
				n.set_meta("impact_played",true)
				if sim.tactics.point_visible(local_team,s.b):
					combat_fx.bullet_impact(s)
					if not s.get("impact",{}).is_empty() and s.get("sound",true) and not sim.paused and combat_fx.close_enough(s.b,32):play_sound("impact",s.b,-23)
		else:
			var trail_age=float(n.get_meta("trail_age"))+dt
			if trail_age>=.045 and not s.done:combat_fx.trail(s,p);trail_age=0.0
			n.set_meta("trail_age",trail_age)
	for id in shot_nodes.keys():
		if not live.has(id):shot_nodes[id].hide();shot_pool.append(shot_nodes[id]);shot_nodes.erase(id)
	for impact in sim.impacts:
		if not sim.tactics.point_visible(local_team,impact.p):continue
		if impact_seen.has(impact.id): continue
		impact_seen[impact.id]=sim.clock;burst(impact.p,impact.size*.52)
		if not sim.paused:play_sound("explosion",impact.p,-10)
	for id in impact_seen.keys():
		if sim.clock-impact_seen[id]>10: impact_seen.erase(id)
	for w in sim.wrecks:
		if not sim.tactics.point_visible(local_team,w.p):continue
		if wreck_seen.has(w.id): continue
		wreck_seen[w.id]=true
		if w.type=="gate":continue
		if not sim.types[w.type].get("structure",false):
			if sim.clock-w.at<2.5:debris.explode(w)
			if sim.types[w.type].get("infantry",false) or sim.types[w.type].get("air",false):continue
		var root=Node3D.new();add_child(root);root.position=Vector3(w.p.x,sim.ground_height(w.p.x,w.p.z),w.p.z);root.rotation=Vector3(0,w.angle,.07)
		root.set_meta("wreck_at",w.at)
		wreck_nodes.append(root)
		if sim.types[w.type].get("structure",false):
			var wreck=instance_model(w.type+"_"+str(w.team),root);var charred=material(Color("38392c"),.88)
			for mesh in wreck.find_children("*","MeshInstance3D",true,false):mesh.material_override=charred
		else:debris.make_wreck(w,root)
	if sim.match_rules.enabled():
		for node in wreck_nodes.duplicate():
			if sim.clock-float(node.get_meta("wreck_at",0))>=38:node.queue_free();wreck_nodes.erase(node)
		var retained={}
		for event in sim.wrecks:retained[event.id]=true
		for id in wreck_seen.keys():
			if not retained.has(id):wreck_seen.erase(id)
	if debris!=null:debris.update(dt,sim.paused)
	for effect in effect_nodes:
		effect.age+=dt;effect.light.light_energy=maxf(0,3-effect.age*18)
		if effect.age>2.6:effect.root.hide();burst_pool.append(effect)
	effect_nodes=effect_nodes.filter(func(e):return e.age<=2.6)
	combat_fx.update(dt)

func pick(screen: Vector2, friendly_team: int=-1) -> int:
	var best=-1
	var nearest=INF
	var ray_from=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	for u in sim.units:
		if friendly_team>=0 and u.team!=friendly_team: continue
		if not sim.tactics.can_see(local_team,u):continue
		if friendly_team>=0 and sim.types[u.type].get("structure",false):continue
		var p=Vector3(u.x,sim.ground_height(u.x,u.z)+u.altitude+1.0,u.z)
		if camera.is_position_behind(p):continue
		var delta=p-ray_from
		var along=delta.dot(direction)
		if along<0: continue
		var gap=(ray_from+direction*along).distance_to(p)
		var radius=maxf(.8,sim.types[u.type].radius)
		var screen_gap=camera.unproject_position(p).distance_to(screen)
		if (gap<radius or screen_gap<12) and screen_gap<nearest:
			if sim.obstruction(ray_from,p)>=0: continue
			nearest=screen_gap;best=u.id
	return best

func mark_order(p: Vector3, attack: bool):
	var ring=TorusMesh.new();ring.inner_radius=1.1;ring.outer_radius=1.3;ring.rings=32;ring.ring_segments=6
	var mat=material(Color("ffb16a") if attack else Color("e3f3a3"),.6,1)
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	p.y=sim.ground_height(p.x,p.z)+.2
	var node=mesh_node(ring,mat,self,p);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	command_markers.append({"node":node,"age":0.0})

func play_sound(kind: String, p: Vector3, volume: float, bus: String="Weapons",priority: bool=false):
	for i in range(audio_nodes.size()-1,-1,-1):
		if not audio_nodes[i].playing:audio_pool.append(audio_nodes[i]);audio_nodes.remove_at(i)
	if audio_nodes.size()>=16:
		if not priority:return
		# Keep the possessed weapon audible during a crowded army volley.
		var victim=-1;var farthest=-1.0
		for i in range(audio_nodes.size()):
			var distance=audio_nodes[i].position.distance_squared_to(p)
			if not audio_nodes[i].get_meta("priority",false) and distance>farthest:victim=i;farthest=distance
		if victim<0:return
		var old=audio_nodes[victim];old.stop();audio_nodes.remove_at(victim);audio_pool.append(old)
	if not audio_cache.has(kind):audio_cache[kind]=load("res://assets/audio/"+kind+".wav")
	var player=audio_pool.pop_back();player.stream=audio_cache[kind];player.bus=bus;player.position=p;player.volume_db=volume;player.pitch_scale=randf_range(.92,1.08)
	player.set_meta("priority",priority);player.play();audio_nodes.append(player)

func reset_effects():
	for n in shot_nodes.values():n.hide();shot_pool.append(n)
	for n in wreck_nodes:n.queue_free()
	for n in audio_nodes:
		if is_instance_valid(n):n.stream_paused=false;n.stop();n.stream=null;audio_pool.append(n)
	for e in effect_nodes:e.root.hide();burst_pool.append(e)
	for m in command_markers:m.node.queue_free()
	shot_nodes.clear();wreck_nodes.clear();audio_nodes.clear();effect_nodes.clear();command_markers.clear();impact_seen.clear();wreck_seen.clear();sound_clock=0
	if combat_fx!=null:combat_fx.reset()
	if soundscape!=null:soundscape.reset()
	if debris!=null:debris.reset()

func _exit_tree():
	for n in audio_nodes:
		if is_instance_valid(n):n.stream_paused=false;n.stop();n.stream=null

func rig_for(root: Node3D) -> Dictionary:
	var result={}
	for n in root.find_children("*","Node3D",true,false):
		if str(n.name).begins_with("Leg_") or str(n.name).begins_with("Shin_") or str(n.name).begins_with("Foot_") or str(n.name).begins_with("Forearm_") or str(n.name).begins_with("Hand_") or str(n.name).begins_with("Wheel_") or str(n.name) in ["Upper","Head","Turret","TankBarrel","GunnerMount","GunnerBody","MountedGun","GunBolt","Weapon","Magazine","Arm_L","Arm_R"]:result[str(n.name)]=n
	return result
func muzzle_offset(u: Dictionary) -> Vector3:return sim.muzzle_offset(u)
func update_occlusion(selection: Array):
	var candidates=[]
	for n in fade_nodes:candidates.append(n)
	for u in sim.units:
		if sim.types[u.type].get("structure",false) and actors.has(u.id):candidates.append_array(actors[u.id].meshes)
	var targets=[]
	for id in selection.slice(0,15):
		if actors.has(id):targets.append(actors[id].root.position+Vector3.UP)
	for mesh in candidates:
		var faded=false
		var box_bounds=mesh.get_aabb();var inverse=mesh.global_transform.affine_inverse()
		for target in targets:
			if sim.box_trace(inverse*camera.global_position,inverse*target,box_bounds.position,box_bounds.end)>=0:faded=true;break
		mesh.transparency=.78 if faded else 0.0

func make_tracks(parent: Node3D,team: int) -> ShaderMaterial:
	var belt=MultiMesh.new();belt.transform_format=MultiMesh.TRANSFORM_3D;belt.use_custom_data=true
	var pad=BoxMesh.new();pad.size=Vector3(.64,.075,.135);belt.mesh=pad;belt.instance_count=132
	for i in range(132):
		belt.set_instance_transform(i,Transform3D.IDENTITY)
		belt.set_instance_custom_data(i,Color((i%66)/66.0*9.027433,-1.24 if i<66 else 1.24,0,0))
	belt.custom_aabb=AABB(Vector3(-1.6,0,-2.1),Vector3(3.2,1.05,4.2))
	var mat=ShaderMaterial.new();mat.shader=track_shader;mat.set_shader_parameter("plastic",Color("176225") if team==0 else Color("b39355"))
	var instance=MultiMeshInstance3D.new();instance.multimesh=belt;instance.material_override=mat;parent.add_child(instance)
	return mat

func make_dust(parent: Node3D) -> GPUParticles3D:
	var particles=GPUParticles3D.new();particles.amount=20;particles.lifetime=1.2;particles.local_coords=false;particles.emitting=false;particles.visibility_aabb=AABB(Vector3(-12,-4,-12),Vector3(24,16,24))
	var process=ParticleProcessMaterial.new();process.direction=Vector3(0,.25,-1);process.spread=35;process.gravity=Vector3(0,.55,0);process.initial_velocity_min=.5;process.initial_velocity_max=1.5;process.scale_min=.45;process.scale_max=1.1;particles.process_material=process
	var gradient=Gradient.new();gradient.set_color(0,Color(1,1,1,.26));gradient.set_color(1,Color(1,1,1,0))
	var texture=GradientTexture2D.new();texture.gradient=gradient;texture.fill=GradientTexture2D.FILL_RADIAL;texture.fill_from=Vector2(.5,.5);texture.fill_to=Vector2(1,.5);texture.width=64;texture.height=64
	var mat=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.albedo_color=Color("baa77f");mat.albedo_texture=texture;mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh=QuadMesh.new();mesh.size=Vector2.ONE;mesh.material=mat;particles.draw_pass_1=mesh;particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;particles.position=Vector3(0,.25,-1.8);parent.add_child(particles)
	return particles
