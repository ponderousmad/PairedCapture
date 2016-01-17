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
    func captureImage(image: UIImage!)
}


class StructureSensor : NSObject, STSensorControllerDelegate {
    var toRGBA : STDepthToRgba?
    var sensorObserver : SensorObserverDelegate!
    
    init(observer: SensorObserverDelegate!) {
        super.init()
        self.sensorObserver = observer
        
        STSensorController.sharedController().delegate = self
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
                kSTStreamConfigKey: NSNumber(integer: STStreamConfig.Depth640x480.rawValue),
                kSTFrameSyncConfigKey: NSNumber(integer: STFrameSyncConfig.Off.rawValue),
                kSTHoleFilterConfigKey: true
            ]
            do {
                try STSensorController.sharedController().startStreamingWithOptions(options as [NSObject : AnyObject])
                let toRGBAOptions : [NSObject : AnyObject] = [
                    kSTDepthToRgbaStrategyKey : NSNumber(integer: STDepthToRgbaStrategy.RedToBlueGradient.rawValue)
                ]
                try toRGBA = STDepthToRgba(options: toRGBAOptions)
                return true
            } catch let error as NSError {
                print(error)
            }
        }
        return false
    }
    
    func updateStatus(status: String) {
        self.sensorObserver.statusChange(status);
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
    }
    
    func sensorDidLeaveLowPowerMode() {}
    
    func sensorBatteryNeedsCharging()
    {
        updateStatus("Low Battery");
    }
    
    func sensorDidOutputDepthFrame(depthFrame: STDepthFrame!) {
        if let renderer = toRGBA {
            updateStatus("Showing Depth \(depthFrame.width)x\(depthFrame.height)");
            let pixels = renderer.convertDepthFrameToRgba(depthFrame)
            if let image = imageFromPixels(pixels, width: Int(renderer.width), height: Int(renderer.height)) {
                self.sensorObserver.captureImage(image)
            }
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
