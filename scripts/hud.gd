extends Control
class_name BattleHUD
signal action(name: String, value)
var battle
var settings_panel: PanelContainer
var settings_widgets={}
var squad_buttons=[]
var feedback_label: Label
var quality_button: Button
var title_label: Label
var status_label: Label
var count_label: Label
var selected_label: Label
var notice_label: Label
var clock_label: Label
var mode_picker: OptionButton
var score_panel: PanelContainer
var score_label: Label
var respawn_label: Label
var gate_label: Label
var hq_label: Label
var role_buttons: Dictionary={}
var infantry_buttons: Dictionary={}
var drag_buttons: Dictionary={}
var menu: PanelContainer
var menu_title: Label
var menu_description: Label
var ip_field: LineEdit
var loading: Control
var loading_label: Label
var loading_bar: ProgressBar
var network_label: Label
var minimap_area: Control
var scope_mask: ColorRect
var direct_panel
var control_button
var next_unit_button
var direct_movement
var direct_squad
var direct_status
var swat_button
var commando_button
var drag_rect=Rect2()
var drag_visible=false
var notice_remaining=0.0
var help_panel: PanelContainer
var result_shown=false
var weapon_feedback_style: StyleBoxFlat
const HIT_FEEDBACK_TIME=.25
var restart_button: Button
const INK=Color("1c332b")
const PAPER=Color("e5ebbd")
const MUTED=Color("a8bba0")

func panel_style(color: Color, border: Color=Color("526348"), radius: int=8) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color;s.border_color=border;s.set_border_width_all(1);s.set_corner_radius_all(radius);s.content_margin_left=16;s.content_margin_right=16;s.content_margin_top=12;s.content_margin_bottom=12;return s

func label(text: String, size_value: int, color: Color=PAPER) -> Label:
	var n=Label.new();n.text=text;n.add_theme_font_size_override("font_size",size_value);n.add_theme_color_override("font_color",color);return n

func button(text: String, call: String, value=null) -> Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=36;b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;b.add_theme_font_size_override("font_size",13)
	b.add_theme_color_override("font_color",PAPER);b.add_theme_color_override("font_hover_color",Color.WHITE)
	b.add_theme_stylebox_override("normal",panel_style(Color("304a36")))
	b.add_theme_stylebox_override("hover",panel_style(Color("486142"),Color("bdce87")))
	b.add_theme_stylebox_override("pressed",panel_style(Color("627643"),PAPER))
	b.add_theme_stylebox_override("focus",panel_style(Color(0,0,0,0),PAPER))
	for state in ["normal","hover","pressed","focus"]:
		var style=b.get_theme_stylebox(state).duplicate();style.content_margin_top=5;style.content_margin_bottom=5;b.add_theme_stylebox_override(state,style)
	b.pressed.connect(func():action.emit(call,value))
	return b

func unit_icon(b: Button,category: String,small: bool=false):
	b.icon=load("res://assets/icons/"+category+".svg");b.expand_icon=true;b.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_max_width",18 if small else 28)
	b.add_theme_constant_override("h_separation",4 if small else 10)
	for state in ["normal","hover","pressed","focus"]:
		var style=b.get_theme_stylebox(state).duplicate();style.content_margin_left=7 if small else 10;style.content_margin_right=7;b.add_theme_stylebox_override(state,style)

func place(node: Control, rect: Rect2):
	node.position=rect.position;node.size=rect.size

func _ready():
	weapon_feedback_style=panel_style(Color("14231de8"),Color("9d8960"),4)
	scope_mask=ColorRect.new();scope_mask.mouse_filter=Control.MOUSE_FILTER_IGNORE;scope_mask.z_index=-1;add_child(scope_mask);scope_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope_mask.material=ShaderMaterial.new();scope_mask.material.shader=preload("res://scripts/sniper_scope.gdshader");scope_mask.hide()
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top=Panel.new();top.name="Top";top.add_theme_stylebox_override("panel",panel_style(INK,Color("41543c"),0));add_child(top);top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);top.offset_bottom=78
	title_label=label("★  PLASTIC COMMAND",25);top.add_child(title_label);title_label.position=Vector2(22,12)
	var sub=label("GULF CROSSING  /  TIMED BATTLE · 0.26.1",10,MUTED);top.add_child(sub);sub.position=Vector2(24,47)
	clock_label=label("00:00",25);top.add_child(clock_label);clock_label.position=Vector2(360,13)
	status_label=label("BATTLE READY",10,MUTED);top.add_child(status_label);status_label.position=Vector2(360,46)
	var tools=HBoxContainer.new();top.add_child(tools);tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);tools.offset_left=-590;tools.offset_right=-16;tools.offset_top=19;tools.add_theme_constant_override("separation",7)
	for item in [["High detail","quality"],["Settings","settings"],["Pause [P]","pause"],["Controls [?]","help"],["Menu","menu"]]:
		var b=button(item[0],item[1]);tools.add_child(b)
		if item[1]=="quality":quality_button=b
	var side=PanelContainer.new();side.name="Side";add_child(side);side.add_theme_stylebox_override("panel",panel_style(INK,Color("41543c"),0));side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE);side.offset_left=-252;side.offset_top=78;side.offset_bottom=-79
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side.add_child(scroll)
	var list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list);list.add_theme_constant_override("separation",3)
	list.add_child(label("YOUR STARTING ARMY",10,MUTED))
	count_label=label("104 / 104",28);list.add_child(count_label)
	gate_label=label("GREEN ARMY · GATE CLOSED",10,MUTED);list.add_child(gate_label)
	control_button=button("Control selected [G]","control_selected");control_button.add_theme_font_size_override("font_size",12);list.add_child(control_button)
	var line=HSeparator.new();list.add_child(line)
	for row in [["infantry","Toy soldiers",90],["tank","Battle tanks",4],["jeep","Humvees",4],["mortar","Mortar crews",2],["helicopter","Helicopters",2]]:
		var b=button(row[1]+"    "+str(row[2]),"select_type",row[0]);b.custom_minimum_size.y=32;unit_icon(b,row[0]);list.add_child(b);role_buttons[row[0]]=b
	commando_button=button("Select commando","select_type","commando");commando_button.custom_minimum_size.y=32;unit_icon(commando_button,"commando",true);list.add_child(commando_button)
	swat_button=button("Select SWAT","select_type","swat");swat_button.custom_minimum_size.y=32;unit_icon(swat_button,"swat",true);list.add_child(swat_button)
	var grid=GridContainer.new();grid.columns=2;list.add_child(grid)
	for row in [["rifle","Riflemen"],["bazooka","Bazookas"],["gunner","Machine guns"],["sniper","Snipers"],["radio","Radio"],["officer","Officers"]]:
		var b=button(row[1],"select_type",row[0]);b.add_theme_font_size_override("font_size",10);b.custom_minimum_size=Vector2(100,28);unit_icon(b,row[0],true);grid.add_child(b)
		infantry_buttons[row[0]]=b
	list.add_child(label("SQUADS",10,MUTED))
	var squads=HBoxContainer.new();list.add_child(squads)
	for i in range(3):
		var b=button(["A","B","C"][i]+" · 35","squad",i);b.add_theme_font_size_override("font_size",11);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;squads.add_child(b);squad_buttons.append(b)
	list.add_child(label("FORMATION",10,MUTED))
	var formations=HBoxContainer.new();list.add_child(formations)
	for f in ["compact","line","spread"]:
		var b=button(f.capitalize(),"formation",f);b.add_theme_font_size_override("font_size",10);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;formations.add_child(b)
	var spacer=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;list.add_child(spacer)
	hq_label=label("PROTECT YOUR HQ\nDESTROY ENEMY HQ",12);list.add_child(hq_label)
	list.add_child(button("Take cover [Z]","cover"))
	var bottom=Panel.new();bottom.name="Bottom";add_child(bottom);bottom.add_theme_stylebox_override("panel",panel_style(INK,Color("41543c"),0));bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);bottom.offset_top=-79
	selected_label=label("Select your troops",18);bottom.add_child(selected_label);selected_label.position=Vector2(24,13)
	feedback_label=label("DRAG map · SHIFT+DRAG select · HOLD RIGHT CLICK preview",10,MUTED);bottom.add_child(feedback_label);feedback_label.position=Vector2(24,44)
	var orders=HBoxContainer.new();bottom.add_child(orders);orders.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);orders.offset_left=-532;orders.offset_right=-20;orders.offset_top=18;orders.add_theme_constant_override("separation",7)
	for row in [["Select army [E]","select_all"],["Attack move [Q]","attack"],["Hold [X]","stop"],["Focus [F]","focus"]]:orders.add_child(button(row[0],row[1]))
	var navigation=HBoxContainer.new();add_child(navigation);navigation.name="Navigation";navigation.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);navigation.offset_top=-131;navigation.offset_bottom=-90;navigation.offset_left=-773;navigation.offset_right=-265;navigation.add_theme_constant_override("separation",5)
	for row in [["✥ Drag map","drag","pan"],["▧ Box select","drag","select"],["Base [H]","home",""],["City [N]","city",""],["−","zoom",1.2],["+","zoom",.82]]:
		var b=button(row[0],row[1],row[2]);b.add_theme_font_size_override("font_size",11);navigation.add_child(b)
		if row[1]=="drag":drag_buttons[row[2]]=b
	minimap_area=Control.new();minimap_area.mouse_filter=Control.MOUSE_FILTER_STOP;minimap_area.gui_input.connect(_map_input);add_child(minimap_area)
	notice_label=label("",15);notice_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;notice_label.add_theme_color_override("font_shadow_color",Color.BLACK);notice_label.add_theme_constant_override("shadow_offset_x",1);notice_label.add_theme_constant_override("shadow_offset_y",2);add_child(notice_label);notice_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);notice_label.offset_top=92;notice_label.offset_left=270;notice_label.offset_right=-265
	notice_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	score_panel=PanelContainer.new();score_panel.name="MatchScore";add_child(score_panel)
	score_panel.add_theme_stylebox_override("panel",panel_style(INK,Color("8fa767"),6))
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_panel.offset_left=-178;score_panel.offset_right=178;score_panel.offset_top=88;score_panel.offset_bottom=153
	score_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var scores=VBoxContainer.new();score_panel.add_child(scores)
	score_label=label("GREEN  0 : 0  SAND",21);score_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;scores.add_child(score_label)
	respawn_label=label("20 vs 20 · Five-minute team deathmatch",11,MUTED);respawn_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;scores.add_child(respawn_label)
	score_panel.hide()
	make_menu();make_help();make_settings();make_loading();make_direct_panel()
	resized.connect(func():place(minimap_area,map_rect()))
	call_deferred("layout_map")

func layout_map():place(minimap_area,map_rect())
func map_rect() -> Rect2:return Rect2(22,size.y-(294 if battle.commando_control.active else 268),230,164)

func make_menu():
	menu=PanelContainer.new();menu.add_theme_stylebox_override("panel",panel_style(Color("20392cf5"),Color("8fa767"),12));add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER);menu.offset_left=-290;menu.offset_right=290;menu.offset_top=-280;menu.offset_bottom=280
	var content=VBoxContainer.new();content.add_theme_constant_override("separation",10);menu.add_child(content)
	content.add_child(label("OPERATION  /  GULF CROSSING",12,MUTED))
	menu_title=label("CHOOSE YOUR BATTLE",28);content.add_child(menu_title)
	menu_description=label("A city of molded plastic and desert sand.\n104 units per army. One chance to command them.",14);content.add_child(menu_description)
	mode_picker=OptionButton.new();mode_picker.custom_minimum_size.y=38
	mode_picker.add_item("Headquarters assault · Fixed armies",0)
	mode_picker.add_item("20 vs 20 · 5-minute respawn match",1)
	mode_picker.tooltip_text="Choose your solo match or the match you host. LAN guests use the host’s choice."
	mode_picker.item_selected.connect(func(_index):refresh_mode_description())
	content.add_child(mode_picker);refresh_mode_description()
	content.add_child(button("DEPLOY · SOLO SKIRMISH","start"))
	var row=HBoxContainer.new();content.add_child(row);row.add_theme_constant_override("separation",10)
	var host=button("Host LAN battle","host");host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(host)
	var join=button("Join LAN battle","join");join.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(join)
	ip_field=LineEdit.new();ip_field.placeholder_text="Host IP address — e.g. 192.168.1.10";ip_field.text="127.0.0.1";ip_field.custom_minimum_size.y=36;content.add_child(ip_field)
	network_label=label("Same Wi-Fi: one player hosts, one joins using the host IP.\nInternet play needs UDP port 27888 reachable on the host.",11,MUTED);content.add_child(network_label)
	restart_button=button("Return to battle","resume");restart_button.visible=false;content.add_child(restart_button)
	var saves=HBoxContainer.new();content.add_child(saves)
	for item in [["Save skirmish","save"],["Load skirmish","load"]]:
		var b=button(item[0],item[1]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;saves.add_child(b)
	content.add_child(button("Quit game","quit"))

func selected_match_mode() -> String:
	return "timed_20v20" if mode_picker!=null and mode_picker.selected==1 else "hq"
func refresh_mode_description():
	menu_description.text="2 tanks · 2 Humvees · 1 commando · 15 soldiers per team\n5 minutes · Kills score · Respawn: troops 5s / vehicles 12s" if selected_match_mode()=="timed_20v20" else "104 units per army · No respawns\nDestroy the enemy headquarters to win."

func make_loading():
	loading=ColorRect.new();loading.color=Color("182e25");add_child(loading);loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box_container=VBoxContainer.new();loading.add_child(box_container);box_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER);box_container.offset_left=-260;box_container.offset_right=260;box_container.offset_top=-70;box_container.offset_bottom=70;box_container.add_theme_constant_override("separation",16)
	box_container.add_child(label("★  PLASTIC COMMAND",31))
	loading_label=label("Preparing the native battlefield…",14,MUTED);box_container.add_child(loading_label)
	loading_bar=ProgressBar.new();loading_bar.custom_minimum_size.y=7;loading_bar.show_percentage=false;box_container.add_child(loading_bar)

func loading_progress(text: String, percent: float):
	loading_label.text=text;loading_bar.value=percent*100

func make_help():
	help_panel=PanelContainer.new();add_child(help_panel);help_panel.add_theme_stylebox_override("panel",panel_style(INK,PAPER,12));help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);help_panel.offset_left=-330;help_panel.offset_right=330;help_panel.offset_top=-315;help_panel.offset_bottom=315
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",12);help_panel.add_child(column)
	column.add_child(label("FIELD MANUAL",28))
	var text=RichTextLabel.new();text.bbcode_enabled=true;text.fit_content=false;text.custom_minimum_size=Vector2(620,490);text.add_theme_font_size_override("normal_font_size",14)
	text.text="[b]CAMERA[/b]\nLeft drag moves the map. Middle drag also pans. Wheel, two-finger scroll or pinch zooms.\nYou can zoom while dragging. WASD / arrows pan. [ and ] rotate. V changes camera angle.\nH returns to base. N frames the city. M shows the whole map.\nF focuses your selection. C follows selected troops.\n\n[b]PLAYABLE CHARACTERS[/b]\nSelect any friendly mobile unit, then Control selected / G to play it.\nUse a type button, then G; G again switches among all surviving soldiers and vehicles.\nAfter a death, Control next / G takes another survivor. HQ assault has no replacements; timed matches respawn lost units.\nHold Alt to use HUD buttons; Tab returns to strategy.\nCommando and SWAT use the same selection and G control.\nTab / Esc returns to strategy. G with no selection picks a survivor.\nWASD moves. Mouse looks. Left click fires; right click aims.\nShift sprints. C crouches. Q / E lean. R reloads. Your army operates automatically.\nSniper: hold right mouse for scope; scroll 4x / 8x / 12x; hold Shift to steady.\nSniper range: 180 units; walls and terrain stop bullets.\nSWAT: 320 HP, 35% small-arms protection, automatic shotgun, 12-round drum.\nHold fire for repeated blasts. Right-click tightens spread. SWAT moves slower.\nTanks / Humvees: W/S drive, A/D steer, mouse aims the gun.\nHelicopters: WASD fly, Q/E descend/climb. Mortars: aim at ground beyond 7.\nLeft fires; right aims/zooms. Weapon ranges remain specific to each unit.\nWhile controlling a unit: 1 Follow, 2 Hold, 3 Cover, 4 Attack aim, 5 Release.\nOrders recruit up to 8 friendly infantry within 28 units. Amber arc warns of nearby shots.\nDiagonal hit marker confirms damage. Reload bar and low-ammo cues appear near the aim point.\n\n[b]COMMAND[/b]\nClick a unit to select. Shift-drag adds a group. Box select selects a group.\nHold right-click to preview routes and formations; release to order.\nSpread is the default: dispersed positions with space between soldiers.\nQ then click: attack move. X: hold. Z: take nearby building cover.\nE selects the army. 1–5 select soldiers, tanks, Humvees, mortars, helicopters.\nCtrl/Cmd+6–9 saves a group; 6–9 recalls it. P / Space pauses solo.\nCtrl/Cmd+S saves; Ctrl/Cmd+L loads a solo skirmish.\nCtrl/Cmd+F1–F3 saves camera views; F1–F3 recalls them.\n\n[b]TIMED 20 VS 20[/b]\nChoose this optional match in the menu. Each team has 2 tanks, 2 Humvees,\n1 commando and 15 rifle soldiers. No helicopters. One point per enemy kill.\nTroops return after 5 seconds; vehicles after 12, when a clear spawn is available.\nHighest score after five minutes wins; equal scores are a draw.\nHQs and base structures are scenery in this mode. Solo pause stops the timer.\n\n[b]HEADQUARTERS ASSAULT[/b]\n90 soldiers + 1 commando + 1 SWAT heavy, 4 tanks, 4 Humvees, 2 mortars, 2 helicopters.\nNo unit production, reinforcements, or temporary defenses.\nTwo direct heavy hits destroy a tank or helicopter. Only rockets and tank shells hit aircraft.\nMachine guns suppress; cover protects infantry; officers aid recovery.\nThe whole battlefield is visible to both armies. Walls still block shots.\n Gates open for friendly ground troops only.\nDestroy the enemy headquarters to win. Armoured gates can be breached.\n\n[b]CITY RESIDENTS[/b]\n36 neutral residents live around the shops and homes. Press N to view the city.\nThey walk between doorways and shelter when they hear fighting.\nBullets, blasts, tanks and Humvees can kill exposed residents.\nThey are not selectable troops and do not count toward victory.\n\n[b]MULTIPLAYER[/b]\nOne player hosts; the other joins their IP. LAN works without a separate\nserver. Internet play requires a reachable UDP port 27888."
	column.add_child(text);column.add_child(button("Understood","close_help"));help_panel.visible=false

func notice(message: String):notice_label.text=message;notice_remaining=4.5

func _process(dt: float):
	if notice_remaining>0:
		notice_remaining-=dt
		if notice_remaining<=0:notice_label.text=""
	if battle!=null and battle.ready_for_play:queue_redraw()

func _map_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var r=map_rect();action.emit("map",Vector2(event.position.x/r.size.x*420,event.position.y/r.size.y*300))
		accept_event()

func update_hud():
	if battle==null or not battle.ready_for_play:return
	var s=battle.sim;var team=battle.team
	quality_button.text="High detail" if battle.high_quality else "Balanced"
	quality_button.tooltip_text="High: 4× AA, ambient occlusion, long shadows.\nBalanced: 2× AA, no AO/glow, shorter shadows.\nBoth skip distant soldier shadows and IK."
	var seconds=int(ceil(s.match_rules.remaining())) if s.match_rules.enabled() else int(s.clock)
	clock_label.text="%02d:%02d"%[seconds/60,seconds%60]
	notice_label.offset_top=170 if s.match_rules.enabled() else 92
	notice_label.offset_bottom=220 if s.match_rules.enabled() else 142
	notice_label.visible=not menu.visible
	if s.match_rules.enabled():
		score_label.text="GREEN  %d : %d  SAND"%s.match_rules.scores
		var waiting=s.match_rules.pending.filter(func(entry):return s.match_rules.templates.get(int(entry.slot),{}).get("team",-1)==team)
		var next=INF
		for entry in waiting:next=minf(next,float(entry.at)-s.clock)
		respawn_label.text="%d returning · Next respawn in %ds"%[waiting.size(),maxi(0,int(ceil(next)))] if not waiting.is_empty() else "20 vs 20 · Five-minute team deathmatch"
		if s.winner>=0:respawn_label.text="MATCH COMPLETE"
		elif s.paused:respawn_label.text="PAUSED · "+respawn_label.text
	status_label.text=("PAUSED" if s.paused else "BATTLE IN PROGRESS") if battle.started else "BATTLE READY"
	status_label.text+=" · %d FPS"%Engine.get_frames_per_second()
	if battle.network_role!="":status_label.text="LAN · "+battle.connection_state.to_upper()+" · "+("GREEN" if team==0 else "SAND")
	var selected=battle.commando_control.selected_unit();var replacement=battle.commando_control.replacement() if battle.commando_control.awaiting_replacement else {}
	control_button.text="Control next [G]" if selected.is_empty() and not replacement.is_empty() else "Control selected [G]" if not selected.is_empty() else "Control random [G]"
	control_button.disabled=not battle.started or battle.commando_control.available().is_empty()
	commando_button.disabled=s.commando.find_unit(team).is_empty()
	swat_button.disabled=s.commando.find_unit(team,"swat").is_empty()
	swat_button.visible=not s.match_rules.enabled()
	for type in infantry_buttons:infantry_buttons[type].visible=not s.match_rules.enabled() or type=="rifle"
	var army=s.units.filter(func(u):return u.team==team and not s.types[u.type].get("structure",false))
	count_label.text=str(army.size())+" / "+str(s.army_size(team))
	for i in range(squad_buttons.size()):
		var count=army.filter(func(u):return int(u.id)%3==i).size();squad_buttons[i].text=["A","B","C"][i]+" · "+str(count)
	var gate=s.gates[team].open
	gate_label.text=("GREEN ARMY" if team==0 else "SAND ARMY")+" · GATE "+("OPEN" if gate>.94 else "CLOSED" if gate<.01 else "MOVING")
	for type in role_buttons:
		var count=army.filter(func(u):return s.types[u.type].get("infantry",false) and not s.is_playable(u) if type=="infantry" else u.type==type).size()
		role_buttons[type].text=({"infantry":"Toy soldiers","tank":"Battle tanks","jeep":"Humvees","mortar":"Mortar crews","helicopter":"Helicopters"}[type])+"    "+str(count)
		role_buttons[type].disabled=count==0
		role_buttons[type].visible=not (s.match_rules.enabled() and type in ["mortar","helicopter"])
	selected_label.text=(str(battle.selection.size())+" units selected") if battle.selection.size()!=1 else s.types[s.lookup[battle.selection[0]].type].name if s.lookup.has(battle.selection[0]) else "Select your troops"
	if battle.selection.is_empty():selected_label.text="Select your troops"
	if battle.attack_mode:selected_label.text+="  ·  CLICK TO ATTACK MOVE"
	feedback_label.text="DRAG map · SHIFT+DRAG select · HOLD RIGHT CLICK preview"
	if battle.selection.size()==1 and s.lookup.has(battle.selection[0]):
		var unit=s.lookup[battle.selection[0]];var states=[]
		if unit.in_cover:states.append("IN COVER")
		if unit.suppression>.25:states.append("SUPPRESSED")
		if unit.commanded:states.append("OFFICER SUPPORT")
		if not states.is_empty():feedback_label.text=" · ".join(states)
	if s.lookup.has(battle.last_hover) and not battle.selection.is_empty():
		var enemy=s.lookup[battle.last_hover]
		if enemy.team!=team and s.tactics.can_see(team,enemy):
			var status="CANNOT TARGET AIRCRAFT"
			for id in battle.selection:
				if not s.lookup.has(id):continue
				var unit=s.lookup[id]
				if not s.can_target(unit,enemy):continue
				if s.in_range(unit,enemy):status="TARGET IN RANGE";break
				if s.position(unit).distance_to(s.position(enemy))-s.types[enemy.type].radius>s.types[unit.type].range:status="OUT OF RANGE · ORDER TO APPROACH"
				else:status="SHOT BLOCKED BY COVER"
			feedback_label.text=status
	var headquarters=s.units.filter(func(u):return u.type=="hq")
	var own=0.0;var enemy=0.0
	for unit in headquarters:
		if unit.team==team:own=unit.hp/unit.maxHp
		else:enemy=unit.hp/unit.maxHp
	hq_label.text="5 MINUTES · MOST KILLS WINS\nTroops respawn in 5s · Vehicles in 12s" if s.match_rules.enabled() else "YOUR HQ   %d%%\nENEMY HQ   %d%%"%[int(own*100),int(enemy*100)]
	for mode in drag_buttons:drag_buttons[mode].modulate=Color.WHITE if battle.drag_mode==mode else Color(.64,.70,.58)
	if s.winner>=0 and not result_shown:
		result_shown=true;menu_title.text="HONOURS EVEN." if s.winner==2 else "VICTORY, COMMANDER." if s.winner==team else "OUTMANEUVERED.";menu_description.text=s.reason;menu.show();restart_button.visible=false
	score_panel.visible=battle.started and s.match_rules.enabled() and not menu.visible

func _draw():
	if battle==null or not battle.ready_for_play or loading.visible or battle.world.camera==null:return
	var s=battle.sim;var r=map_rect()
	scope_mask.visible=battle.commando_control.is_scoped() and not any_modal()
	if scope_mask.visible:
		draw_scope();return
	draw_style_box(panel_style(Color("243d30ed"),Color("738961"),6),Rect2(r.position-Vector2(7,24),r.size+Vector2(14,31)))
	draw_rect(r,Color("ba9d71"))
	for road in s.data.roads:
		draw_rect(Rect2(r.position+Vector2((road.x-road.w*.5)/420,(road.z-road.d*.5)/300)*r.size,Vector2(road.w/420,road.d/300)*r.size),Color("808374"))
	for building in s.data.buildings:
		draw_rect(Rect2(r.position+Vector2((building.x-building.w*.5)/420,(building.z-building.d*.5)/300)*r.size,Vector2(building.w/420,building.d/300)*r.size),Color("e1d4b4"))
	for unit in s.units:
		if not s.tactics.can_see(battle.team,unit):continue
		var p=r.position+Vector2(unit.x/420,unit.z/300)*r.size
		var radius=1.5 if not s.types[unit.type].get("structure",false) else 2.1
		draw_circle(p,radius,PAPER if unit.id in battle.selection else Color("315426") if unit.team==0 else Color("75502d"))
	var view_point=r.position+Vector2(battle.world.camera_target.x/420,battle.world.camera_target.z/300)*r.size
	draw_circle(view_point,5,Color("f8f5d2"),false,1.5,true)
	draw_line(view_point-Vector2(9,0),view_point+Vector2(9,0),PAPER,1)
	draw_line(view_point-Vector2(0,9),view_point+Vector2(0,9),PAPER,1)
	draw_string(ThemeDB.fallback_font,r.position-Vector2(0,8),"TACTICAL MAP",HORIZONTAL_ALIGNMENT_LEFT,-1,10,MUTED)
	if battle.commando_control.active:
		var center=size*.5;var unit=s.lookup.get(battle.commando_control.unit_id,{})
		var color=Color("ffac69") if confirmed_hit(unit) else PAPER
		for axis in [Vector2.RIGHT,Vector2.DOWN]:
			for sign in [-1,1]:draw_line(center+axis*sign*7,center+axis*sign*14,Color.BLACK,4);draw_line(center+axis*sign*7,center+axis*sign*14,color,2)
		if unit.get("type","")=="swat":
			var spread=s.types.swat.aim_spread if battle.commando_control.aiming else s.types.swat.spread
			var radius=tan(deg_to_rad(spread))*size.y*.5/tan(deg_to_rad(battle.world.camera.fov)*.5)
			draw_circle(center,radius,Color(color,.6),false,1.3,true)
		var danger_age=s.clock-unit.get("threat_at",-100.0)
		if danger_age>=0 and danger_age<2.0:
			var origin=unit.get("threat_from",Vector3.ZERO);var direction=Vector2(origin.x-unit.x,origin.z-unit.z).normalized();var yaw=battle.commando_control.yaw
			var angle=atan2(direction.dot(Vector2(-cos(yaw),sin(yaw))),direction.dot(Vector2(sin(yaw),cos(yaw))))-PI*.5
			draw_arc(center,64,angle-.32,angle+.32,16,Color(1,.64,.25,1-danger_age/2),4,true)
		if not unit.is_empty() and unit.get("reload_time",0)<=0 and not confirmed_hit(unit):
			var range_text="OUT OF RANGE" if battle.commando_control.aim_distance>s.types[unit.type].range else "TOO CLOSE" if battle.commando_control.aim_distance<s.types[unit.type].get("minRange",0) else ""
			if range_text!="":draw_string(ThemeDB.fallback_font,center+Vector2(-48,44),range_text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffc078"))
		draw_circle(center,1.3,color)
		draw_weapon_feedback(unit,center)
		return
	if battle.preview_active:
		var route=PackedVector2Array()
		for p in battle.preview_path:
			if not battle.world.camera.is_position_behind(p):route.append(battle.world.camera.unproject_position(p))
		if route.size()>1:draw_polyline(route,Color(.78,.94,.55,.9),2,true)
		for slot in battle.preview_slots:
			if battle.world.camera.is_position_behind(slot.p):continue
			var p=battle.world.camera.unproject_position(slot.p)
			if p.x<size.x-254 and p.y>78 and p.y<size.y-80:draw_circle(p,3,PAPER if slot.clear else Color("ee976a"),false,1.5,true)
	if drag_visible:
		draw_rect(drag_rect,Color(.7,.9,.4,.16));draw_rect(drag_rect,PAPER,false,1.5)
	for id in battle.selection:
		if not s.lookup.has(id):continue
		var u=s.lookup[id]
		if battle.selection.size()>12 and u.hp>=u.maxHp:continue
		var p=Vector3(u.x,s.ground_height(u.x,u.z)+u.altitude+3,u.z)
		if battle.world.camera.is_position_behind(p):continue
		var screen=battle.world.camera.unproject_position(p)
		if screen.x<0 or screen.x>size.x-254 or screen.y<78 or screen.y>size.y-140:continue
		draw_rect(Rect2(screen-Vector2(14,0),Vector2(28,3)),Color("26382a"));draw_rect(Rect2(screen-Vector2(14,0),Vector2(28*u.hp/u.maxHp,3)),PAPER)

func draw_scope():
	var center=size*.5;var radius=minf(size.y*.34,size.x*.42)
	scope_mask.material.set_shader_parameter("viewport_size",size);scope_mask.material.set_shader_parameter("lens_radius",radius)
	var c=battle.commando_control;var u=battle.sim.lookup.get(c.unit_id,{})
	var ink=Color("101c18")
	draw_circle(center,radius,Color("657262"),false,2,true)
	for axis in [Vector2.RIGHT,Vector2.DOWN]:
		for sign in [-1,1]:
			draw_line(center+axis*sign*4,center+axis*sign*(radius-14),Color(.83,.9,.79,.38),3,true)
			draw_line(center+axis*sign*4,center+axis*sign*(radius-14),ink,1,true)
			for i in range(1,6):
				var p=center+axis*sign*i*radius/7;var normal=Vector2(-axis.y,axis.x)
				draw_line(p-normal*3,p+normal*3,ink,1,true)
	var hit=confirmed_hit(u)
	draw_circle(center,2,Color("ffa762") if hit else Color("c44e3b"))
	var font=ThemeDB.fallback_font
	draw_style_box(panel_style(Color("14231dda"),Color("536650"),3),Rect2(center+Vector2(-radius*.65,-radius*.77),Vector2(134,30)))
	draw_string(font,center+Vector2(-radius*.63,-radius*.69),"SNIPER / %d×"%int(c.scope_zoom()),HORIZONTAL_ALIGNMENT_LEFT,-1,16,PAPER)
	draw_style_box(panel_style(Color("14231dda"),Color("536650"),3),Rect2(center+Vector2(-radius*.65,radius*.65),Vector2(205,29)))
	draw_string(font,center+Vector2(-radius*.63,radius*.73),"RANGE %d  ·  MAP-WIDE"%int(c.aim_distance),HORIZONTAL_ALIGNMENT_LEFT,-1,13,PAPER)
	draw_string(font,Vector2(center.x-radius,size.y-143),"SCROLL: ZOOM     HOLD SHIFT: STEADY     RELEASE RIGHT: EXIT",HORIZONTAL_ALIGNMENT_CENTER,radius*2,12,PAPER)
	draw_weapon_feedback(u,center)

func confirmed_hit(u: Dictionary) -> bool:
	var age=battle.sim.clock-u.get("hit_at",-100.0)
	return not u.is_empty() and u.get("hp",0)>0 and age>=0 and age<HIT_FEEDBACK_TIME
func weapon_feedback(u: Dictionary) -> Dictionary:
	# Presentation reads authoritative ammo/timers; it never advances a reload.
	if u.is_empty() or u.get("hp",0)<=0:return {}
	var capacity=battle.sim.unit_control.magazine(u)
	if u.get("reload_time",0)>0:
		var duration=maxf(.001,battle.sim.unit_control.reload_seconds(u))
		return {"text":"RELOADING · %.1f s"%u.reload_time,"progress":clampf(1-u.reload_time/duration,0,1)}
	if u.get("ammo",0)<=0:return {"text":"EMPTY · R TO RELOAD","progress":-1.0}
	if capacity>1 and u.ammo<capacity and u.ammo<=maxi(1,int(capacity*.2)):
		return {"text":"LOW AMMO · %d / %d · R"%[u.ammo,capacity],"progress":-1.0}
	return {}
func draw_weapon_feedback(u: Dictionary,center: Vector2):
	if not battle.commando_control.active or battle.commando_control.suspended or any_modal():return
	if confirmed_hit(u):
		var age=battle.sim.clock-u.hit_at;var alpha=clampf(1-age/HIT_FEEDBACK_TIME,0,1)
		# Four diagonal strokes make a confirmed hit distinct from the aim cross.
		for offset in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			var a=center+offset*5;var b=center+offset*10
			draw_line(a,b,Color(0,0,0,alpha*.9),4,true)
			draw_line(a,b,Color(1,.84,.52,alpha),2,true)
	var status=weapon_feedback(u)
	if status.is_empty():return
	var reloading=status.progress>=0
	var box=Rect2(center+Vector2(-110,minf(84,size.y*.1)),Vector2(220,43 if reloading else 30))
	draw_style_box(weapon_feedback_style,box)
	draw_string(ThemeDB.fallback_font,box.position+Vector2(8,20),status.text,HORIZONTAL_ALIGNMENT_CENTER,204,13,Color("ffd294"))
	if reloading:
		var track=Rect2(box.position+Vector2(12,31),Vector2(196,4))
		draw_rect(track,Color("465448"));draw_rect(Rect2(track.position,Vector2(track.size.x*status.progress,track.size.y)),Color("ffd294"))

func any_modal() -> bool:return menu.visible or help_panel.visible or settings_panel.visible
func make_settings():
	settings_panel=PanelContainer.new();settings_panel.add_theme_stylebox_override("panel",panel_style(INK,PAPER,12));add_child(settings_panel);settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);settings_panel.offset_left=-285;settings_panel.offset_right=285;settings_panel.offset_top=-290;settings_panel.offset_bottom=290
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",7);settings_panel.add_child(column)
	column.add_child(label("FIELD SETTINGS",28));column.add_child(label("AUDIO MIX",11,MUTED))
	for bus in ["Master","Weapons","Vehicles","Ambience","Radio","sensitivity"]:
		var row=HBoxContainer.new();column.add_child(row);var title=label("Camera speed" if bus=="sensitivity" else bus,14);title.custom_minimum_size.x=135;row.add_child(title)
		var slider=HSlider.new();slider.min_value=.3 if bus=="sensitivity" else 0;slider.max_value=2 if bus=="sensitivity" else 1;slider.step=.05;slider.value=battle.settings[bus];slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size.y=30;row.add_child(slider);settings_widgets[bus]=slider
		slider.value_changed.connect(func(v):action.emit("setting",{"key":bus,"value":v}))
	for row in [["edge_scroll","Move camera at screen edges"],["character_markers","Small markers for distant characters"]]:
		var check=CheckButton.new();check.text=row[1];check.button_pressed=battle.settings[row[0]];column.add_child(check);settings_widgets[row[0]]=check
		check.toggled.connect(func(v):action.emit("setting",{"key":row[0],"value":v}))
	column.add_child(label("SAVED CAMERA VIEWS · Ctrl/Cmd + F1–F3 to save",11,MUTED))
	var views=HBoxContainer.new();column.add_child(views)
	for i in range(3):
		var b=button("View "+str(i+1),"camera_recall",i);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;views.add_child(b)
	column.add_child(button("Return to battle","close_help"));settings_panel.hide()
func sync_settings():
	for key in settings_widgets:
		if settings_widgets[key] is Range:settings_widgets[key].set_value_no_signal(battle.settings[key])
		else:settings_widgets[key].set_pressed_no_signal(battle.settings[key])

func make_direct_panel():
	direct_panel=PanelContainer.new();direct_panel.add_theme_stylebox_override("panel",panel_style(INK,Color("8fa767"),6));add_child(direct_panel)
	direct_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);direct_panel.offset_top=-120
	var row=HBoxContainer.new();direct_panel.add_child(row)
	var info=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(info)
	direct_squad=label("",12);info.add_child(direct_squad)
	direct_status=label("COMMANDO · ARMY ON AUTO",19);info.add_child(direct_status)
	direct_movement=label("",12,MUTED);info.add_child(direct_movement)
	info.add_child(label("R reload · G next unit · Hold ALT for buttons · TAB / ESC return to strategy",12,MUTED))
	var actions=VBoxContainer.new();row.add_child(actions)
	next_unit_button=button("Next unit [G]","control_selected");actions.add_child(next_unit_button)
	actions.add_child(button("Strategy [TAB]","strategy"));direct_panel.hide()
func set_direct_mode(active: bool):
	if not active:scope_mask.hide()
	for name in ["Side","Bottom","Navigation"]:get_node(name).visible=not active
	direct_panel.visible=active
	minimap_area.mouse_filter=Control.MOUSE_FILTER_IGNORE if active else Control.MOUSE_FILTER_STOP
	queue_redraw()
