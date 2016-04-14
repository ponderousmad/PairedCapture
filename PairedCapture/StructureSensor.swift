//
//  StructureSensor.swift
//  PairedCapture
//
//  Created by Adrian Smith on 2016-01-15.
//  Copyright © 2016 Adrian Smith. All rights reserved.
//

import Foundation
import CoreMotion

protocol SensorObserverDelegate {
    func statusChange(status: String)
    func captureDepth(image: UIImage!)
    func captureImage(image: UIImage!)
    func captureStats(centerDepth: Float)
    func saveComplete();
}

class StructureSensor : NSObject, STSensorControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var toRGBA : STDepthToRgba?
    var sensorObserver : SensorObserverDelegate!
    var captureSession : AVCaptureSession?
    var videoDevice : AVCaptureDevice?
    var saveNextCapture = false
    let controller : STSensorController
    let motionManager = CMMotionManager()
    var orientation : CMQuaternion?
    var prevDepth : [[Float]] = []
    let prevCount = 5
    
    init(observer: SensorObserverDelegate!) {
        controller = STSensorController.sharedController()
        sensorObserver = observer
        
        super.init()
        
        controller.delegate = self
        
        tryInitializeSensor()
        
        motionManager.startDeviceMotionUpdatesUsingReferenceFrame(
            CMAttitudeReferenceFrame.XMagneticNorthZVertical,
            toQueue: NSOperationQueue.currentQueue()!,
            withHandler:handleMotion
        )
    }
    
    func tryInitializeSensor() -> Bool {
        let result = STSensorController.sharedController().initializeSensorConnection()
        if result == .AlreadyInitialized || result == .Success {
            return true
        }
        return false
    }
    
    func tryStartStreaming() -> Bool {
        if tryInitializeSensor() {
            let options : [NSObject : AnyObject] = [
                kSTStreamConfigKey: NSNumber(integer: STStreamConfig.RegisteredDepth640x480.rawValue),
                kSTFrameSyncConfigKey: NSNumber(integer: STFrameSyncConfig.DepthAndRgb.rawValue),
                kSTHoleFilterConfigKey: true,
                kSTColorCameraFixedLensPositionKey: 1.0
            ]
            do {
                try STSensorController.sharedController().startStreamingWithOptions(options as [NSObject : AnyObject])
                let toRGBAOptions : [NSObject : AnyObject] = [
                    kSTDepthToRgbaStrategyKey : NSNumber(integer: STDepthToRgbaStrategy.RedToBlueGradient.rawValue)
                ]
                try toRGBA = STDepthToRgba(options: toRGBAOptions)
                startCamera()
                return true
            } catch let error as NSError {
                updateStatus(error.localizedDescription);
            }
        }
        return false
    }
    
    func checkCameraAuthorized() -> Bool {
        if AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).count == 0 {
            return false;
        }
        
        let status = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
        if status != AVAuthorizationStatus.Authorized {
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo) {
                (granted: Bool) in
                if granted {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.startCamera()
                    }
                }
            }
        }
        return true;
    }
    
    func setupCamera() {
        if captureSession != nil {
            return;
        }
        if !checkCameraAuthorized() {
            updateStatus("Camera access not granted")
            return
        }
        captureSession = AVCaptureSession()
        captureSession!.beginConfiguration()
        captureSession!.sessionPreset = AVCaptureSessionPreset640x480
        
        videoDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)!
        assert(videoDevice != nil);
        
        if let device = videoDevice {
            do {
                try device.lockForConfiguration()
            }
            catch let error as NSError {
                updateStatus(error.localizedDescription)
                return
            }
            
            if device.isExposureModeSupported(AVCaptureExposureMode.ContinuousAutoExposure) {
                device.exposureMode = AVCaptureExposureMode.ContinuousAutoExposure;
            }
            
            if device.isWhiteBalanceModeSupported(AVCaptureWhiteBalanceMode.ContinuousAutoWhiteBalance) {
                device.whiteBalanceMode = AVCaptureWhiteBalanceMode.ContinuousAutoWhiteBalance
            }
            
            device.setFocusModeLockedWithLensPosition(1.0, completionHandler: nil)
            device.unlockForConfiguration()

            do {
                let input = try AVCaptureDeviceInput(device: device)
                captureSession!.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)]
                output.setSampleBufferDelegate(self, queue: dispatch_get_main_queue())
                captureSession!.addOutput(output)
            }
            catch let error as NSError{
                updateStatus(error.localizedDescription)
                return
            }
            
            do {
                try device.lockForConfiguration()
            }
            catch let error as NSError {
                updateStatus(error.localizedDescription)
            }
            device.activeVideoMaxFrameDuration = CMTimeMake(1,30)
            device.activeVideoMinFrameDuration = CMTimeMake(1,30)
            device.unlockForConfiguration()
        }
        captureSession?.commitConfiguration()
        updateStatus("Camera configured")
    }
    
    func startCamera() {
        setupCamera()
        
        if let session = captureSession {
            session.startRunning()
            updateStatus("Camera started")
        }
    }
    
    func stopCamera() {
        if let session = captureSession {
            session.stopRunning()
        }
        captureSession = nil
        
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        controller.frameSyncNewColorBuffer(sampleBuffer)
        // renderCameraImage(sampleBuffer)
    }
    
    func updateStatus(status: String) {
        sensorObserver.statusChange(status);
    }
    
    func tryReconnect() {
        if controller.isConnected() {
            sensorDidConnect()
        } else {
            sensorDidDisconnect()
        }
    }
    
    func sensorDidConnect() {
        if tryStartStreaming() {
            updateStatus("Streaming");
        } else {
            updateStatus("Connected");
        }
    }
    
    func sensorDidDisconnect()
    {
        updateStatus("Disconnected");
    }
    
    func sensorDidStopStreaming(reason: STSensorControllerDidStopStreamingReason)
    {
        updateStatus("Stopped Streaming");
        stopCamera()
    }
    
    func sensorDidLeaveLowPowerMode() {}
    
    func sensorBatteryNeedsCharging()
    {
        updateStatus("Low Battery");
    }
    
    func sensorDidOutputDepthFrame(depthFrame: STDepthFrame!) {
        renderDepth(depthFrame)
        forgetDepth()
    }
    
    func sensorDidOutputSynchronizedDepthFrame(depthFrame: STDepthFrame!, andColorFrame: STColorFrame!) {
        renderDepth(depthFrame)
        if let image = imageFromSampleBuffer(andColorFrame.sampleBuffer) {
            self.sensorObserver.captureImage(image)
            if saveNextCapture {
                save(depthFrame, color: image)
            }
        }
        forgetDepth()
    }
    
    func renderDepth(depthFrame: STDepthFrame) {
        let size : Int = (Int)(depthFrame.width * depthFrame.height)
        let buffer = UnsafeMutableBufferPointer<Float>(start: depthFrame.depthInMillimeters, count: size)
        prevDepth.append(Array(buffer))
        if let renderer = toRGBA {
            updateStatus("Showing Depth \(depthFrame.width)x\(depthFrame.height)");
            let pixels = renderer.convertDepthFrameToRgba(depthFrame)
            if let image = imageFromPixels(pixels, width: Int(renderer.width), height: Int(renderer.height)) {
                self.sensorObserver.captureDepth(image)
            }
            
            let offset = Int((depthFrame.height * (depthFrame.width + 1)) / 2)
            self.sensorObserver.captureStats(depthFrame.depthInMillimeters[offset])
        }
    }
    
    func forgetDepth() {
        if prevDepth.count > prevCount {
            prevDepth.removeFirst()
        }
    }
    
    func imageFromSampleBuffer(sampleBuffer : CMSampleBufferRef) -> UIImage? {
        if let cvPixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let coreImage = CIImage(CVPixelBuffer: cvPixels)
            let context = CIContext()
            let rect = CGRectMake(0, 0, CGFloat(CVPixelBufferGetWidth(cvPixels)), CGFloat(CVPixelBufferGetHeight(cvPixels)))
            let cgImage = context.createCGImage(coreImage, fromRect: rect)
            let image = UIImage(CGImage: cgImage)
            return image
        }
        return nil
    }
    
    func imageFromPixels(pixels : UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        let bitmapInfo = CGBitmapInfo.ByteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.NoneSkipLast.rawValue))
        
        let provider = CGDataProviderCreateWithCFData(NSData(bytes:pixels, length: width*height*4))
        
        let image = CGImageCreate(
            width,                       //width
            height,                      //height
            8,                           //bits per component
            8 * 4,                       //bits per pixel
            width * 4,                   //bytes per row
            colorSpace,                  //Quartz color space
            bitmapInfo,                  //Bitmap info (alpha channel?, order, etc)
            provider,                    //Source of data for bitmap
            nil,                         //decode
            false,                       //pixel interpolation
            CGColorRenderingIntent.RenderingIntentDefault);     //rendering intent
        
        return UIImage(CGImage: image!)
    }
    
    func quaternionValueToByte(v : Double, max : UInt8) -> UInt8 {
        return UInt8(Double(max) * (v + 1) / 2)
    }
    
    func renderDepthInMillimeters(depthFrame : STDepthFrame!) -> UIImage? {
        let byteMax = UInt8(255)
        let channels = 4
        let channelMax = 8 // Maximum value to encode in blue/green channels.
        let maxRedValue = byteMax - UInt8(channelMax) // Maximum value to encode in red channel.
        let channelsMax = channelMax * channelMax // Max encoded across blue/green
        let maxDepthValue = Float(maxRedValue) * Float(channelsMax) // Max encoded across all channels.
        var offset = 0
        var imageData = [UInt8](count: Int(depthFrame.width * depthFrame.height) * channels, repeatedValue: byteMax)
        
        if let attitude = orientation {
            // Pixel 0 is red to signify presense of orientation.
            imageData[offset * channels + 0] = byteMax
            imageData[offset * channels  + 1] = 0
            imageData[offset * channels  + 2] = 0
            imageData[offset * channels  + 3] = byteMax
            offset += 1
            
            // Pixel 1 encodes orientation.
            imageData[offset * channels  + 0] = quaternionValueToByte(attitude.x, max: byteMax)
            imageData[offset * channels  + 1] = quaternionValueToByte(attitude.y, max: byteMax)
            imageData[offset * channels  + 2] = quaternionValueToByte(attitude.z, max: byteMax)
            imageData[offset * channels  + 3] = quaternionValueToByte(attitude.w, max: byteMax)
            offset += 1
        }
        
        for i in offset ..< Int(depthFrame.width * depthFrame.height) {
            var value : Float
            var prevFrame = prevDepth.count - 1
            repeat {
                value = prevDepth[prevFrame][i]
                prevFrame -= 1
            } while(value.isNaN && prevFrame >= 0)
            
            if value.isNaN {
                // Pure  black encodes unknown value.
                imageData[i * channels + 0] = 0
                imageData[i * channels + 1] = 0
                imageData[i * channels + 2] = 0
            } else {
                // Encode depth as integer between 0 to approx 2^14
                // White is close, and make the pixels 'almost' greyscale so
                // that you can get a rough idea of depth by eye.
                let depth = Int(max(0, min(value.isNaN ? 0 : value, maxDepthValue)))
                let red = maxRedValue - UInt8(depth / channelsMax) // approx 8 bits in red
                let low = depth % channelsMax // Lower 6 bits, of which
                let green = red + UInt8(low / channelMax) // three bits go in green
                let blue = red + UInt8(low % channelMax) // and three bits in blue.
                imageData[i * channels + 0] = red
                imageData[i * channels + 1] = green
                imageData[i * channels + 2] = blue
            }
        }
        
        return imageFromPixels(&imageData, width: Int(depthFrame.width), height: Int(depthFrame.height))
    }
    
    func saveNext() {
        saveNextCapture = true
    }
    
    func save(depthFrame: STDepthFrame!, color: UIImage!) {
        if let depth = renderDepthInMillimeters(depthFrame) {
            let size = CGSizeMake(max(color.size.width, depth.size.width), color.size.height + depth.size.height)
            UIGraphicsBeginImageContext(size)
            color.drawInRect(CGRectMake(0, 0, color.size.width, color.size.height))
            depth.drawInRect(CGRectMake(0, color.size.height, depth.size.width, depth.size.height))
            let combined = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let imageData = UIImagePNGRepresentation(combined) {
                if let png = UIImage(data: imageData) {
                    UIImageWriteToSavedPhotosAlbum(png, nil, nil, nil)
                    sensorObserver.saveComplete()
                }
            }
        }
        saveNextCapture = false
    }
    
    func handleMotion(motion: CMDeviceMotion?, error: NSError?)
    {
        if let attitude = motion?.attitude {
            orientation = attitude.quaternion
        }
    }

}
