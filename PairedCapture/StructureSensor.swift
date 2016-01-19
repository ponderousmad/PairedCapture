//
//  StructureSensor.swift
//  PairedCapture
//
//  Created by Adrian Smith on 2016-01-15.
//  Copyright © 2016 Adrian Smith. All rights reserved.
//

import Foundation

protocol SensorObserverDelegate {
    func statusChange(status: String)
    func captureDepth(image: UIImage!)
    func captureImage(image: UIImage!)
}

class StructureSensor : NSObject, STSensorControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var toRGBA : STDepthToRgba?
    var sensorObserver : SensorObserverDelegate!
    var captureSession : AVCaptureSession?
    var videoDevice : AVCaptureDevice?
    let controller : STSensorController
    
    init(observer: SensorObserverDelegate!) {
        controller = STSensorController.sharedController()
        sensorObserver = observer
        
        super.init()
        
        controller.delegate = self
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
    }
    
    func sensorDidOutputSynchronizedDepthFrame(depthFrame: STDepthFrame!, andColorFrame: STColorFrame!) {
        renderDepth(depthFrame)
        renderCameraImage(andColorFrame.sampleBuffer)
    }
    
    func renderDepth(depthFrame: STDepthFrame) {
        if let renderer = toRGBA {
            updateStatus("Showing Depth \(depthFrame.width)x\(depthFrame.height)");
            let pixels = renderer.convertDepthFrameToRgba(depthFrame)
            if let image = imageFromPixels(pixels, width: Int(renderer.width), height: Int(renderer.height)) {
                self.sensorObserver.captureDepth(image)
            }
        }
    }
    
    func renderCameraImage(sampleBuffer: CMSampleBufferRef) {
        if let cvPixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let coreImage = CIImage(CVPixelBuffer: cvPixels)
            let context = CIContext()
            let rect = CGRectMake(0, 0, CGFloat(CVPixelBufferGetWidth(cvPixels)), CGFloat(CVPixelBufferGetHeight(cvPixels)))
            let cgImage = context.createCGImage(coreImage, fromRect: rect)
            let image = UIImage(CGImage: cgImage)
            self.sensorObserver.captureImage(image)
        }
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
}
