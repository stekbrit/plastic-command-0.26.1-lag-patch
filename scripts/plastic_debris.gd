extends Node3D
class_name PlasticDebris
var world
var templates={}
var pieces=[]
var paused_last=false
const LIMIT=80
func build(owner_world):
	world=owner_world
	var material=PhysicsMaterial.new();material.friction=.72;material.bounce=.32
	var floor=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=2;floor.physics_material_override=material;add_child(floor)
	var shape=CollisionShape3D.new();var ground=BoxShape3D.new();ground.size=Vector3(600,1,500);shape.shape=ground;shape.position=Vector3(210,-.32,150);floor.add_child(shape)
	var nav=world.sim.navigation
	for i in range(nav.rectangles.size()):
		var r=nav.rectangles[i];var h=nav.heights[i]
		var collider=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(maxf(.12,r.size.x),h,maxf(.12,r.size.y));collider.shape=box;collider.position=Vector3(r.get_center().x,h*.5+.18,r.get_center().y);floor.add_child(collider)
func get_parts(type: String,team: int) -> Array:
	var key=type+"_"+str(team)
	if not templates.has(key):
		var root=world.fetch_model(key+"_debris").instantiate();var result=[]
		for mesh in root.find_children("*","MeshInstance3D",true,false):
			var aabb=mesh.mesh.get_aabb();result.append({"name":str(mesh.name),"mesh":mesh.mesh,"center":aabb.get_center(),"size":aabb.size})
		root.free();templates[key]=result
	return templates[key]
func explode(event: Dictionary):
	var parts=get_parts(event.type,event.team);var rng=RandomNumberGenerator.new();rng.seed=int(event.id)*591+int(event.at*100)
	var ground=world.sim.ground_height(event.p.x,event.p.z)
	for part in parts:
		# Ground vehicles retain their lower hull as a wreck. Everything else
		# separates into the same modeled parts used by the original toy.
		if part.name=="Core" and event.type in ["tank","jeep","mortar"]:continue
		if pieces.size()>=LIMIT:
			var oldest=pieces.pop_front();oldest.body.queue_free()
		var body=RigidBody3D.new();body.collision_layer=2;body.collision_mask=1;body.mass=clampf(part.size.x*part.size.y*part.size.z*.35,.08,5);body.linear_damp=.18;body.angular_damp=.6
		var physics=PhysicsMaterial.new();physics.friction=.72;physics.bounce=.34;body.physics_material_override=physics
		var bounds=BoxShape3D.new();bounds.size=part.size.max(Vector3.ONE*.075)*.86
		var collider=CollisionShape3D.new();collider.shape=bounds;body.add_child(collider)
		var mesh=MeshInstance3D.new();mesh.mesh=part.mesh;mesh.position=-part.center;mesh.lod_bias=.6;body.add_child(mesh)
		body.position=Vector3(event.p.x,ground+event.p.y,event.p.z)+Basis(Vector3.UP,event.angle)*part.center+Vector3.UP*.12;body.rotation.y=event.angle;add_child(body)
		var radial=Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1)).normalized()
		body.linear_velocity=(radial*rng.randf_range(3,8)+Vector3.UP*rng.randf_range(2.6,7.2))*(1.0 if event.get("heavy",true) else .32);body.angular_velocity=Vector3(rng.randf_range(-7,7),rng.randf_range(-8,8),rng.randf_range(-7,7))
		body.freeze=world.sim.paused
		pieces.append({"body":body,"age":0.0})
func make_wreck(event: Dictionary,parent: Node3D):
	for part in get_parts(event.type,event.team):
		if part.name!="Core":continue
		var mesh=MeshInstance3D.new();mesh.mesh=part.mesh;mesh.material_override=world.material(Color("33412a") if event.team==0 else Color("66513b"),.75);mesh.lod_bias=.65;parent.add_child(mesh)
func update(dt: float,paused: bool):
	for piece in pieces:
		if paused!=paused_last:piece.body.freeze=paused
		piece.age+=dt
		if piece.age>38:piece.body.queue_free()
	pieces=pieces.filter(func(p):return p.age<=38)
	paused_last=paused
func reset():
	for piece in pieces:piece.body.queue_free()
	pieces.clear()
