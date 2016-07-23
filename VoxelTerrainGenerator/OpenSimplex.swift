// Copyright 2013 The Noise-rs Developers.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Ported to Swift by mystise

import Foundation

private let OFFSET: Float64 = sqrt(3.0)

struct Brownian {
    private let noise: OpenSimplex
    private let octaves: UInt32
    private let frequency: Float64
    private let lacunarity: Float64
    private let persistence: Float64
    
    init(seed: UInt32, octaves: UInt32 = 1, frequency: Float64 = 1.0, lacunarity: Float64 = 2.2, persistence: Float64 = 0.5) {
        self.noise = OpenSimplex(seed: seed)
        self.octaves = octaves
        self.frequency = frequency
        self.lacunarity = lacunarity
        self.persistence = persistence
    }
    
    func gen(x: Float64, _ y: Float64) -> Float64 {
        var output = 0.0
        
        var offset = OFFSET
        var frequency = self.frequency
        var total_magnitude = 0.0
        var magnitude = 1.0
        for _ in 0..<self.octaves {
            output += self.noise.gen(x * frequency + offset, y * frequency + offset) * magnitude
            total_magnitude += magnitude
            
            frequency *= self.lacunarity
            magnitude *= self.persistence
            offset += OFFSET
        }
        
        return output / total_magnitude
    }
}

private let STRETCH: Float64 = (1 / sqrt(3.0) - 1) / 2
private let SQUISH: Float64 = (sqrt(3.0) - 1) / 2
private let NORM: Float64 = 1.0 / 14.0

// Implementation of OpenSimplex: http://uniblock.tumblr.com/post/97868843242/noise

struct OpenSimplex {
    private let perm: [UInt8]
    
    init(seed: UInt32) {
        srand(seed)
        var perm: [UInt8] = (Int(0)...255).map { (x) -> UInt8 in UInt8(x) }
        for i in (1...255).reverse() {
            perm[i] = perm[Int(rand() % (i + 1))]
        }
        
        self.perm = perm
    }
    
    func gen(x: Float64, _ y: Float64) -> Float64 {
        let stretch_offset = (x + y) * STRETCH
        let xs = x + stretch_offset
        let ys = y + stretch_offset
        var xs_floor = floor(xs)
        var ys_floor = floor(ys)
        let squish_offset = (xs_floor + ys_floor) * SQUISH
        let x_floor = xs_floor + squish_offset
        let y_floor = ys_floor + squish_offset
        let xs_frac = xs - xs_floor
        let ys_frac = ys - ys_floor
        let frac_sum = xs_frac + ys_frac
        var dx0 = x - x_floor
        var dy0 = y - y_floor
        var value = 0.0
        
        let dx1 = dx0 - 1.0 - SQUISH
        let dy1 = dy0 - SQUISH
        value += gradient(xs_floor + 1.0, ys_floor: ys_floor, dx: dx1, dy: dy1)
        
        let dx2 = dx1 + 1.0
        let dy2 = dy1 - 1.0
        value += gradient(xs_floor, ys_floor: ys_floor + 1, dx: dx2, dy: dy2)
        
        if frac_sum > 1.0 {
            xs_floor += 1.0
            ys_floor += 1.0
            
            dx0 = dx1 - SQUISH
            dy0 = dy2 - SQUISH
        }
        value += gradient(xs_floor, ys_floor: ys_floor, dx: dx0, dy: dy1)
        
        return value * NORM
    }
    
    private func gradient(xs_floor: Float64, ys_floor: Float64, dx: Float64, dy: Float64) -> Float64 {
        let attn = 2.0 - dx * dx - dy * dy
        if attn > 0.0 {
            let index = Int(self.perm[Int(self.perm[Int(xs_floor) & 0xFF]) ^ (Int(ys_floor) & 0xFF)])
            let norm = 1.0 / sqrt(2.0)
            let vec: (Float64, Float64)
            switch index % 8 {
            case 0: vec = ( 1.0,  0.0)
            case 1: vec = (-1.0,  0.0)
            case 2: vec = ( 0.0,  1.0)
            case 3: vec = ( 0.0, -1.0)
            case 4: vec = ( norm,  norm)
            case 5: vec = (-norm,  norm)
            case 6: vec = ( norm, -norm)
            case 7: vec = (-norm, -norm)
            default: vec = (0.0, 0.0); assert(false, "Really?")
            }
            return attn * attn * attn * attn * (dx * vec.0 + dy * vec.1)
        }
        return 0.0
    }
}