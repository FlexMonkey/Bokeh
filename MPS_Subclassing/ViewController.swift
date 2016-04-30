//
//  ViewController.swift
//  MPS_Subclassing
//
//  Created by Simon Gladman on 29/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit
import MetalPerformanceShaders
import MetalKit

class ViewController: UIViewController, MTKViewDelegate
{
    // MARK: Metal Objects
    
    let device = MTLCreateSystemDefaultDevice()
 
    lazy var commandQueue: MTLCommandQueue =
    {
        return self.device!.newCommandQueue()
    }()
    
    lazy var imageTexture: MTLTexture =
    {
        let textureLoader = MTKTextureLoader(device: self.device!)
        let imageTexture:MTLTexture
        
        let sourceImage = UIImage(named: "DSC00773.jpg")!
        
        do
        {
            imageTexture = try textureLoader.newTextureWithCGImage(
                sourceImage.CGImage!,
                options: nil)
        }
        catch
        {
            fatalError("unable to create texture from image")
        }
        
        return imageTexture
    }()
    
    // MARK: UI Components
    
    lazy var imageView: MTKView =
    {
        let imageView = MTKView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 640),
            device: self.device!)
        
        imageView.framebufferOnly = false
        imageView.delegate = self
        
        return imageView
    }()
    
    // MARK: Metal Performance Shaders
    
    lazy var additionalCompositing: AdditionalCompositing =
    {
        let compositing =  AdditionalCompositing(device: self.device!)
        compositing.secondryTextureBrightness = 0.4
        
        return compositing
    }()
    
    lazy var threshold: MPSImageThresholdBinary =
    {
        return MPSImageThresholdBinary(
            device: self.device!,
            thresholdValue: 0.99,
            maximumValue: 1.0,
            linearGrayColorTransform: nil)
    }()
    
    lazy var dilate: MPSImageDilate =
    {
        var probe = [Float]()
        
        let size = 45
        let v = Float(size / 4)
        let h = v * sqrt(3.0)
        let mid = Float(size) / 2
        
        for i in 0 ..< size
        {
            for j in 0 ..< size
            {
                let x = abs(Float(i) - mid)
                let y = abs(Float(j) - mid)
                
                let element = Float((x > h || y > v * 2.0) ?
                    1.0 :
                    ((2.0 * v * h - v * x - h * y) >= 0.0) ? 0.0 : 1.0)
                
                probe.append(element)
            }
        }
        
        let dilate = MPSImageDilate(device: self.device!, kernelWidth: size, kernelHeight: size, values: probe)
        
        dilate.edgeMode = .Clamp
        
        return dilate
    }()
    
    lazy var rotate: MPSImageLanczosScale =
    {
        let scale = MPSImageLanczosScale(device: self.device!)
        
        var tx = MPSScaleTransform(
            scaleX: 1,
            scaleY: -1,
            translateX: 0,
            translateY: Double(-self.imageTexture.height))
        
        withUnsafePointer(&tx)
        {
            scale.scaleTransform = $0
        }
        
        return scale
    }()
    
    lazy var blur: MPSImageGaussianBlur =
    {
        return MPSImageGaussianBlur(device: self.device!, sigma: 5)
    }()
    
    // MARK: Layout
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.addSubview(imageView)
    }
    
    override func viewDidLayoutSubviews()
    {
        imageView.frame.origin.x = view.frame.midX - imageView.frame.midX
        imageView.frame.origin.y = view.frame.midY - imageView.frame.midY
    }

    // MARK: MTKViewDelegate
    
    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize)
    {
        
    }
    
    func drawInMTKView(view: MTKView)
    {
        if view.frame.size == CGSizeZero
        {
            return
        }
        
        guard let currentDrawable = view.currentDrawable where imageView.frame.size != CGSizeZero else
        {
            return
        }
        
        let commandQueue = device!.newCommandQueue()
        
        let commandBuffer = commandQueue.commandBuffer()
        
        let rotatedTexture = newTexture(imageTexture.width, height: imageTexture.height)
        let thresholdTexture = newTexture(imageTexture.width, height: imageTexture.height)
        let dilatedTexture = newTexture(imageTexture.width, height: imageTexture.height)
        let compositedTexture = newTexture(imageTexture.width, height: imageTexture.height)
        
        rotate.encodeToCommandBuffer(
            commandBuffer,
            sourceTexture: imageTexture,
            destinationTexture: rotatedTexture)
        
        threshold.encodeToCommandBuffer(
            commandBuffer,
            sourceTexture: rotatedTexture,
            destinationTexture: thresholdTexture)
        
        dilate.encodeToCommandBuffer(
            commandBuffer,
            sourceTexture: thresholdTexture,
            destinationTexture: dilatedTexture)
        
        additionalCompositing.encodeToCommandBuffer(
            commandBuffer,
            primaryTexture: rotatedTexture,
            secondaryTexture: dilatedTexture,
            destinationTexture: compositedTexture)
        
        blur.encodeToCommandBuffer(
            commandBuffer,
            sourceTexture: compositedTexture,
            destinationTexture: currentDrawable.texture)
        
        commandBuffer.presentDrawable(imageView.currentDrawable!)
        
        commandBuffer.commit();
    }
    
    func newTexture(width: Int, height: Int) -> MTLTexture
    {
        let textureDesciptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
            MTLPixelFormat.RGBA8Unorm,
            width: imageTexture.width,
            height: imageTexture.height,
            mipmapped: false)
        
        let texture = device!.newTextureWithDescriptor(textureDesciptor)

        return texture
    }
}

class AdditionalCompositing: MPSBinaryImageKernel
{
    var secondryTextureBrightness: Float = 0.2
    
    override init(device: MTLDevice)
    {
        super.init(device: device)
    }
    
    lazy var defaultLibrary: MTLLibrary =
    {
        return self.device.newDefaultLibrary()!
    }()
    
    lazy var pipelineState: MTLComputePipelineState =
    {
        let kernelFunction = self.defaultLibrary.newFunctionWithName("additionalCompositing")!
        
        do
        {
            let pipelineState = try self.device.newComputePipelineStateWithFunction(kernelFunction)
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create pipeline state for additionalCompositing")
        }
    }()
    
    lazy var threadsPerThreadgroup: MTLSize =
    {
        let maxTotalThreadsPerThreadgroup = Double(self.pipelineState.maxTotalThreadsPerThreadgroup)
        let threadExecutionWidth = Double(self.pipelineState.threadExecutionWidth)
        
        let threadsPerThreadgroupSide = 0.stride(
            to: Int(sqrt(maxTotalThreadsPerThreadgroup)),
            by: 1).reduce(16)
            {
                return (Double($1 * $1) / threadExecutionWidth) % 1 == 0 ? $1 : $0
            }
        
        return MTLSize(
            width:threadsPerThreadgroupSide,
            height:threadsPerThreadgroupSide,
            depth:1)
    }()
    
    override func encodeToCommandBuffer(commandBuffer: MTLCommandBuffer,
                                        inPlacePrimaryTexture: UnsafeMutablePointer<MTLTexture?>,
                                        secondaryTexture: MTLTexture,
                                        fallbackCopyAllocator copyAllocator: MPSCopyAllocator?) -> Bool
    {
        fatalError("not implemented")
    }
    
    override func encodeToCommandBuffer(commandBuffer: MTLCommandBuffer,
                                        primaryTexture: MTLTexture,
                                        inPlaceSecondaryTexture: UnsafeMutablePointer<MTLTexture?>,
                                        fallbackCopyAllocator copyAllocator: MPSCopyAllocator?) -> Bool {
        fatalError("not implemented")
    }
    
    override func encodeToCommandBuffer(commandBuffer: MTLCommandBuffer,
                                        primaryTexture: MTLTexture,
                                        secondaryTexture: MTLTexture,
                                        destinationTexture: MTLTexture)
    {
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        
        commandEncoder.setTexture(primaryTexture, atIndex: 0)
        commandEncoder.setTexture(secondaryTexture, atIndex: 1)
        commandEncoder.setTexture(destinationTexture, atIndex: 2)
        
        let buffer = device.newBufferWithBytes(
            &secondryTextureBrightness,
            length: sizeof(Float),
            options: MTLResourceOptions.CPUCacheModeDefaultCache)
        
        commandEncoder.setBuffer(buffer, offset: 0, atIndex: 0)
        
        let threadgroupsPerGrid = MTLSizeMake(
            destinationTexture.width / threadsPerThreadgroup.width,
            destinationTexture.height / threadsPerThreadgroup.height, 1)
        
        commandEncoder.dispatchThreadgroups(
            threadgroupsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
    }
}