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
    func statusChange(_ status: String)
    func captureDepth(_ image: UIImage!)
    func captureImage(_ image: UIImage!)
    func captureStats(_ centerDepth: Float)
    func captureAttitude(_ attitude: CMAttitude)
    func saveComplete();
}

enum CaptureRes {
    case single
    case double
    case quad
    case full
}

class StructureSensor : NSObject, STSensorControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var toRGBA : STDepthToRgba?
    var sensorObserver : SensorObserverDelegate!
    var captureSession : AVCaptureSession?
    var videoDevice : AVCaptureDevice?
    var saveNextCapture = false
    let controller : STSensorController
    let motionManager = CMMotionManager()
    var attitude : CMAttitude?
    var prevDepth : [[Float]] = []
    let prevCount = 5
    let highRes : [Int32] = [2592, 1936]
    let baseRes : [Int32] = [640, 480]
    let doubleRes : [Int32] = [1280, 960]
    let quadRes : [Int32] = [2560, 1920]
    var captureRes = CaptureRes.quad;
    
    init(observer: SensorObserverDelegate!) {
        controller = STSensorController.shared()
        sensorObserver = observer
        
        super.init()
        
        controller.delegate = self
        
        tryInitializeSensor()
        
        motionManager.startDeviceMotionUpdates(
            using: CMAttitudeReferenceFrame.xMagneticNorthZVertical,
            to: OperationQueue.current!,
            withHandler: { motion, error in
                self.attitude = motion?.attitude
                if let att = self.attitude {
                    self.sensorObserver.captureAttitude(att)
                }
            }
        )
    }
    
    @discardableResult
    func tryInitializeSensor() -> Bool {
        let result = STSensorController.shared().initializeSensorConnection()
        if result == .alreadyInitialized || result == .success {
            return true
        }
        return false
    }
    
    func tryStartStreaming() -> Bool {
        if tryInitializeSensor() {
            let options : [AnyHashable: Any] = [
                kSTStreamConfigKey: NSNumber(value: STStreamConfig.registeredDepth640x480.rawValue as Int),
                kSTFrameSyncConfigKey: NSNumber(value: STFrameSyncConfig.depthAndRgb.rawValue as Int),
                kSTHoleFilterEnabledKey: true,
                kSTColorCameraFixedLensPositionKey: 1.0
            ]
            do {
                try STSensorController.shared().startStreaming(options: options as [AnyHashable: Any])
                let toRGBAOptions : [AnyHashable: Any] = [
                    kSTDepthToRgbaStrategyKey : NSNumber(value: STDepthToRgbaStrategy.redToBlueGradient.rawValue as Int)
                ]
                toRGBA = STDepthToRgba(options: toRGBAOptions)
                startCamera()
                return true
            } catch let error as NSError {
                updateStatus(error.localizedDescription);
            }
        }
        return false
    }
    
    func checkCameraAuthorized() -> Bool {
        if AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo).count == 0 {
            return false;
        }
        
        let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        if status != AVAuthorizationStatus.authorized {
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) {
                (granted: Bool) in
                if granted {
                    DispatchQueue.main.async {
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
        captureSession!.sessionPreset = AVCaptureSessionPresetInputPriority
        
        videoDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)!
        assert(videoDevice != nil)
        
        if configureCamera(false) {
            do {
                let input = try AVCaptureDeviceInput(device: videoDevice!)
                captureSession!.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
                output.setSampleBufferDelegate(self, queue: DispatchQueue.main)
                captureSession!.addOutput(output)
            }
            catch let error as NSError{
                updateStatus(error.localizedDescription)
                return
            }
        }
        
        captureSession?.commitConfiguration()
        updateStatus("Camera configured")
    }
    
    @discardableResult
    func configureCamera(_ forCapture: Bool) -> Bool {
        if let device = videoDevice {
            do {
                try device.lockForConfiguration()
            }
            catch let error as NSError {
                updateStatus(error.localizedDescription)
                return false
            }
            
            if device.isExposureModeSupported(AVCaptureExposureMode.continuousAutoExposure) {
                device.exposureMode = AVCaptureExposureMode.continuousAutoExposure;
            }
            
            if device.isWhiteBalanceModeSupported(AVCaptureWhiteBalanceMode.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = AVCaptureWhiteBalanceMode.continuousAutoWhiteBalance
            }
            
            device.setFocusModeLockedWithLensPosition(1.0, completionHandler: nil)
            
            let res = captureRes == CaptureRes.single && !forCapture ?  baseRes : highRes;
            if selectCaptureFormat(device, width: res[0], height: res[1]) {
                updateStatus("Capture format set")
            } else {
                updateStatus("Capture format not set")
                device.unlockForConfiguration()
                return false
            }
            
            let frameDuration24FPS = CMTimeMake(1, 24);
            let frameDuration15FPS = CMTimeMake(1, 15);
            
            let activeFrameDuration = device.activeVideoMinFrameDuration;
            
            var targetFrameDuration = CMTimeMake(1, 30);
            
            // >0 if min duration > desired duration, in which case we need to increase our duration to the minimum
            // or else the camera will throw an exception.
            if 0 < CMTimeCompare(activeFrameDuration, targetFrameDuration) {
                // In firmware <= 1.1, we can only support frame sync with 30 fps or 15 fps.
                if (0 == CMTimeCompare(activeFrameDuration, frameDuration24FPS)) {
                    targetFrameDuration = frameDuration24FPS;
                } else {
                    targetFrameDuration = frameDuration15FPS;
                }
            }
            
            device.activeVideoMaxFrameDuration = targetFrameDuration
            device.activeVideoMinFrameDuration = targetFrameDuration
            
            device.unlockForConfiguration()
            
            return true
        }
        return false
    }
    
    func fourCharCodeFrom(_ string : String) -> FourCharCode {
        assert(string.characters.count == 4, "String length must be 4")
        var result : FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
    
    func selectCaptureFormat(_ device: AVCaptureDevice, width: Int32?=nil, height: Int32?=nil) -> Bool {
        for f in device.formats {
            let format = f as! AVCaptureDeviceFormat
            if let formatDesc = format.formatDescription {
                let fourCharCode = CMFormatDescriptionGetMediaSubType(formatDesc)
                if fourCharCode != fourCharCodeFrom("420f") {
                    continue
                }
                
                let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
                if let w = width {
                    if dims.width != w {
                        continue
                    }
                }
                if let h = height {
                    if dims.height != h {
                        continue
                    }
                }
            }
            device.activeFormat = format
            return true
        }
        return false
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
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        controller.frameSyncNewColorBuffer(sampleBuffer)
    }
    
    func updateStatus(_ status: String) {
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
    
    func sensorDidStopStreaming(_ reason: STSensorControllerDidStopStreamingReason)
    {
        updateStatus("Stopped Streaming");
        stopCamera()
    }
    
    func sensorDidLeaveLowPowerMode() {}
    
    func sensorBatteryNeedsCharging()
    {
        updateStatus("Low Battery");
    }
    
    func sensorDidOutputDepthFrame(_ depthFrame: STDepthFrame!) {
        renderDepth(depthFrame)
        forgetDepth()
    }
    
    func sensorDidOutputSynchronizedDepthFrame(_ depthFrame: STDepthFrame!, colorFrame: STColorFrame!) {
        renderDepth(depthFrame)
        if let image = imageFromSampleBuffer(colorFrame.sampleBuffer) {
            self.sensorObserver.captureImage(image)
            if saveNextCapture {
                save(depthFrame, color: image)
            }
        }
        forgetDepth()
    }
    
    func renderDepth(_ depthFrame: STDepthFrame) {
        let size : Int = (Int)(depthFrame.width * depthFrame.height)
        let buffer = UnsafeMutableBufferPointer<Float>(start: depthFrame.depthInMillimeters, count: size)
        prevDepth.append(Array(buffer))
        if let renderer = toRGBA {
            updateStatus("Showing Depth \(depthFrame.width)x\(depthFrame.height)");
            let pixels = renderer.convertDepthFrame(toRgba: depthFrame)
            if let image = imageFromPixels(pixels!, width: Int(renderer.width), height: Int(renderer.height)) {
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
    
    func imageFromSampleBuffer(_ sampleBuffer : CMSampleBuffer) -> UIImage? {
        if let cvPixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let coreImage = CIImage(cvPixelBuffer: cvPixels)
            let context = CIContext()
            let rect = CGRect(x: 0, y: 0, width: CGFloat(CVPixelBufferGetWidth(cvPixels)), height: CGFloat(CVPixelBufferGetHeight(cvPixels)))
            let cgImage = context.createCGImage(coreImage, from: rect)
            let image = UIImage(cgImage: cgImage!)
            return image
        }
        return nil
    }
    
    func imageFromPixels(_ pixels : UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))
        
        let provider = CGDataProvider(data: Data(bytes: UnsafePointer<UInt8>(pixels), count: width*height*4) as CFData)
        
        let image = CGImage(
            width: width,                       //width
            height: height,                      //height
            bitsPerComponent: 8,                           //bits per component
            bitsPerPixel: 8 * 4,                       //bits per pixel
            bytesPerRow: width * 4,                   //bytes per row
            space: colorSpace,                  //Quartz color space
            bitmapInfo: bitmapInfo,                  //Bitmap info (alpha channel?, order, etc)
            provider: provider!,                    //Source of data for bitmap
            decode: nil,                         //decode
            shouldInterpolate: false,                       //pixel interpolation
            intent: CGColorRenderingIntent.defaultIntent);     //rendering intent
        
        return UIImage(cgImage: image!)
    }
    
    func unitValueToByte(_ v : Double, max : UInt8) -> UInt8 {
        return UInt8(Double(max) * (v + 1) / 2)
    }
    
    func byteToUnitValue(_ v : UInt8, max : UInt8) -> Double {
        return (Double(v) / Double(max) * 2) - 1
    }
    
    func setPixel(_ image : inout [UInt8], offset : Int, r : UInt8, g : UInt8, b : UInt8, a : UInt8) -> Int {
        image[offset + 0] = r
        image[offset + 1] = g
        image[offset + 2] = b
        image[offset + 3] = a
        return 1
    }
    
    func renderDepthInMillimeters(_ depthFrame : STDepthFrame!) -> UIImage? {
        let byteMax = UInt8(255)
        let channels = 4
        let channelMax = 8 // Maximum value to encode in blue/green channels.
        let maxRedValue = byteMax - UInt8(channelMax) // Maximum value to encode in red channel.
        let channelsMax = channelMax * channelMax // Max encoded across blue/green
        let maxDepthValue = Float(maxRedValue) * Float(channelsMax) // Max encoded across all channels.
        var totalSize = depthFrame.width * depthFrame.height
        if captureRes == CaptureRes.full {
            let width = highRes[0]
            let rows = Int32(ceil(Float(totalSize) / Float(width)))
            totalSize = width * rows;
        }
        var offset = 0
        var imageData = [UInt8](repeating: byteMax, count: Int(totalSize) * channels)
        
        if let orientation = attitude?.quaternion {
            // Pixel 0 is red to signify presense of orientation.
            offset += setPixel(&imageData, offset: offset * channels, r: byteMax, g: 0, b: 0, a: byteMax)
            // Pixel 1 encodes orientation as a quaternion.
            offset += setPixel(&imageData, offset: offset * channels,
                               r: unitValueToByte(orientation.x, max: byteMax),
                               g: unitValueToByte(orientation.y, max: byteMax),
                               b: unitValueToByte(orientation.z, max: byteMax),
                               a: unitValueToByte(orientation.w, max: byteMax)
            )
            
            // Pixel 2 is red to signify presense of additional encodings
            offset += setPixel(&imageData, offset: offset * channels, r: byteMax, g: 0, b: 0, a: byteMax)
            // Pixel 3 encodes roll/pitch/yaw
            offset += setPixel(&imageData, offset: offset * channels,
                               r: unitValueToByte(attitude!.roll  / Double.pi, max: byteMax),
                               g: unitValueToByte(attitude!.pitch / Double.pi, max: byteMax),
                               b: unitValueToByte(attitude!.yaw   / Double.pi, max: byteMax),
                               a: byteMax
            )
            // Pixels 4, 5 & 6 encode rotation matrix
            let matrix = attitude!.rotationMatrix
            offset += setPixel(&imageData, offset: offset * channels,
                               r: unitValueToByte(matrix.m11, max: byteMax),
                               g: unitValueToByte(matrix.m12, max: byteMax),
                               b: unitValueToByte(matrix.m13, max: byteMax),
                               a: byteMax
            )
            offset += setPixel(&imageData, offset: offset * channels,
                               r: unitValueToByte(matrix.m21, max: byteMax),
                               g: unitValueToByte(matrix.m22, max: byteMax),
                               b: unitValueToByte(matrix.m23, max: byteMax),
                               a: byteMax
            )
            offset += setPixel(&imageData, offset: offset * channels,
                               r: unitValueToByte(matrix.m31, max: byteMax),
                               g: unitValueToByte(matrix.m32, max: byteMax),
                               b: unitValueToByte(matrix.m33, max: byteMax),
                               a: byteMax
            )
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
        
        if captureRes == CaptureRes.full {
            return imageFromPixels(&imageData, width: Int(highRes[0]), height: Int(totalSize / highRes[0]))
        }
        return imageFromPixels(&imageData, width: Int(depthFrame.width), height: Int(depthFrame.height))
    }
    
    func saveNext() {
        saveNextCapture = true
        configureCamera(true)
    }
    
    func save(_ depthFrame: STDepthFrame!, color: UIImage!) {
        if let depth = renderDepthInMillimeters(depthFrame) {
            var height = max(color.size.height, depth.size.height)
            var size = CGSize(width: max(color.size.width, depth.size.width), height: 2 * height)
            if captureRes == CaptureRes.double {
                height = CGFloat(doubleRes[1])
                size = CGSize(width: CGFloat(doubleRes[0]), height: CGFloat(height * 2))
            } else if captureRes == CaptureRes.quad {
                height = CGFloat(quadRes[1])
                size = CGSize(width: CGFloat(quadRes[0]), height: CGFloat(height * 2))
            } else if captureRes == CaptureRes.full {
                height = CGFloat(highRes[1])
                size = CGSize(width: CGFloat(highRes[0]), height: CGFloat(height + depth.size.height))
            }
            UIGraphicsBeginImageContext(size)
            color.draw(in: CGRect(x: 0, y: 0, width: min(color.size.width, size.width), height: min(color.size.height, height)))
            let context = UIGraphicsGetCurrentContext()
            context!.interpolationQuality = CGInterpolationQuality.none
            depth.draw(in: CGRect(x: 0, y: height, width: size.width, height: size.height - height))
            let combined = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let imageData = UIImagePNGRepresentation(combined!) {
                if let png = UIImage(data: imageData) {
                    UIImageWriteToSavedPhotosAlbum(png, nil, nil, nil)
                    sensorObserver.saveComplete()
                    updateStatus("Captured image at \(Int(size.width))x\(Int(height))")
                }
            }
        }
        saveNextCapture = false
        configureCamera(false)
    }
}
