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
    uchar4 pos;
    uchar4 color;
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
    uchar4 pos = vert_in[vid].pos;
    outVertex.position = mvp * (float4(pos.x, pos.y, pos.z, 1.0) + float4(chunk_offset * 16, 0.0, 0.0));
    outVertex.color = float4(vert_in[vid].color) / float(0xFF) * float(pos.w) / float(0xFF);
    
    return outVertex;
};

fragment half4 passThroughFragment(VertexOut inFrag [[stage_in]])
{
    return pow(half4(inFrag.color), 1.0/2.2);
};