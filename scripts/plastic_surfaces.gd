extends RefCounted
# Shared, tiled PBR maps: moulded plastic micrograin and roughness variation.
# Triplanar projection also textures parts with no authored UVs, such as armour.
var materials={}
var grain: NoiseTexture2D
var roughness: NoiseTexture2D
const FINISHES={
	"fabric":[.78,.02,.55,.25],"gear":[.59,.10,.40,.28],
	"shell":[.36,.38,.18,.32],"face":[.57,.08,.15,.20],
	"rubber":[.86,0.0,.42,.16],"weapon":[.46,.18,.18,.22],
	"optic":[.17,.60,0.0,.08]
}
func _init():
	var noise=FastNoiseLite.new();noise.seed=7419;noise.frequency=.24;noise.fractal_octaves=3
	grain=NoiseTexture2D.new();grain.width=512;grain.height=512;grain.noise=noise;grain.seamless=true;grain.as_normal_map=true;grain.bump_strength=.10
	var broad=FastNoiseLite.new();broad.seed=1894;broad.frequency=.032;broad.fractal_octaves=4
	roughness=NoiseTexture2D.new();roughness.width=512;roughness.height=512;roughness.noise=broad;roughness.seamless=true
	var gradient=Gradient.new();gradient.colors=PackedColorArray([Color(.68,.68,.68),Color(1,1,1)]);roughness.color_ramp=gradient
func apply(mesh: MeshInstance3D,character: bool=false):
	for surface in range(mesh.mesh.get_surface_count()):
		var original=mesh.mesh.surface_get_material(surface)
		if not original is StandardMaterial3D:continue
		var key=str(original.get_instance_id())+("_figure" if character else "")
		if not materials.has(key):
			var m=original.duplicate()
			m.normal_enabled=true;m.normal_texture=grain;m.normal_scale=.38
			m.roughness_texture=roughness;m.roughness=maxf(.33,m.roughness)
			m.uv1_triplanar=true;m.uv1_scale=Vector3.ONE*2.8;m.uv1_triplanar_sharpness=6
			m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.clearcoat_enabled=true;m.clearcoat=.42;m.clearcoat_roughness=.3
			if character:m.rim_enabled=true;m.rim=.28;m.rim_tint=.35
			for finish in FINISHES:
				if not character or not original.resource_name.begins_with("pc_finish_"+finish):continue
				var profile=FINISHES[finish]
				m.vertex_color_use_as_albedo=true;m.roughness=profile[0];m.clearcoat=profile[1];m.normal_scale=profile[2];m.rim=profile[3]
				m.clearcoat_enabled=m.clearcoat>0;m.metallic=0.0
				if finish=="optic":m.normal_enabled=false;m.roughness_texture=null
			# New soldiers are a single material throughout, including their
			# goggles and guns. Mortar crew and debris use this path as well.
			if original.resource_name.begins_with("pc_finish_plastic"):
				m.vertex_color_use_as_albedo=true;m.metallic=0.0
				m.roughness=.32;m.roughness_texture=roughness;m.normal_scale=.14
				m.clearcoat_enabled=true;m.clearcoat=.38;m.clearcoat_roughness=.3
				m.rim_enabled=true;m.rim=.22;m.rim_tint=.35
			materials[key]=m
		mesh.set_surface_override_material(surface,materials[key])
