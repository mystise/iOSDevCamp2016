//
//  Scheduler.swift
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import GLKit

let TIMESTEP: Float64 = 1.0/60.0
let RADIUS: Int32 = 3

class Scheduler {
    private var meshes: Dictionary<ChunkPosition, (MTLBuffer, MTLBuffer, Int, MTLBuffer)> = [:] // (vertices, indices, index count, chunk offset)
    private var chunks: Dictionary<ChunkPosition, Chunk> = [:]
    private var dirty_chunks: Set<ChunkPosition> = []
    private var unpopulated_chunks: Set<ChunkPosition> = []
    private var ungenerated_chunks: Set<ChunkPosition> = []
    private let seed: UInt32
    private var camera_pos: (Float32, Float32) = (0.0, 128.0) // (Y, Z), X = 0
    private let height_noise: Brownian
    private let dirt_noise: OpenSimplex
    
    private var view: MTKView! = nil
    private var device: MTLDevice! = nil
    private var commandQueue: MTLCommandQueue! = nil
    private var pipelineState: MTLRenderPipelineState! = nil
    private var mvpBuffer: MTLBuffer! = nil
    private var depthStencilState: MTLDepthStencilState! = nil
    
    var camera_speed: Float32 = 2.0
    
    init(seed: UInt32, view: MTKView) {
        self.seed = seed
        self.height_noise = Brownian(seed: self.seed, octaves: 4, frequency: 1.0/150.0)
        self.dirt_noise = OpenSimplex(seed: self.seed)
        
        for x_pos in -RADIUS...RADIUS {
            for y_pos in -1...RADIUS {
                let chunk_pos = ChunkPosition(x: x_pos, y: y_pos)
                if !self.chunks.keys.contains(chunk_pos) {
                    self.ungenerated_chunks.insert(chunk_pos)
                }
            }
        }
        
        self.view = view
        self.view.clearColor = MTLClearColorMake(0.0, 0.2, 0.8, 1.0)
        self.device = self.view.device
        self.commandQueue = self.device.newCommandQueue()
        self.commandQueue.label = "Main Queue"
        
        let defaultLibrary = device.newDefaultLibrary()!
        let fragmentProgram = defaultLibrary.newFunctionWithName("passThroughFragment")!
        let vertexProgram = defaultLibrary.newFunctionWithName("passThroughVertex")!
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.view.colorPixelFormat
        pipelineStateDescriptor.sampleCount = self.view.sampleCount
        
        do {
            try self.pipelineState = self.device.newRenderPipelineStateWithDescriptor(pipelineStateDescriptor)
        } catch let error {
            assert(false, "Failed to create pipeline state, error \(error)")
        }
        
        let depthStencilStateDescriptor = MTLDepthStencilDescriptor()
        depthStencilStateDescriptor.depthCompareFunction = .Less
        depthStencilStateDescriptor.depthWriteEnabled = true
        self.depthStencilState = self.device.newDepthStencilStateWithDescriptor(depthStencilStateDescriptor)
        
        self.mvpBuffer = self.device.newBufferWithLength(sizeof(GLKMatrix4), options: .CPUCacheModeWriteCombined)
        self.mvpBuffer.label = "Matrix"
    }
    
    func update() {
        let old_camera_pos = Int32(floor(self.camera_pos.0)) / 16
        self.camera_pos.0 += self.camera_speed * Float32(TIMESTEP)
        let new_camera_pos = Int32(floor(self.camera_pos.0)) / 16
        if old_camera_pos != new_camera_pos {
            var removed: Array<ChunkPosition> = []
            for chunk_pos in self.chunks.keys {
                if chunk_pos.x < -RADIUS ||
                    chunk_pos.x > RADIUS + 1 ||
                    chunk_pos.y < new_camera_pos - 1 ||
                    chunk_pos.y > new_camera_pos + RADIUS + 1 {
                    removed.append(chunk_pos)
                }
            }
            
            for chunk_pos in removed {
                self.chunks.removeValueForKey(chunk_pos)
                self.unpopulated_chunks.remove(chunk_pos)
                self.ungenerated_chunks.remove(chunk_pos)
                self.dirty_chunks.remove(chunk_pos)
                self.meshes.removeValueForKey(chunk_pos)
            }
            
            for x_pos in -RADIUS...RADIUS {
                for y_pos in new_camera_pos - 1...new_camera_pos + RADIUS {
                    let chunk_pos = ChunkPosition(x: x_pos, y: y_pos)
                    if !self.chunks.keys.contains(chunk_pos) {
                        self.ungenerated_chunks.insert(chunk_pos)
                    }
                }
            }
        }
        
        {
            let chunk_pos = ChunkPosition(x: 0, y: new_camera_pos)
            if let chunk = self.chunks[chunk_pos] {
                let y_pos = UInt32(floor(self.camera_pos.0)) & 0xF
                for z in (UInt32(0)..<128).reverse() {
                    if chunk.get(0, y_pos, z) != .Air {
                        self.camera_pos.1 = Float32(z) + 4.0
                        break
                    }
                }
            }
        }()
        
        
        if let chunk_pos = self.ungenerated_chunks.popFirst() {
            self.generate_chunk(chunk_pos)
        }
        
        var pop_chunk_pos: ChunkPosition? = nil
        for chunk_pos in self.unpopulated_chunks {
            if self.chunks.keys.contains(chunk_pos.north()) &&
                self.chunks.keys.contains(chunk_pos.north_east()) &&
                self.chunks.keys.contains(chunk_pos.east()) &&
                self.chunks.keys.contains(chunk_pos.south_east()) &&
                self.chunks.keys.contains(chunk_pos.south()) &&
                self.chunks.keys.contains(chunk_pos.south_west()) &&
                self.chunks.keys.contains(chunk_pos.west()) &&
                self.chunks.keys.contains(chunk_pos.north_west()) {
                pop_chunk_pos = chunk_pos
                break
            }
        }
        
        if let chunk_pos = pop_chunk_pos {
            self.unpopulated_chunks.remove(chunk_pos)
            self.populate_chunk(chunk_pos)
        }
        
        if let chunk_pos = self.dirty_chunks.popFirst() {
            self.mesh_chunk(chunk_pos)
        }
        
        let projection = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(90.0), Float(self.view.drawableSize.width / self.view.drawableSize.height), 0.01, 1000.0)
        let modelView = GLKMatrix4MakeLookAt(0.5, camera_pos.0, camera_pos.1, 0.5, camera_pos.0 + 1.0, camera_pos.1, 0.0, 0.0, 1.0)
        let mvp = [GLKMatrix4Multiply(projection, modelView)]
        let vData = UnsafeMutablePointer<GLKMatrix4>(self.mvpBuffer.contents())
        vData.initializeFrom(mvp)
        
        let commandBuffer = commandQueue.commandBuffer()
        commandBuffer.label = "Frame command buffer"
        
        if let renderPassDescriptor = self.view.currentRenderPassDescriptor, currentDrawable = self.view.currentDrawable {
            let renderEncoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPassDescriptor)
            renderEncoder.label = "Render encoder"
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setFrontFacingWinding(.CounterClockwise)
            renderEncoder.setCullMode(.Back)
            renderEncoder.setDepthStencilState(self.depthStencilState)
            
            for (chunk_pos, (vertices, indices, index_count, chunk_offset)) in self.meshes {
                renderEncoder.pushDebugGroup("chunk \(chunk_pos)")
                
                renderEncoder.setVertexBuffer(vertices, offset: 0, atIndex: 0)
                renderEncoder.setVertexBuffer(self.mvpBuffer, offset: 0, atIndex: 1)
                renderEncoder.setVertexBuffer(chunk_offset, offset: 0, atIndex: 2)
                renderEncoder.drawIndexedPrimitives(.Triangle, indexCount: index_count, indexType: .UInt32, indexBuffer: indices, indexBufferOffset: 0)
                
                renderEncoder.popDebugGroup()
            }
            
            renderEncoder.endEncoding()
            
            commandBuffer.presentDrawable(currentDrawable)
        }
        
        commandBuffer.commit()
    }
    
    func generate_chunk(chunk_pos: ChunkPosition) {
        let chunk = Chunk()
        self.chunks[chunk_pos] = chunk
        
        for x in Int32(0)..<16 {
            for y in Int32(0)..<16 {
                let xy_pos = (chunk_pos.x * 16 + x, chunk_pos.y * 16 + y)
                
                var noise = self.height_noise.gen(Float64(xy_pos.0), Float64(xy_pos.1))
                let height = Int32((noise + 1.0) / 2.0 * 32.0 + 16.0)
                
                for z in Int32(0)..<height {
                    chunk.set(UInt32(x), UInt32(y), UInt32(z), block: .Stone)
                }
                
                let scale = 32.0
                noise = self.dirt_noise.gen(Float64(xy_pos.0) / scale, Float64(xy_pos.1) / scale)
                let dirt_height = Int32((noise + 1.0) / 2.0 * 8.0 - 1.0)
                
                if height - dirt_height < height {
                    for z in height - dirt_height..<height {
                        chunk.set(UInt32(x), UInt32(y), UInt32(z), block: .Dirt)
                    }
                }
                
                if dirt_height > 0 {
                    chunk.set(UInt32(x), UInt32(y), UInt32(height), block: .Grass)
                }
                
                if height < 32 {
                    for z in height..<32 {
                        chunk.set(UInt32(x), UInt32(y), UInt32(z), block: .Water)
                    }
                }
            }
        }
        
        self.unpopulated_chunks.insert(chunk_pos)
    }
    
    func populate_chunk(chunk_pos: ChunkPosition) {
        let chunk = self.chunks[chunk_pos]!
        srand((UInt32(bitPattern: chunk_pos.x) &* 0x0CFF235B) &+ (UInt32(bitPattern: chunk_pos.y) &* 0x4F72AC03) &+ seed)
        
        self.dirty_chunks.insert(chunk_pos)
        
        for _ in 0..<rand() % 12 {
            let block_x = UInt32(rand() % 16)
            let block_y = UInt32(rand() % 16)
            
            var zpos: UInt32 = 0
            for z in (UInt32(0)...127).reverse() {
                if chunk.get(block_x, block_y, z) != .Air {
                    zpos = z
                    break
                }
            }
            
            if chunk.get(block_x, block_y, zpos) != .Grass {
                continue
            }
            
            let tree_height = UInt32((rand() % 5) + 5)
            
            for z in zpos + 1 ..< zpos + tree_height + 1 {
                chunk.set(block_x, block_y, z, block: .Log)
            }
            
            let check_set_leaf = { (pos: WorldPosition) in
                let chunk = self.chunks[pos.chunk_pos]!
                if chunk.get(pos.block_pos.x, pos.block_pos.y, pos.block_pos.z) == .Air {
                    chunk.set(pos.block_pos.x, pos.block_pos.y, pos.block_pos.z, block: .Leaf)
                    if !self.unpopulated_chunks.contains(pos.chunk_pos) {
                        self.dirty_chunks.insert(pos.chunk_pos)
                    }
                }
            }
            
            let world_pos = WorldPosition(block_pos: BlockPosition(x: block_x, y: block_y, z: 0), chunk_pos: chunk_pos)
            for z in Int32(zpos + tree_height - 1) ... Int32(zpos + tree_height) {
                for w in Int32(-2)...2 {
                    check_set_leaf(world_pos.offset(w, y: 0, z: z))
                    check_set_leaf(world_pos.offset(w, y: 1, z: z))
                    check_set_leaf(world_pos.offset(w, y: -1, z: z))
                    if w != -2 && w != 2 {
                        check_set_leaf(world_pos.offset(w, y: 2, z: z))
                        check_set_leaf(world_pos.offset(w, y: -2, z: z))
                    }
                }
            }
            
            for w in Int32(-1)...1 {
                check_set_leaf(world_pos.offset(w, y: 0, z: Int32(zpos + tree_height + 1)))
                if w == 0 {
                    check_set_leaf(world_pos.offset(w, y: 1, z: Int32(zpos + tree_height + 1)))
                    check_set_leaf(world_pos.offset(w, y: -1, z: Int32(zpos + tree_height + 1)))
                }
            }
        }
    }
    
    func mesh_chunk(chunk_pos: ChunkPosition) {
        let chunk = self.chunks[chunk_pos]!
        
        let block_exists = { (pos: WorldPosition) -> Bool in
            return self.chunks[pos.chunk_pos]!.get(pos.block_pos.x, pos.block_pos.y, pos.block_pos.z) != .Air
        }
        
        let get_face = { (base_index: UInt32, flipped: Bool) -> [UInt32] in
            switch flipped {
            case false:
                    //3 - 2
                    //| ╲ |
                    //0 - 1
                    return [base_index + 3, base_index + 0, base_index + 1, base_index + 1, base_index + 2, base_index + 3]
            case true:
                    //3 - 2
                    //| ╱ |
                    //0 - 1
                    return [base_index + 0, base_index + 1, base_index + 2, base_index + 2, base_index + 3, base_index + 0]
            }
        }
        
        let get_occlusion = { (exists1: Bool, exists2: Bool, exists3: Bool) -> Int8 in
            switch (exists1, exists2, exists3) {
            case (false, false, false):
                return 3
            case (true, false, false), (false, true, false), (false, false, true):
                return 2
            case (true, true, false), (false, true, true):
                return 1
            case (true, _, true):
                return 0
            default:
                return 0
            }
        }
        
        let get_vertex = { (x: UInt8, y: UInt8, z: UInt8, color: (UInt8, UInt8, UInt8, UInt8), occlusion: Int8) -> Vertex in
            var output: UInt8 = 0x00
            switch occlusion {
            case 3: output = 0xFF
            case 2: output = 0xE5
            case 1: output = 0xCC
            case 0: output = 0xB2
            default: output = 0x00
            }
            
            return Vertex(x: x, y: y, z: z, occlusion: output, r: color.0, g: color.1, b: color.2, a: color.3)
        }
        
        var vertices: Array<Vertex> = []
        var indices: Array<UInt32> = []
        
        for x in UInt32(0)..<16 {
            for y in UInt32(0)..<16 {
                for z in UInt32(0)..<128 {
                    let block = chunk.get(x, y, z)
                    if block == .Air {
                        continue
                    }
                    
                    let world_pos = WorldPosition(block_pos: BlockPosition(x: x, y: y, z: z), chunk_pos: chunk_pos)
                    
                    let x = UInt8(x)
                    let y = UInt8(y)
                    let z = UInt8(z)
                    
                    let surrounding = [
                        block_exists(world_pos.offset(-1, y:  1, z:  1)), // 0
                        block_exists(world_pos.offset( 0, y:  1, z:  1)),
                        block_exists(world_pos.offset( 1, y:  1, z:  1)),
                        
                        block_exists(world_pos.offset(-1, y:  0, z:  1)), // 3
                        block_exists(world_pos.offset( 0, y:  0, z:  1)),
                        block_exists(world_pos.offset( 1, y:  0, z:  1)),
                        
                        block_exists(world_pos.offset(-1, y: -1, z:  1)), // 6
                        block_exists(world_pos.offset( 0, y: -1, z:  1)),
                        block_exists(world_pos.offset( 1, y: -1, z:  1)),
                        
                        block_exists(world_pos.offset(-1, y:  1, z:  0)), // 9
                        block_exists(world_pos.offset( 0, y:  1, z:  0)),
                        block_exists(world_pos.offset( 1, y:  1, z:  0)),
                        
                        block_exists(world_pos.offset(-1, y:  0, z:  0)), // 12
                        true,
                        block_exists(world_pos.offset( 1, y:  0, z:  0)),
                        
                        block_exists(world_pos.offset(-1, y: -1, z:  0)), // 15
                        block_exists(world_pos.offset( 0, y: -1, z:  0)),
                        block_exists(world_pos.offset( 1, y: -1, z:  0)),
                        
                        block_exists(world_pos.offset(-1, y:  1, z: -1)), // 18
                        block_exists(world_pos.offset( 0, y:  1, z: -1)),
                        block_exists(world_pos.offset( 1, y:  1, z: -1)),
                        
                        block_exists(world_pos.offset(-1, y:  0, z: -1)), // 21
                        block_exists(world_pos.offset( 0, y:  0, z: -1)),
                        block_exists(world_pos.offset( 1, y:  0, z: -1)),
                        
                        block_exists(world_pos.offset(-1, y: -1, z: -1)), // 24
                        block_exists(world_pos.offset( 0, y: -1, z: -1)),
                        block_exists(world_pos.offset( 1, y: -1, z: -1))
                        ]
                    
                    if !surrounding[4] {
                        // Top face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[3], surrounding[6], surrounding[7])
                        let occ1 = get_occlusion(surrounding[7], surrounding[8], surrounding[5])
                        let occ2 = get_occlusion(surrounding[5], surrounding[2], surrounding[1])
                        let occ3 = get_occlusion(surrounding[1], surrounding[0], surrounding[3])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 0, y + 0, z + 1, block.color(), occ0))
                        vertices.append(get_vertex(x + 1, y + 0, z + 1, block.color(), occ1))
                        vertices.append(get_vertex(x + 1, y + 1, z + 1, block.color(), occ2))
                        vertices.append(get_vertex(x + 0, y + 1, z + 1, block.color(), occ3))
                    }
                    
                    if !surrounding[22] {
                        // Bottom face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[21], surrounding[18], surrounding[19])
                        let occ1 = get_occlusion(surrounding[19], surrounding[20], surrounding[23])
                        let occ2 = get_occlusion(surrounding[23], surrounding[26], surrounding[25])
                        let occ3 = get_occlusion(surrounding[25], surrounding[24], surrounding[21])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 0, y + 1, z + 0, block.color(), occ0))
                        vertices.append(get_vertex(x + 1, y + 1, z + 0, block.color(), occ1))
                        vertices.append(get_vertex(x + 1, y + 0, z + 0, block.color(), occ2))
                        vertices.append(get_vertex(x + 0, y + 0, z + 0, block.color(), occ3))
                    }
                    
                    if !surrounding[10] {
                        // North face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[11], surrounding[20], surrounding[19])
                        let occ1 = get_occlusion(surrounding[19], surrounding[18], surrounding[9])
                        let occ2 = get_occlusion(surrounding[9], surrounding[0], surrounding[1])
                        let occ3 = get_occlusion(surrounding[1], surrounding[2], surrounding[11])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 1, y + 1, z + 0, block.color(), occ0))
                        vertices.append(get_vertex(x + 0, y + 1, z + 0, block.color(), occ1))
                        vertices.append(get_vertex(x + 0, y + 1, z + 1, block.color(), occ2))
                        vertices.append(get_vertex(x + 1, y + 1, z + 1, block.color(), occ3))
                    }
                    
                    if !surrounding[14] {
                        // East face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[17], surrounding[26], surrounding[23])
                        let occ1 = get_occlusion(surrounding[23], surrounding[20], surrounding[11])
                        let occ2 = get_occlusion(surrounding[11], surrounding[2], surrounding[5])
                        let occ3 = get_occlusion(surrounding[5], surrounding[8], surrounding[17])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 1, y + 0, z + 0, block.color(), occ0))
                        vertices.append(get_vertex(x + 1, y + 1, z + 0, block.color(), occ1))
                        vertices.append(get_vertex(x + 1, y + 1, z + 1, block.color(), occ2))
                        vertices.append(get_vertex(x + 1, y + 0, z + 1, block.color(), occ3))
                    }
                    
                    if !surrounding[16] {
                        // South face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[15], surrounding[24], surrounding[25])
                        let occ1 = get_occlusion(surrounding[25], surrounding[26], surrounding[17])
                        let occ2 = get_occlusion(surrounding[17], surrounding[8], surrounding[7])
                        let occ3 = get_occlusion(surrounding[7], surrounding[6], surrounding[15])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 0, y + 0, z + 0, block.color(), occ0))
                        vertices.append(get_vertex(x + 1, y + 0, z + 0, block.color(), occ1))
                        vertices.append(get_vertex(x + 1, y + 0, z + 1, block.color(), occ2))
                        vertices.append(get_vertex(x + 0, y + 0, z + 1, block.color(), occ3))
                    }
                    
                    if !surrounding[12] {
                        // West face
                        
                        //3 - 2
                        //| ╲ |
                        //0 - 1
                        
                        let occ0 = get_occlusion(surrounding[9], surrounding[18], surrounding[21])
                        let occ1 = get_occlusion(surrounding[21], surrounding[24], surrounding[15])
                        let occ2 = get_occlusion(surrounding[15], surrounding[6], surrounding[3])
                        let occ3 = get_occlusion(surrounding[3], surrounding[0], surrounding[9])
                        
                        indices.appendContentsOf(get_face(UInt32(vertices.count), abs(occ0 - occ2) < abs(occ1 - occ3)))
                        
                        vertices.append(get_vertex(x + 0, y + 1, z + 0, block.color(), occ0))
                        vertices.append(get_vertex(x + 0, y + 0, z + 0, block.color(), occ1))
                        vertices.append(get_vertex(x + 0, y + 0, z + 1, block.color(), occ2))
                        vertices.append(get_vertex(x + 0, y + 1, z + 1, block.color(), occ3))
                    }
                }
            }
        }
        
        let vertex_buffer = self.device.newBufferWithLength(vertices.count * sizeof(Vertex), options: .CPUCacheModeWriteCombined)
        let index_buffer = self.device.newBufferWithLength(indices.count * sizeof(UInt32), options: .CPUCacheModeWriteCombined)
        
        vertex_buffer.label = "Vertices"
        index_buffer.label = "Indices"
        
        let vData = UnsafeMutablePointer<Vertex>(vertex_buffer.contents())
        vData.initializeFrom(vertices)
        let iData = UnsafeMutablePointer<UInt32>(index_buffer.contents())
        iData.initializeFrom(indices)
        
        let chunk_offset_buffer = self.device.newBufferWithLength(2 * sizeof(Float), options: .CPUCacheModeWriteCombined)
        chunk_offset_buffer.label = "Chunk Offset"
        
        let coData = UnsafeMutablePointer<Float>(chunk_offset_buffer.contents())
        coData.initializeFrom([Float(chunk_pos.x), Float(chunk_pos.y)])
        
        self.meshes[chunk_pos] = (vertex_buffer, index_buffer, indices.count, chunk_offset_buffer)
    }
    
    /*
     
     vertexBuffer = device.newBufferWithLength(ConstantBufferSize, options: [])
     vertexBuffer.label = "vertices"
     
     let vertexColorSize = vertexData.count * sizeofValue(vertexColorData[0])
     vertexColorBuffer = device.newBufferWithBytes(vertexColorData, length: vertexColorSize, options: [])
     vertexColorBuffer.label = "colors"*/
    
    /*// vData is pointer to the MTLBuffer's Float data contents
     //        let pData = vertexBuffer.contents()
     //        let vData = UnsafeMutablePointer<Float>(pData + 256*bufferIndex)
     
     // reset the vertices to default before adding animated offsets
     //        vData.initializeFrom(vertexData)
     
     // Animate triangle offsets
     //        let lastTriVertex = 24
     //        let vertexSize = 4
     //        for j in 0..<MaxBuffers {
     //            // update the animation offsets
     //            xOffset[j] += xDelta[j]
     //
     //            if(xOffset[j] >= 1.0 || xOffset[j] <= -1.0) {
     //                xDelta[j] = -xDelta[j]
     //                xOffset[j] += xDelta[j]
     //            }
     //
     //            yOffset[j] += yDelta[j]
     //
     //            if(yOffset[j] >= 1.0 || yOffset[j] <= -1.0) {
     //                yDelta[j] = -yDelta[j]
     //                yOffset[j] += yDelta[j]
     //            }
     //
     //            // Update last triangle position with updated animated offsets
     //            let pos = lastTriVertex + j*vertexSize
     //            vData[pos] = xOffset[j]
     //            vData[pos+1] = yOffset[j]
     //        }
     */
}

struct Vertex {
    var x: UInt8
    var y: UInt8
    var z: UInt8
    var occlusion: UInt8
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}
