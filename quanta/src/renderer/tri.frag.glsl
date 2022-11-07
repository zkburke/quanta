#version 450
#extension GL_EXT_scalar_block_layout : enable
#extension GL_EXT_nonuniform_qualifier : enable

layout(location = 0) in Out
{
    flat uint material_index;
    vec4 fragment_color;
    vec2 uv;
} in_data;

layout(location = 0) out vec4 output_color;

struct Material
{
    uint albedo_index;
    uint albedo_color;
};

layout(set = 0, binding = 3, scalar) readonly buffer Materials
{
    Material materials[];
};

layout(set = 0, binding = 4) uniform sampler2D samplers[];

void main() 
{
    Material material = materials[in_data.material_index];

    vec4 albedo = unpackUnorm4x8(material.albedo_color) * texture(samplers[nonuniformEXT(material.albedo_index)], in_data.uv);

    output_color = in_data.fragment_color * albedo;
}