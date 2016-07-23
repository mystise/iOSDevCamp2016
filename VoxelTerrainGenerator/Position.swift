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
    private(set) var x: UInt32
    private(set) var y: UInt32
    private(set) var z: UInt32
    
    private(set) var chunk_pos: ChunkPosition
}
