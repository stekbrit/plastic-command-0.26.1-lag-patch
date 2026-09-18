extends Node3D
# Cosmetic-only particles: five shared meshes, fixed capacity, no physics bodies.
# No resource or scene creation takes place while a weapon fires.
const SHADER=preload("res://scripts/combat_particle.gdshader")
const BUDGET={"smoke":128,"fire":32,"spark":96,"case":64,"mark":80}
var world
var groups={}
var rng=RandomNumberGenerator.new()
var last_update_usec=0
func build(owner_world):
	world=owner_world;rng.seed=11017
	for kind in BUDGET:
		var batch=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true;batch.use_custom_data=true
		var material
		if kind in ["case","spark"]:
			var mesh=BoxMesh.new();mesh.size=Vector3.ONE;batch.mesh=mesh
			material=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=.36;material.metallic=.65 if kind=="case" else 0.0
			if kind=="spark":material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.emission_enabled=true;material.emission=Color("ffb559");material.emission_energy_multiplier=2.0
		else:
			var mesh=QuadMesh.new();mesh.size=Vector2.ONE;batch.mesh=mesh
			material=ShaderMaterial.new();material.shader=SHADER;material.set_shader_parameter("mode",0 if kind=="smoke" else 1 if kind=="fire" else 2)
		batch.instance_count=BUDGET[kind];batch.visible_instance_count=0
		var node=MultiMeshInstance3D.new();node.multimesh=batch;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.custom_aabb=AABB(Vector3(-50,-10,-50),Vector3(520,140,420));add_child(node)
		groups[kind]={"batch":batch,"items":[],"cursor":0}
func emit(kind: String,p: Vector3,v: Vector3,size: float,life: float,color: Color,normal: Vector3=Vector3.UP):
	var g=groups[kind]
	var item={"p":p,"v":v,"size":size,"life":life,"age":0.0,"color":color,"normal":normal,"spin":rng.randf_range(-PI,PI),"seed":rng.randf(),"floor":world.sim.ground_height(p.x,p.z)+.025}
	if g.items.size()<BUDGET[kind]:g.items.append(item)
	else:g.items[g.cursor]=item;g.cursor=(g.cursor+1)%BUDGET[kind]
func close_enough(p: Vector3,distance: float=90.0) -> bool:
	return world.camera.global_position.distance_squared_to(p)<distance*distance
func muzzle(s: Dictionary):
	if not close_enough(s.a):return
	var direction=(s.b-s.a).normalized();var heavy=s.kind!="bullet"
	var size=1.0 if s.attacker=="swat" else .65
	if heavy:size=2.4 if s.attacker=="tank" else 1.6
	emit("smoke",s.a+direction*.22,direction*.9+Vector3.UP*.8,size,.52 if not heavy else .85,Color(.68,.65,.58,.27))
	if heavy:emit("fire",s.a+direction*.3, direction*1.5,size*.8,.085,Color(1,.72,.22,.9))
	if s.kind=="bullet" and close_enough(s.a,45):
		var right=Vector3(direction.z,0,-direction.x).normalized()
		var casing_color=Color("b6a051") if s.attacker!="swat" else Color("973a2e")
		emit("case",s.a-direction*.85+right*.2,right*rng.randf_range(1.4,2.5)+Vector3.UP*1.5,.055 if s.attacker!="swat" else .085,1.8,casing_color)
func bullet_impact(s: Dictionary):
	var hit=s.get("impact",{})
	if hit.is_empty() or not close_enough(s.b):return
	var p=s.b;var normal=hit.normal;var kind=hit.surface
	var metal=kind=="metal"
	for i in range(4 if metal else 2):
		var v=(normal*1.7+Vector3(rng.randf_range(-1,1),rng.randf_range(.3,1.5),rng.randf_range(-1,1)))*rng.randf_range(1,2.5)
		emit("spark" if metal else "smoke",p+normal*.04,v,.035 if metal else rng.randf_range(.18,.32),.16 if metal else .45,Color(1,.8,.36) if metal else Color(.63,.56,.44,.55))
	if kind in ["stone","ground"]:
		emit("mark",p+normal*.018,Vector3.ZERO,rng.randf_range(.12,.21),12.0,Color(.13,.115,.09,.7),normal)
func trail(s: Dictionary,p: Vector3):
	if s.kind!="rocket" or not close_enough(p,180):return
	emit("smoke",p,Vector3.UP*.35,.38,.65,Color(.71,.72,.7,.32))
func explosion(p: Vector3,size: float):
	if not close_enough(p,240):return
	for i in range(5):
		var v=Vector3(rng.randf_range(-1,1),rng.randf_range(.2,1.3),rng.randf_range(-1,1))*size
		emit("fire",p+v*.06,v*.55,size*rng.randf_range(.8,1.2),rng.randf_range(.17,.32),Color(1,.55,.12,.95))
	for i in range(12):
		var v=Vector3(rng.randf_range(-1,1),rng.randf_range(.2,1.3),rng.randf_range(-1,1))*size
		emit("smoke",p+v*.12,v*.65,size*rng.randf_range(.5,.95),rng.randf_range(1.3,2.2),Color(.3,.28,.245,.65))
		if i<8:emit("spark",p,v*3,.045,.38,Color(1,.72,.25))
	var floor=world.sim.ground_height(p.x,p.z)
	if p.y-floor<2:
		emit("mark",Vector3(p.x,floor+.025,p.z),Vector3.ZERO,size*1.35,18,Color(.18,.155,.12,.6))
		for i in range(8):
			var angle=TAU*i/8;var v=Vector3(cos(angle),.05,sin(angle))*size*2
			emit("smoke",Vector3(p.x,floor+.15,p.z),v,size*.6,.7,Color(.72,.63,.47,.33))
func update(dt: float):
	var started=Time.get_ticks_usec();var facing=world.camera.global_basis
	for kind in groups:
		var g=groups[kind];var count=0
		for item in g.items:
			item.age+=dt
			if item.age>=item.life:continue
			if kind in ["case","spark"]:
				item.v.y-=9.8*dt
				item.p+=item.v*dt
				if item.p.y<item.floor:
					item.p.y=item.floor;item.v=Vector3(item.v.x*.55,absf(item.v.y)*.22,item.v.z*.55)
			else:item.p+=item.v*dt;item.v*=exp(-dt*2)
			var t=item.age/item.life;var scale=item.size;var basis=facing
			var color=item.color
			if kind=="case":
				basis=Basis.from_euler(Vector3(item.spin+item.age*9,item.spin,1.1));basis=basis.scaled(Vector3(scale,scale*2.8,scale))
			elif kind=="spark":
				basis=Basis(Quaternion(Vector3.UP,item.v.normalized())) if item.v.length_squared()>.01 else Basis.IDENTITY;basis=basis.scaled(Vector3(scale,scale*5,scale))
			elif kind=="mark":
				basis=Basis(Quaternion(Vector3.BACK,item.normal));basis=basis.rotated(item.normal,item.spin).scaled(Vector3.ONE*scale);color.a*=minf(1,(1-t)*5)
			else:
				scale*=1+t*(1.7 if kind=="smoke" else .8);basis=basis.rotated(facing.z,item.spin).scaled(Vector3.ONE*scale);color.a*=pow(1-t,1.2)
			g.batch.set_instance_transform(count,Transform3D(basis,item.p));g.batch.set_instance_color(count,color);g.batch.set_instance_custom_data(count,Color(item.seed,t,0,1));count+=1
		g.batch.visible_instance_count=count
		g.items=g.items.filter(func(item):return item.age<item.life)
		g.cursor=g.cursor%maxi(1,g.items.size())
	last_update_usec=Time.get_ticks_usec()-started
func reset():
	for g in groups.values():g.items.clear();g.batch.visible_instance_count=0;g.cursor=0
