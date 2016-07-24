//
//  Chunk.swift
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

import Foundation

enum Block: UInt8 {
    case Air
    case Stone
    case Dirt
    case Grass
    case Log
    case Leaf
    case Water
    
    func color() -> (UInt8, UInt8, UInt8, UInt8) {
        // BOOOOOOOO Switches aren't expressions >:(
        switch self {
        case .Air: return (0x00, 0x00, 0x00, 0x00)
        case .Stone: return (0x70, 0x80, 0x90, 0xFF)
        case .Dirt: return (0x80, 0x46, 0x1B, 0xFF)
        case .Grass: return (0x0A, 0x85, 0x04, 0xFF)
        case .Log: return (0x4D, 0x33, 0x12, 0xFF)
        case .Leaf: return (0x17, 0x5C, 0x17, 0xFF)
        case .Water: return (0x00, 0x57, 0xFF, 0x5F)
        }
    }
}

class Chunk {
    private var blocks: [Block] = Array(count: 16*16*128, repeatedValue: .Air)
    
    func get(x: UInt32, _ y: UInt32, _ z: UInt32) -> Block {
        assert(x < 16 && y < 16 && z < 128, "Index out of bounds")
        return blocks[Int(x*16*16 + y*16 + z)]
    }
    
    func set(x: UInt32, _ y: UInt32, _ z: UInt32, block: Block) {
        assert(x < 16 && y < 16 && z < 128, "Index out of bounds")
        blocks[Int(x*16*16 + y*16 + z)] = block
    }
}
