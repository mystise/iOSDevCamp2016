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
    
    var camera_speed: Float32 = 0.0
    
    init(seed: UInt32) {
        self.seed = seed
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
            
            for _ in self.unpopulated_chunks {
                // TODO: Check for surrounding chunks, if found early exit
                
            }
            
            if let _ = self.dirty_chunks.popFirst() {
                // TODO: Mesh chunk
            }
        }
    }
    
    func generate_chunk(chunk_pos: ChunkPosition) -> Chunk {
        return Chunk()
    }
}
