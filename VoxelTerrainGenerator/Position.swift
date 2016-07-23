//
//  Position.swift
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

import Foundation

struct ChunkPosition {
    var x: Int32
    var y: Int32
    
    func north() -> ChunkPosition {
        return ChunkPosition(x: self.x + 0, y: self.y + 1)
    }
    
    func north_east() -> ChunkPosition {
        return ChunkPosition(x: self.x + 1, y: self.y + 1)
    }
    
    func east() -> ChunkPosition {
        return ChunkPosition(x: self.x + 1, y: self.y + 0)
    }
    
    func south_east() -> ChunkPosition {
        return ChunkPosition(x: self.x + 1, y: self.y - 1)
    }
    
    func south() -> ChunkPosition {
        return ChunkPosition(x: self.x + 0, y: self.y - 1)
    }
    
    func south_west() -> ChunkPosition {
        return ChunkPosition(x: self.x - 1, y: self.y - 1)
    }
    
    func west() -> ChunkPosition {
        return ChunkPosition(x: self.x - 1, y: self.y + 0)
    }
    
    func north_west() -> ChunkPosition {
        return ChunkPosition(x: self.x - 1, y: self.y + 1)
    }
}

extension ChunkPosition: Hashable {
    var hashValue: Int {
        get {
            return Int(self.x) | (Int(self.y) << 32)
        }
    }
}

func ==(lhs: ChunkPosition, rhs: ChunkPosition) -> Bool {
    return lhs.x == rhs.x && lhs.y == rhs.y
}

struct Position {
    var x: Int32
    var y: Int32
    var z: Int32
}

struct BlockPosition {
    var x: UInt32
    var y: UInt32
    var z: UInt32
}

struct WorldPosition {
    let block_pos: BlockPosition
    let chunk_pos: ChunkPosition
    
    init(block_pos: BlockPosition, chunk_pos: ChunkPosition) {
        self.block_pos = block_pos
        self.chunk_pos = chunk_pos
    }
    
    init(pos: Position) {
        let x = WorldPosition.convert(pos.x, 16)
        let y = WorldPosition.convert(pos.y, 16)
        let z = WorldPosition.clamp(pos.z, 128)
        
        self.block_pos = BlockPosition(x: x.0, y: y.0, z: z)
        self.chunk_pos = ChunkPosition(x: x.1, y: y.1)
    }
    
    private static func convert(val: Int32, _ divisor: Int32) -> (UInt32, Int32) {
        var mod = val
        var div = Int32(0)
        while mod < 0 {
            mod += divisor
            div -= 1
        }
        while mod >= divisor {
            mod -= divisor
            div += 1
        }
        return (UInt32(mod), div)
    }
    
    private static func clamp(val: Int32, _ max: Int32) -> UInt32 {
        if val < 0 {
            return 0
        }
        if val >= max {
            return UInt32(max - 1)
        }
        return UInt32(val)
    }
    
    func offset(x: Int32, y: Int32, z: Int32) -> WorldPosition {
        let block_x = Int32(self.block_pos.x) + x
        let block_y = Int32(self.block_pos.y) + y
        let block_z = Int32(self.block_pos.z) + z
        let chunk_x = self.chunk_pos.x
        let chunk_y = self.chunk_pos.y
        
        let x = WorldPosition.convert(block_x, 16)
        let y = WorldPosition.convert(block_y, 16)
        let z = WorldPosition.clamp(block_z, 128)
        
        return WorldPosition(block_pos: BlockPosition(x: x.0, y: y.0, z: z), chunk_pos: ChunkPosition(x: chunk_x + x.1, y: chunk_y + y.1))
    }
}
