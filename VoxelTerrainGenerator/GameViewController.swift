//
//  GameViewController.swift
//  VoxelTerrainGenerator
//
//  Created by Adalynn Dudney on 7/22/16.
//  Copyright © 2016 mystise. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import GLKit

class GameViewController:UIViewController, MTKViewDelegate {
    var scheduler: Scheduler! = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let device = MTLCreateSystemDefaultDevice()
        guard device != nil else { // Fallback to a blank UIView, an application could also fallback to OpenGL ES here.
            print("Metal is not supported on this device")
            self.view = UIView(frame: self.view.frame)
            return
        }

        // setup view properties
        let view = self.view as! MTKView
        view.device = device
        view.delegate = self
        view.preferredFramesPerSecond = 60
        
        // load any resources required for rendering
        
        self.scheduler = Scheduler(seed: UInt32(NSDate().timeIntervalSinceReferenceDate), view: view)
    }
    
    func drawInMTKView(view: MTKView) {
        self.scheduler.update()
    }
    
    
    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}
