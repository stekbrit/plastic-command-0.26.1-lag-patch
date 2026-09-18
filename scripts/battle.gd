extends Node3D
const Sim=preload("res://scripts/simulation.gd")
const World=preload("res://scripts/world_view.gd")
const HUD=preload("res://scripts/hud.gd")
const PORT=27888
const PROTOCOL="PLASTIC_NATIVE_20"
const CommandoControl=preload("res://scripts/commando_controller.gd")
var commando_control
var source: Dictionary
var sim
var world
var hud
var team=0
var ready_for_play=false
var started=false
var match_mode="hq"
var selection: Array=[]
var drag_mode="pan"
var attack_mode=false
var formation="spread"
var following=false
var groups: Dictionary={}
var pointer_down=false
var pointer_start=Vector2.ZERO
var pointer_last=Vector2.ZERO
var pointer_dragged=false
var pointer_select=false
var pointer_add=false
var pointer_middle=false
var profile_frames=false
var frame_phases={}
var profile_stamp=0
func frame_mark(label: String):
	if profile_frames:
		var now=Time.get_ticks_usec();frame_phases[label]=now-profile_stamp;profile_stamp=now

var tick_accumulator=0.0
var hud_accumulator=0.0
var net_accumulator=0.0
var network_role=""
var guest_peer=0
var network_ticks=0
var high_quality=true
var network_test_hero="commando"
var test_scope_seen=false
var auto_test=""
var auto_test_elapsed=0.0
var settings={"Master":.8,"Weapons":.8,"Vehicles":.65,"Ambience":.5,"Radio":.8,"sensitivity":1.0,"edge_scroll":false,"character_markers":true,"high_quality":true,"lag_patch":0}
var settings_file="user://settings.cfg"
var camera_presets={}
var pause_before_modal=false
var preview_active=false
var preview_screen=Vector2.ZERO
var preview_path=[]
var preview_slots=[]
var preview_timer=0.0
var connection_state="offline"
var connection_timer=0.0
var last_hover=-1
var screen_shake=0.0
var save_slot="user://quicksave.pcs"

func _ready():
	commando_control=CommandoControl.new(self)
	source=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefield.json"))
	sim=Sim.new(source,true);sim.realtime_direct=true;sim.realtime_planning=true;sim.fog_enabled=false
	var layer=CanvasLayer.new();add_child(layer)
	hud=HUD.new();hud.battle=self;layer.add_child(hud);hud.action.connect(handle_action)
	world=World.new();add_child(world)
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	multiplayer.connected_to_server.connect(connected_to_host)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(server_disconnected)
	var args=OS.get_cmdline_user_args()
	if "--timed-match" in args:match_mode=Sim.MatchRules.TIMED;hud.mode_picker.select(1);hud.refresh_mode_description()
	if "--test-swat" in args:network_test_hero="swat"
	for arg in args:
		if arg.begins_with("--test-unit=") and source.types.has(arg.trim_prefix("--test-unit=")):network_test_hero=arg.trim_prefix("--test-unit=")
	if "--network-test-host" in args or "--network-test-client" in args:
		auto_test="host" if "--network-test-host" in args else "client"
		ready_for_play=true;hud.loading.hide();world.sim=sim
		if auto_test=="host":host_game()
		else:join_game("127.0.0.1")
		return
	await world.build(sim,hud.loading_progress)
	ready_for_play=true;load_settings()
	# 0.26 saved High detail. That preset hitchs in a 104-vs-104 fight, so this
	# patch turns Balanced on once. The quality regression uses a private file.
	if auto_test=="" and settings_file=="user://settings.cfg" and int(settings.get("lag_patch",0))<261:
		settings.high_quality=false;settings.lag_patch=261;apply_settings();save_settings()
		hud.notice("Balanced graphics on to reduce hitching. Click High detail if you want it back.")
	hud.loading.hide();hud.update_hud()
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	if "--quick-start" in args:start_game(true)
	if "--screenshot" in args:
		start_game(false);sim.paused=true;sim.fog_enabled=false;world.camera_target=Vector3(64,1,150);world.distance_target=84;world.camera_center=world.camera_target;world.update_camera(1)

	if "--commando-review" in args:
		start_game(false);sim.fog_enabled=false
		var hero=sim.commando.find_unit(0);hero.x=210;hero.z=110;hero.angle=0;hero.hull_angle=0
		world.actors[hero.id].root.position=Vector3(210,.18,110);world.update_view(.1,[])
		commando_control.toggle();commando_control.yaw=PI if "--front-view" in args else 0
		sim.autonomy[0]=false

func start_game(with_ai: bool):
	if commando_control.active:commando_control.leave()
	commando_control.pending_respawn=-1
	commando_control.awaiting_replacement=false;commando_control.last_kind="";commando_control.last_unit_id=-1;commando_control.switch_bag.clear()
	sim=Sim.new(source,with_ai,match_mode);sim.realtime_direct=true;sim.realtime_planning=true;world.sim=sim
	if auto_test!="" and network_test_hero not in ["commando","swat"]:
		var test_units=sim.units.filter(func(u):return u.team==1 and u.type==network_test_hero).slice(0,2)
		for i in range(test_units.size()):
			var u=test_units[i];u.x=327 if i==0 else 319;u.z=150;u.angle=-PI/2;u.hull_angle=-PI/2;u.erase("exitX")
			if u.type=="helicopter":u.altitude=38;u.launched=true
	selection=[];attack_mode=false;following=false;started=true;team=1 if network_role=="guest" else 0
	world.local_team=team;groups.clear();preview_active=false;sim.fog_enabled=false
	if auto_test=="":
		for id in world.actors:world.actors[id].root.queue_free()
		world.actors.clear()
		for u in sim.units:world.make_actor(u)
		world.reset_effects()
		world.home(team)
		if sim.match_rules.enabled():world.camera_target=Vector3(150 if team==0 else 270,1,150);world.distance_target=75
	select_type("infantry")
	hud.menu.hide();hud.help_panel.hide();hud.settings_panel.hide();hud.result_shown=false;hud.restart_button.visible=true
	hud.menu_title.text="YOUR NEXT BATTLE";hud.refresh_mode_description()
	hud.notice("20 vs 20 · Five minutes · Enemy kills score. Fallen units respawn." if sim.match_rules.enabled() else "90 soldiers, 1 commando, 1 SWAT heavy, 4 tanks, 4 Humvees, 2 mortars and 2 helicopters ready.")

func handle_action(action_name: String, value):
	match action_name:
		"control_selected":commando_control.control_selected()
		"commando":commando_control.toggle()
		"swat":commando_control.toggle("swat")
		"strategy":commando_control.leave()
		"start":disconnect_network();match_mode=hud.selected_match_mode();start_game(true)
		"host":host_game()
		"join":join_game(hud.ip_field.text.strip_edges())
		"quit":get_tree().quit()
		"resume":close_modals()
		"menu":open_modal(hud.menu)
		"help":open_modal(hud.help_panel)
		"close_help":close_modals()
		"settings":open_modal(hud.settings_panel)
		"setting":
			if not settings.has(value.key):return
			settings[value.key]=value.value;apply_settings();save_settings()
		"save":save_game()
		"load":load_game()
		"cover":send_order({"action":"cover","ids":selection.duplicate()})
		"squad":
			selection=[]
			for u in sim.units:
				if u.team==team and not sim.types[u.type].get("structure",false) and int(u.id)%3==int(value):selection.append(u.id)
			if world.soundscape!=null:world.soundscape.acknowledge("select")
		"camera_save":store_camera(int(value))
		"camera_recall":recall_camera(int(value))
		"sound":
			AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0));hud.notice("Sound muted." if AudioServer.is_bus_mute(0) else "Sound enabled.")
		"pause":
			if started and network_role=="":sim.paused=not sim.paused
		"select_all":select_type("all")
		"select_type":select_type(value)
		"formation":formation=value;hud.notice(value.capitalize()+" formation selected.")
		"drag":drag_mode=value;Input.set_default_cursor_shape(Input.CURSOR_DRAG if value=="pan" else Input.CURSOR_CROSS)
		"attack":
			if selection.is_empty():hud.notice("Select troops first.")
			else:attack_mode=not attack_mode
		"stop":send_order({"action":"stop","ids":selection.duplicate()})
		"home":following=false;world.home(team)
		"city":following=false;world.camera_target=Vector3(210,0,150);world.distance_target=260;world.desired_pitch=.9
		"map":following=false;world.camera_target=Vector3(value.x,0,value.y)
		"focus":world.focus(selection)
		"zoom":world.zoom_at(float(value),get_viewport().get_visible_rect().size*.5)
		"quality":
			settings.high_quality=not high_quality;apply_settings();save_settings()
			hud.notice("High detail enabled." if high_quality else "Balanced graphics enabled — better for large battles.")
	if ready_for_play and auto_test=="":hud.update_hud()

func select_type(type: String):
	commando_control.awaiting_replacement=false
	selection=[]
	for u in sim.units:
		if u.team!=team or sim.types[u.type].get("structure",false):continue
		if type=="all" or (type=="infantry" and not sim.is_playable(u) and sim.types[u.type].get("infantry",false)) or u.type==type:selection.append(u.id)
	attack_mode=false
	if auto_test=="" and world.soundscape!=null:world.soundscape.acknowledge("select")

func send_order(order: Dictionary):
	if not started:hud.notice("Deploy your army to begin.");return
	if connection_state=="lost":hud.notice("Connection lost. Start a new battle from Menu.");return
	if network_role=="guest":submit_order.rpc_id(1,order)
	else:
		var error=sim.command(team,order)
		if error!="":hud.notice(error);return
		if order.get("action","")=="squad":hud.notice(sim.combat_director.squad_message(team,order.mode))
	if auto_test=="" and order.get("action","") in ["move","attack"]:
		world.mark_order(Vector3(order.x,0,order.z),order.action=="attack")
		hud.notice(("Attack move" if order.action=="attack" else "Move")+" order issued · "+str(order.ids.size())+" units")
	if auto_test=="" and world.soundscape!=null:world.soundscape.acknowledge("attack" if order.action=="attack" else "order")
	attack_mode=false

func order_at(screen: Vector2, attack: bool=false):
	if selection.is_empty():hud.notice("Select troops first.");return
	var p=world.ground_at_screen(screen)
	var target=world.pick(screen)
	var enemy=sim.lookup.get(target,{})
	if not enemy.is_empty() and enemy.team==team:enemy={}
	var order={"action":"attack" if attack or not enemy.is_empty() else "move","ids":selection.duplicate(),"x":p.x,"z":p.z,"formation":formation,"target":int(enemy.get("id",-1))}
	if not enemy.is_empty():order.x=enemy.x;order.z=enemy.z
	send_order(order)

func _unhandled_input(event: InputEvent):
	if not ready_for_play or auto_test!="" or commando_control.active:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		pointer_down=false;preview_active=false;hud.drag_visible=false;attack_mode=false
		if hud.any_modal():
			if started:close_modals()
		else:open_modal(hud.menu)
		return
	if hud.any_modal():return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			handle_zoom_event(event)
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:preview_active=true;preview_screen=event.position;refresh_preview()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				pointer_down=true;pointer_start=event.position;pointer_last=event.position;pointer_dragged=false;pointer_middle=event.button_index==MOUSE_BUTTON_MIDDLE;pointer_select=not pointer_middle and (drag_mode=="select" or event.shift_pressed);pointer_add=event.shift_pressed
			else:finish_pointer(event.position)
	elif event is InputEventMouseMotion and pointer_down:
		if pointer_start.distance_to(event.position)>6:pointer_dragged=true
		if pointer_dragged:
			if pointer_select:hud.drag_rect=Rect2(pointer_start,event.position-pointer_start).abs();hud.drag_visible=true
			else:following=false;world.pan_drag(pointer_last,event.position)
		pointer_last=event.position
	elif event is InputEventKey and event.pressed and not event.echo:keyboard(event)
	get_viewport().set_input_as_handled()

func finish_pointer(screen: Vector2):
	if not pointer_down:return
	pointer_down=false;hud.drag_visible=false
	if pointer_middle or (pointer_dragged and not pointer_select):return
	if pointer_dragged:
		if not pointer_add:selection.clear()
		var rect=Rect2(pointer_start,screen-pointer_start).abs()
		for u in sim.units:
			if u.team!=team or sim.types[u.type].get("structure",false):continue
			var pos=Vector3(u.x,sim.ground_height(u.x,u.z)+u.altitude+1,u.z)
			if not world.camera.is_position_behind(pos) and rect.has_point(world.camera.unproject_position(pos)) and not u.id in selection:selection.append(u.id)
	elif attack_mode:order_at(screen,true)
	else:
		var id=world.pick(screen,team)
		if not pointer_add:selection.clear()
		if id>=0:
			if id in selection:selection.erase(id)
			else:selection.append(id)
	hud.update_hud()

func handle_zoom_event(event: InputEvent) -> bool:
	if hud.any_modal() or auto_test!="":return false
	var factor=1.0;var at=Vector2.ZERO
	if event is InputEventMagnifyGesture:
		if not is_finite(event.factor) or event.factor<=0:return false
		factor=1.0/event.factor;at=event.position
	elif event is InputEventPanGesture:
		factor=exp(clampf(event.delta.y*.035,-.4,.4));at=event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var amount=event.factor if event.factor>0 else 1.0
		factor=exp(clampf(amount*.13*(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1),-.5,.5));at=event.position
	else:return false
	var bounds=get_viewport().get_visible_rect().size
	if not pointer_down and (at.y<78 or at.y>bounds.y-79 or at.x>bounds.x-252 or hud.map_rect().has_point(at)):return false
	following=false;world.zoom_at(factor,at)
	if preview_active:refresh_preview()
	return true

func _input(event: InputEvent):
	if not ready_for_play:return
	if commando_control.input(event):get_viewport().set_input_as_handled();return
	if commando_control.active:return
	if handle_zoom_event(event):get_viewport().set_input_as_handled();return
	if preview_active:
		if event is InputEventMouseMotion:preview_screen=event.position
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
			preview_active=false;order_at(event.position);get_viewport().set_input_as_handled()
		return
	if not pointer_down:return
	if event is InputEventMouseButton and not event.pressed and event.button_index==(MOUSE_BUTTON_MIDDLE if pointer_middle else MOUSE_BUTTON_LEFT):
		finish_pointer(event.position);get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if pointer_start.distance_to(event.position)>6:pointer_dragged=true
		if pointer_dragged:
			if pointer_select:hud.drag_rect=Rect2(pointer_start,event.position-pointer_start).abs();hud.drag_visible=true
			else:following=false;world.pan_drag(pointer_last,event.position)
		pointer_last=event.position;get_viewport().set_input_as_handled()

func _notification(what: int):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_IN:
		Engine.max_fps=60
		if commando_control!=null:commando_control.focus_changed(true)
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Engine.max_fps=15
		if commando_control!=null:commando_control.focus_changed(false)
		pointer_down=false;preview_active=false
		if hud!=null:hud.drag_visible=false

func keyboard(event: InputEventKey):
	var k=event.keycode
	if k==KEY_G:commando_control.control_selected();return
	if (event.ctrl_pressed or event.meta_pressed) and k==KEY_S:save_game();return
	if (event.ctrl_pressed or event.meta_pressed) and k==KEY_L:load_game();return
	if k>=KEY_F1 and k<=KEY_F3:
		if event.ctrl_pressed or event.meta_pressed:store_camera(k-KEY_F1)
		else:recall_camera(k-KEY_F1)
		return
	if k>=KEY_6 and k<=KEY_9:
		if event.ctrl_pressed or event.meta_pressed:groups[k]=selection.duplicate();hud.notice("Control group "+str(k-KEY_0)+" saved.")
		elif groups.has(k):selection=groups[k].filter(func(id):return sim.lookup.has(id) and sim.lookup[id].hp>0)
	elif k>=KEY_1 and k<=KEY_5:select_type(["infantry","tank","jeep","mortar","helicopter"][k-KEY_1])
	else:
		match k:
			KEY_E:select_type("all")
			KEY_Q:handle_action("attack",null)
			KEY_X:handle_action("stop",null)
			KEY_Z:handle_action("cover",null)
			KEY_H:handle_action("home",null)
			KEY_N:handle_action("city",null)
			KEY_M:following=false;world.camera_target=Vector3(210,0,150);world.distance_target=510;world.desired_pitch=1.1
			KEY_F:world.focus(selection)
			KEY_C:following=not following;hud.notice("Following selection." if following else "Camera released.")
			KEY_V:world.desired_pitch=.44 if world.desired_pitch>.6 else .85
			KEY_BRACKETLEFT:world.desired_bearing-=PI/4
			KEY_BRACKETRIGHT:world.desired_bearing+=PI/4
			KEY_P,KEY_SPACE:handle_action("pause",null)
			KEY_SLASH:handle_action("help",null)

func _process(dt: float):
	if not ready_for_play:return
	if profile_frames:frame_phases={};profile_stamp=Time.get_ticks_usec()
	commando_control.update_input(dt)
	if started and network_role!="guest":sim.step_direct(dt)
	frame_mark("input")
	tick_accumulator+=minf(dt,.15)
	while tick_accumulator>=.1:
		tick_accumulator-=.1
		if started and network_role!="guest":sim.tick(.1)
	frame_mark("simulation")
	# One shared planning allowance per rendered frame, even after two combat
	# ticks. Guests only apply authoritative results; input is handled first.
	if started and network_role!="guest":sim.planning.process_frame(sim.planning.frame_budget(dt))
	frame_mark("planning")
	if network_role=="host" and started:
		net_accumulator+=dt
		if net_accumulator>=.1:
			net_accumulator=0.0
			var snapshot=sim.snapshot()
			if auto_test!="":test_hashes[int(sim.clock*100)]=hash(snapshot.units)
			receive_state.rpc(var_to_bytes(snapshot).compress(FileAccess.COMPRESSION_GZIP))
	if auto_test!="":network_test_step(dt);return
	selection=selection.filter(func(id):return sim.lookup.has(id) and sim.lookup[id].hp>0)
	if not hud.any_modal() and not commando_control.active:
		var horizontal=float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var vertical=float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		if settings.edge_scroll and not pointer_down and not preview_active:
			var mouse=get_viewport().get_mouse_position();var bounds=get_viewport().get_visible_rect().size
			if mouse.x<7:horizontal-=1
			if mouse.x>bounds.x-7:horizontal+=1
			if mouse.y<7:vertical-=1
			if mouse.y>bounds.y-7:vertical+=1
		if horizontal!=0 or vertical!=0:
			following=false
			world.camera_target+=Vector3(cos(world.bearing)*horizontal+sin(world.bearing)*vertical,0,-sin(world.bearing)*horizontal+cos(world.bearing)*vertical)*dt*world.camera_distance*.55*settings.sensitivity
	if following and not selection.is_empty():
		var target=Vector3.ZERO;var count=0
		for id in selection:
			if sim.lookup.has(id):var u=sim.lookup[id];target+=Vector3(u.x,u.altitude,u.z);count+=1
		if count>0:world.camera_target=target/count+Vector3.UP*1.5
	frame_mark("orders")
	world.remote_client=network_role=="guest"
	world.update_view(dt,selection)
	frame_mark("world")
	commando_control.update_camera(dt)
	frame_mark("camera")
	if world.soundscape!=null:world.soundscape.update(dt,team,started and not hud.any_modal())
	frame_mark("audio")
	preview_timer-=dt
	if preview_timer<=0:
		preview_timer=.32
		if preview_active:refresh_preview()
		if not hud.any_modal() and not commando_control.active:last_hover=world.pick(get_viewport().get_mouse_position())
	if network_role=="guest" and not started:
		connection_timer+=dt
		if connection_timer>18:connection_failed()
	frame_mark("hover")
	hud_accumulator+=dt
	if hud_accumulator>.2:hud_accumulator=0;hud.update_hud()
	frame_mark("hud")

func disconnect_network():
	multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();network_role="";guest_peer=0;connection_state="offline";connection_timer=0

func host_game(port: int=PORT):
	disconnect_network()
	match_mode=hud.selected_match_mode()
	var peer=ENetMultiplayerPeer.new();var error=peer.create_server(port,1)
	if error!=OK:hud.network_label.text="Could not host on port "+str(PORT)+". Another match may be using it.";return
	multiplayer.multiplayer_peer=peer;network_role="host";started=false;connection_state="waiting"
	var addresses=[]
	for address in IP.get_local_addresses():
		if ":" not in address and not address.begins_with("127.") and not address.begins_with("169.254."):addresses.append(address)
	hud.network_label.text="Waiting for one player. Host IP: "+", ".join(addresses)+"\nUDP port "+str(PORT)+" · Keep this game open."
	if auto_test!="":print("NATIVE_NET_HOST_READY")

func join_game(address: String,port: int=PORT):
	if address.is_empty():hud.network_label.text="Enter the host IP address.";return
	disconnect_network()
	var peer=ENetMultiplayerPeer.new();var error=peer.create_client(address,port)
	if error!=OK:hud.network_label.text="Could not start a connection. Check the host IP.";return
	multiplayer.multiplayer_peer=peer;network_role="guest";started=false;connection_state="connecting"
	hud.network_label.text="Connecting to "+address+"…"

func peer_connected(id: int):
	if network_role=="host":guest_peer=id

func connected_to_host():hello.rpc_id(1,PROTOCOL)

@rpc("any_peer","call_remote","reliable")
func hello(protocol: String):
	if network_role!="host" or multiplayer.get_remote_sender_id()!=guest_peer:return
	if protocol!=PROTOCOL:multiplayer.multiplayer_peer.disconnect_peer(guest_peer);return
	connection_state="connected"
	begin_match.rpc_id(guest_peer,match_mode)
	start_game(false)

@rpc("authority","call_remote","reliable")
func begin_match(mode: String="hq"):
	match_mode=mode if mode==Sim.MatchRules.TIMED else "hq"
	connection_state="connected";start_game(false)

@rpc("any_peer","call_remote","reliable")
func submit_order(order: Dictionary):
	if network_role!="host" or not started or multiplayer.get_remote_sender_id()!=guest_peer:return
	var error=sim.command(1,order)
	if error!="":receive_notice.rpc_id(guest_peer,error)
	else:
		if auto_test!="":test_commands+=1
		if order.get("action","")=="squad":receive_notice.rpc_id(guest_peer,sim.combat_director.squad_message(1,order.mode))

@rpc("authority","call_remote","reliable",1)
func receive_state(payload: PackedByteArray):
	if network_role!="guest" or not started:return
	var snapshot=bytes_to_var(payload.decompress_dynamic(1048576,FileAccess.COMPRESSION_GZIP))
	if not snapshot is Dictionary:return
	sim.apply_snapshot(snapshot);sim.fog_enabled=false;network_ticks+=1
	if auto_test!="":
		# Several snapshots can arrive before the next rendered frame. Record
		# the received reaction before a later snapshot replaces that brief pose.
		if sim.civilians.people[1].state=="ducking":test_duck_seen=true
		test_ack.rpc_id(1,int(snapshot.clock*100),hash(snapshot.units))

@rpc("authority","call_remote","reliable")
func receive_notice(message: String):hud.notice(message)

func peer_disconnected(id: int):
	if network_role=="host" and id==guest_peer:
		sim.paused=true;connection_state="lost";hud.notice("Opponent disconnected. Open Menu for a new battle.")

func server_disconnected():
	sim.paused=true;connection_state="lost";hud.notice("Host disconnected. Open Menu for a new battle.")
	if not started:hud.network_label.text="Connection ended. Check the host and try again."

func connection_failed():
	disconnect_network();hud.network_label.text="Could not connect. Check the host IP, Wi-Fi and UDP port "+str(PORT)+"."

var test_hashes: Dictionary={}
var test_acks=0
var test_commands=0
var test_sent=false
var test_hero_started=false
var test_controls=0
var test_controlled_id=-1
var test_killed_id=-1
var test_squad_after=3.5
var test_squad_sent=false
var test_squad_fixture_id=-1
var test_control_timer=0.0
var test_civilian_hit=false
var test_duck_triggered=false
var test_duck_seen=false
@rpc("any_peer","call_remote","reliable",2)
func test_ack(at: int, checksum: int):
	if auto_test!="host" or multiplayer.get_remote_sender_id()!=guest_peer:return
	if test_hashes.get(at,-1)==checksum:test_acks+=1

func network_test_step(dt: float):
	if started:
		if auto_test=="host" and auto_test_elapsed>3.3 and not test_duck_triggered:
			test_duck_triggered=true
			var resident=sim.civilians.people[1];resident.x=212;resident.z=110;resident.outside=true;resident.react_after=0
			sim.civilians.on_shot(Vector3(210,1.5,90),Vector3(210,1.5,140))
		if sim.civilians.people[1].state=="ducking":test_duck_seen=true
	auto_test_elapsed+=dt
	if auto_test=="host" and network_test_hero=="sniper":
		var controlled=sim.commando.active_unit(1)
		if not controlled.is_empty() and controlled.get("manual_input",{}).get("aiming",false) and controlled.manual_input.get("scope_zoom",0)==12.0:test_scope_seen=true
	if started and not test_sent:
		test_sent=true
		var army=sim.units.filter(func(u):return u.team==team and u.type=="tank")
		var ids=[]
		for u in army:ids.append(u.id)
		send_order({"action":"move","ids":ids,"x":210,"z":150})
	if auto_test=="host" and started and auto_test_elapsed>4 and not test_civilian_hit:
		test_civilian_hit=true
		var resident=sim.civilians.people[0];resident.outside=true
		sim.civilians.damage(resident,1000,"rifle")
	if auto_test=="host" and started and auto_test_elapsed>2.5:
		var leader=sim.commando.active_unit(1)
		if not leader.is_empty() and leader.id!=test_squad_fixture_id:
			# A replacement fast vehicle may be far from the original squad.
			# Set up nearby recruits for each possession; normal play never moves them.
			test_squad_fixture_id=leader.id
			var nearby=sim.units.filter(func(u):return u.team==1 and u.type=="rifle" and u.id!=leader.id).slice(0,4)
			for i in range(nearby.size()):nearby[i].x=leader.x-3-i;nearby[i].z=leader.z+3;nearby[i].path=[]
	if auto_test=="client" and started and auto_test_elapsed>test_squad_after and not test_squad_sent:
		test_squad_sent=true;send_order({"action":"squad","mode":"hold"})
	if auto_test=="host" and started and network_test_hero not in ["commando","swat"] and auto_test_elapsed>6.5 and test_killed_id<0:
		var unit=sim.commando.active_unit(1)
		if not unit.is_empty():
			test_killed_id=unit.id;unit.hp=0
			if network_test_hero=="sniper":
				# The roster has one sniper. Exercise a cross-role replacement
				# from the same clear test lane after that last sniper dies.
				var reserve=sim.commando.find_unit(1,"rifle")
				reserve.x=319;reserve.z=150;reserve.angle=-PI/2;reserve.hull_angle=-PI/2;reserve.path=[];reserve.target=-1
	test_control_timer-=dt
	if auto_test=="client" and started and auto_test_elapsed>2 and test_control_timer<=0:
		test_control_timer=.05
		var hero=sim.commando.find_unit(1,network_test_hero)
		if hero.is_empty():hero=sim.commando.find_unit(1,"rifle")
		if not hero.is_empty() and hero.id!=test_controlled_id:
			test_hero_started=true;test_controlled_id=hero.id;set_commando_mode(true,hero.type,hero.id);test_squad_sent=false;test_squad_after=maxf(3.5,auto_test_elapsed+.6)
		if not hero.is_empty():send_commando_input({"unit_id":hero.id,"move":Vector2(0,1),"yaw":-PI/2,"pitch":0.0,"aim":Vector3(hero.x-30,1.5,hero.z),"fire":true,"crouch":false,"sprint":false,"lean":0.0,"reload":false,"aiming":network_test_hero=="sniper","scope_zoom":12.0})
	if auto_test_elapsed>12:
		var hero=sim.commando.find_unit(1,network_test_hero)
		if hero.is_empty():hero=sim.commando.find_unit(1,"rifle")
		var direct_ok=not hero.is_empty() and hero.direct and hero.x<315 and sim.autonomy[1] and hero.last_fire>=0
		var switch_ok=network_test_hero in ["commando","swat"] or (sim.units.filter(func(u):return u.team==1 and sim.can_control(u)).size()==103 and (test_killed_id<0 or not sim.lookup.has(test_killed_id)))
		direct_ok=direct_ok and switch_ok
		print("UNIT_SWITCH_NETWORK ","PASS" if switch_ok else "FAIL"," unit=",network_test_hero)
		var civilian_ok=sim.civilians.people.size()==36 and sim.civilians.people[0].hp==0 and sim.civilians.people.any(func(c):return c.distance_walked>0)
		var passed=(test_acks>20 and test_commands>0 and test_controls>20 and direct_ok) if auto_test=="host" else (network_ticks>20 and started and direct_ok)
		var revealed=not sim.fog_enabled and sim.units.all(func(u):return sim.tactics.can_see(team,u))
		passed=passed and revealed
		print("OPEN_BATTLEFIELD_NETWORK ","PASS" if revealed else "FAIL")
		var squad=sim.combat_director.members(1)
		var squad_ok=not squad.is_empty() and squad.all(func(u):return u.squad_order=="hold" and u.squad_leader==hero.id and u.team==1)
		if auto_test=="host" and network_test_hero=="sniper":
			print("SCOPE_NETWORK ","PASS" if test_scope_seen else "FAIL");passed=passed and test_scope_seen
		passed=passed and civilian_ok and squad_ok and test_duck_seen
		print("CIVILIAN_DUCK_NETWORK ","PASS" if test_duck_seen else "FAIL")
		print("SQUAD_NETWORK ","PASS" if squad_ok else "FAIL"," members=",squad.size())
		print("CIVILIAN_NETWORK ","PASS" if civilian_ok else "FAIL"," residents=",sim.civilians.people.size()," casualty=",sim.civilians.people[0].hp)
		print("NATIVE_NET_",auto_test.to_upper()," ","PASS" if passed else "FAIL"," frames=",network_ticks," acks=",test_acks," commands=",test_commands," direct_controls=",test_controls," hero=",network_test_hero," hero_x=",hero.get("x",-1))
		get_tree().quit(0 if passed else 1)

func open_modal(panel: Control):
	if commando_control.active:commando_control.leave()
	if not hud.any_modal():pause_before_modal=sim.paused
	if started and network_role=="":sim.paused=true
	hud.menu.hide();hud.help_panel.hide();hud.settings_panel.hide();panel.show();pointer_down=false;preview_active=false
func close_modals():
	hud.menu.hide();hud.help_panel.hide();hud.settings_panel.hide()
	if network_role=="":sim.paused=pause_before_modal
func apply_settings():
	high_quality=bool(settings.high_quality)
	get_viewport().msaa_3d=Viewport.MSAA_4X if high_quality else Viewport.MSAA_2X
	get_viewport().scaling_3d_scale=1.0 if high_quality else .8
	if world!=null and world.sun!=null:
		world.sun.directional_shadow_max_distance=240 if high_quality else 150
		world.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high_quality else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if world!=null and world.environment!=null:
		world.environment.environment.ssao_enabled=high_quality
		world.environment.environment.glow_enabled=high_quality
	if world!=null:world.high_detail=high_quality
	if world!=null and world.character_markers!=null:world.character_markers.visible=bool(settings.character_markers)
	if world!=null and world.soundscape!=null:
		for bus in ["Master","Weapons","Vehicles","Ambience","Radio"]:world.soundscape.set_volume(bus,float(settings[bus]))
	sim.fog_enabled=false
func load_settings():
	var config=ConfigFile.new()
	if config.load(settings_file)==OK:
		for key in settings:settings[key]=config.get_value("settings",key,settings[key])
		camera_presets=config.get_value("camera","presets",{})
	apply_settings();hud.sync_settings()
func save_settings():
	var config=ConfigFile.new()
	for key in settings:config.set_value("settings",key,settings[key])
	config.set_value("camera","presets",camera_presets);config.save(settings_file)
func store_camera(index: int):
	camera_presets[index]={"center":world.camera_target,"distance":world.distance_target,"pitch":world.desired_pitch,"bearing":world.desired_bearing};save_settings();hud.notice("Camera position "+str(index+1)+" saved. Press F"+str(index+1)+" to return.")
func recall_camera(index: int):
	if not camera_presets.has(index):hud.notice("Save this view with Ctrl/Cmd + F"+str(index+1)+".");return
	var p=camera_presets[index];following=false;world.camera_target=p.center;world.distance_target=p.distance;world.desired_pitch=p.pitch;world.desired_bearing=p.bearing
func save_game():
	if not started or network_role!="":hud.notice("Saving is available during solo skirmishes.");return
	var state=sim.save_state();state.paused=pause_before_modal if hud.any_modal() else sim.paused
	var payload={"version":state.version,"simulation":state,"selection":selection.duplicate(),"groups":groups.duplicate(true),"camera":{"center":world.camera_target,"distance":world.distance_target,"pitch":world.desired_pitch,"bearing":world.desired_bearing}}
	var file=FileAccess.open(save_slot+".tmp",FileAccess.WRITE)
	if file==null:hud.notice("Could not write the save file.");return
	file.store_var(payload);file.close()
	var result=DirAccess.rename_absolute(save_slot+".tmp",save_slot)
	hud.notice("Skirmish saved. Ctrl/Cmd + L restores it." if result==OK else "Could not finish saving the game.")
func load_game():
	commando_control.pending_respawn=-1
	if commando_control.active:commando_control.leave()
	if network_role!="":hud.notice("Leave multiplayer before loading a solo save.");return
	if not FileAccess.file_exists(save_slot):hud.notice("No saved skirmish yet.");return
	var file=FileAccess.open(save_slot,FileAccess.READ)
	if file==null:hud.notice("Could not open the save file.");return
	var payload=file.get_var(false);file.close()
	if not payload is Dictionary or payload.get("version",0) not in [5,6]:hud.notice("This save is not compatible with this edition.");return
	if not payload.get("simulation") is Dictionary or not payload.get("selection") is Array or not payload.get("groups") is Dictionary or not payload.get("camera") is Dictionary:hud.notice("This save is incomplete.");return
	var camera_state=payload.camera
	if not camera_state.get("center") is Vector3 or not camera_state.has_all(["distance","pitch","bearing"]):hud.notice("This save is incomplete.");return
	var restored=Sim.new(source,false);restored.realtime_planning=true
	if not restored.load_state(payload.simulation):hud.notice("The save could not be restored.");return
	restored.fog_enabled=false;restored.tactics.update_vision()
	match_mode=restored.match_rules.mode
	sim=restored;sim.realtime_direct=true;sim.realtime_planning=true;world.sim=sim;team=0;world.local_team=0;started=true;following=false
	world.reset_effects()
	for actor in world.actors.values():actor.root.queue_free()
	world.actors.clear()
	for u in sim.units:world.make_actor(u)
	selection=payload.selection.filter(func(id):return sim.lookup.has(id));groups=payload.groups
	var c=payload.camera;world.camera_target=c.center;world.distance_target=c.distance;world.desired_pitch=c.pitch;world.desired_bearing=c.bearing
	hud.menu.hide();hud.help_panel.hide();hud.settings_panel.hide();hud.result_shown=false;hud.restart_button.show();hud.notice("Skirmish restored.")
func refresh_preview():
	preview_path=[];preview_slots=[]
	if selection.is_empty():return
	var p=world.ground_at_screen(preview_screen);var dest=Vector2(p.x,p.z)
	for infantry in [true,false]:
		var group=selection.filter(func(id):return sim.lookup.has(id) and bool(sim.types[sim.lookup[id].type].get("infantry",false))==infantry)
		for i in range(group.size()):
			var at=dest+sim.formation_offset(i,group.size(),infantry,formation)
			preview_slots.append({"p":Vector3(at.x,.5,at.y),"clear":sim.types[sim.lookup[group[i]].type].get("air",false) or sim.passable(at,team,true,sim.collision_radius(sim.lookup[group[i]]))})
	var lead=sim.lookup.get(selection[0],{})
	if not lead.is_empty():
		preview_path.append(Vector3(lead.x,.6,lead.z))
		for waypoint in sim.path(lead,dest):preview_path.append(Vector3(waypoint.x,.6,waypoint.y))

func set_commando_mode(active: bool,kind: String="commando",requested_id: int=-1):
	if network_role=="guest":
		if connection_state=="connected" and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:request_commando_mode.rpc_id(1,active,kind,requested_id)
	else:sim.commando.activate(team,active,kind,requested_id)
func send_commando_input(state: Dictionary):
	if network_role=="guest":
		if connection_state=="connected" and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:request_commando_input.rpc_id(1,state)
	else:sim.commando.submit(team,state)
@rpc("any_peer","call_remote","reliable",3)
func request_commando_mode(active: bool,kind: String="commando",requested_id: int=-1):
	if network_role=="host" and started and multiplayer.get_remote_sender_id()==guest_peer:sim.commando.activate(1,active,kind,requested_id)
@rpc("any_peer","call_remote","unreliable_ordered",4)
func request_commando_input(state: Dictionary):
	if network_role=="host" and started and multiplayer.get_remote_sender_id()==guest_peer:
		sim.commando.submit(1,state)
		if auto_test!="":test_controls+=1
