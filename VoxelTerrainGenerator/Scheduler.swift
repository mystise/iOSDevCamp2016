//
//  Scheduler.swift
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

import Foundation

let TIMESTEP: Float64 = 1.0/60.0
let RADIUS: Int32 = 10

class Scheduler {
    private var meshes: Dictionary<ChunkPosition, ()> = [:]
    private var chunks: Dictionary<ChunkPosition, Chunk> = [:]
    private var dirty_chunks: Set<ChunkPosition> = []
    private var unpopulated_chunks: Set<ChunkPosition> = []
    private var ungenerated_chunks: Set<ChunkPosition> = []
    private let seed: UInt32
    private var camera_pos: (Float32, Float32) = (0.0, 0.0) // (Y, Z), X = 0
    private var time: Float64 = 0.0
    private let height_noise: Brownian
    private let dirt_noise: OpenSimplex
    
    var camera_speed: Float32 = 0.0
    
    init(seed: UInt32) {
        self.seed = seed
        self.height_noise = Brownian(seed: self.seed, octaves: 4, frequency: 1.0/150.0)
        self.dirt_noise = OpenSimplex(seed: self.seed)
    }
    
    func update(dt: Float64) {
        self.time += dt
        if self.time >= 1.0 { // If we're lagging behind, only do one tick
            self.time = TIMESTEP
        }
        while self.time >= TIMESTEP {
            self.time -= TIMESTEP
            
            let old_camera_pos = Int32(self.camera_pos.0) / 16
            self.camera_pos.0 += self.camera_speed * Float32(TIMESTEP)
            let new_camera_pos = Int32(self.camera_pos.0) / 16
            if old_camera_pos != new_camera_pos {
                var removed: Array<ChunkPosition> = []
                for chunk_pos in self.chunks.keys {
                    if chunk_pos.x < -RADIUS ||
                        chunk_pos.x > RADIUS + 1 ||
                        chunk_pos.y < new_camera_pos - RADIUS ||
                        chunk_pos.y > new_camera_pos + RADIUS + 1 {
                        removed.append(chunk_pos)
                    }
                }
                
                for chunk_pos in removed {
                    self.chunks.removeValueForKey(chunk_pos)
                    self.unpopulated_chunks.remove(chunk_pos)
                    self.ungenerated_chunks.remove(chunk_pos)
                    self.dirty_chunks.remove(chunk_pos)
                    // TODO: Remove mesh as well
                }
                
                for x_pos in -RADIUS...RADIUS {
                    for y_pos in new_camera_pos - RADIUS...new_camera_pos + RADIUS {
                        let chunk_pos = ChunkPosition(x: x_pos, y: y_pos)
                        if !self.chunks.keys.contains(chunk_pos) {
                            self.ungenerated_chunks.insert(chunk_pos)
                        }
                    }
                }
            }
            
            // TODO: If fast enough, do more than one per tick
            
            if let chunk_pos = self.ungenerated_chunks.popFirst() {
                self.chunks[chunk_pos] = self.generate_chunk(chunk_pos)
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
                self.dirty_chunks.insert(chunk_pos)
            }
            
            if let _ = self.dirty_chunks.popFirst() {
                // TODO: Mesh chunk
            }
        }
    }
    
    func generate_chunk(chunk_pos: ChunkPosition) -> Chunk {
        let output = Chunk()
        
        for x in Int32(0)..<16 {
            for y in Int32(0)..<16 {
                let xy_pos = (chunk_pos.x * 16 + x, chunk_pos.y * 16 + y)
                
                var noise = self.height_noise.gen(Float64(xy_pos.0), Float64(xy_pos.1))
                let height = Int32((noise + 1.0) / 2.0 * 32.0 + 16.0)
                
                for z in Int32(0)..<height {
                    output.set(UInt32(x), y: UInt32(y), z: UInt32(z), block: .Stone)
                }
                
                let scale = 32.0
                noise = self.dirt_noise.gen(Float64(xy_pos.0) / scale, Float64(xy_pos.1) / scale)
                let dirt_height = Int32((noise + 1.0) / 2.0 * 8.0 - 1.0)
                
                for z in height - dirt_height..<height {
                    output.set(UInt32(x), y: UInt32(y), z: UInt32(z), block: .Dirt)
                }
                
                if dirt_height > 0 {
                    output.set(UInt32(x), y: UInt32(y), z: UInt32(height), block: .Grass)
                }
                
                for z in height..<32 {
                    output.set(UInt32(x), y: UInt32(y), z: UInt32(z), block: .Water)
                }
            }
        }
        
        return output
    }
    
    func populate_chunk(chunk_pos: ChunkPosition) {
        let chunk = self.chunks[chunk_pos]!
        
        srand((UInt32(chunk_pos.x) &* 0x0CFF235B) &+ (UInt32(chunk_pos.y) &* 0x4F72AC03) &+ seed)
        
        for _ in 0..<rand() % 12 {
            let block_x = UInt32(rand() % 16)
            let block_y = UInt32(rand() % 16)
            
            var zpos: UInt32 = 0
            for z in (UInt32(0)...127).reverse() {
                if chunk.get(block_x, y: block_y, z: z) != .Air {
                    zpos = z
                    break
                }
            }
            
            if chunk.get(block_x, y: block_y, z: zpos) != .Grass {
                continue
            }
            
            let tree_height = UInt32((rand() % 5) + 5)
            
            for z in zpos + 1 ..< zpos + tree_height + 1 {
                chunk.set(block_x, y: block_y, z: z, block: .Log)
            }
            
            let check_set_leaf = { (pos: WorldPosition) in
                let chunk = self.chunks[pos.chunk_pos]!
                if chunk.get(pos.block_pos.x, y: pos.block_pos.y, z: pos.block_pos.z) == .Air {
                    chunk.set(pos.block_pos.x, y: pos.block_pos.y, z: pos.block_pos.z, block: .Leaf)
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
}
