//
//  Shaders.metal
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

struct VertexIn
{
    packed_uchar4 pos;
    packed_uchar4 color;
};

struct VertexOut
{
    float4  position [[position]];
    float4  color;
};

vertex VertexOut passThroughVertex(uint vid [[ vertex_id ]],
                                   constant VertexIn* vert_in [[ buffer(0) ]],
                                   constant float4x4& mvp [[ buffer(1) ]],
                                   constant float2& chunk_offset [[ buffer(2) ]])
{
    VertexOut outVertex;
    
    outVertex.position = mvp * (float4(vert_in[vid].pos[0], vert_in[vid].pos[1], vert_in[vid].pos[2], 1.0) + float4(chunk_offset * 16, 0.0, 0.0));
    outVertex.color = float4(vert_in[vid].color[0], vert_in[vid].color[1], vert_in[vid].color[2], vert_in[vid].color[3]) / float(0xFF) * float(vert_in[vid].pos[3]) / float(0xFF);
    
    return outVertex;
};

fragment half4 passThroughFragment(VertexOut inFrag [[stage_in]])
{
    return half4(inFrag.color);
};