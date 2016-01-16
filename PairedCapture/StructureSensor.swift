//
//  StructureSensor.swift
//  PairedCapture
//
//  Created by Adrian Smith on 2016-01-15.
//  Copyright © 2016 Adrian Smith. All rights reserved.
//

import Foundation

class StructureSensor : NSObject, STSensorControllerDelegate {
     func sensorDidConnect() {}
     func sensorDidDisconnect() {}
     func sensorDidStopStreaming(reason: STSensorControllerDidStopStreamingReason) {}
     func sensorDidLeaveLowPowerMode() {}
     func sensorBatteryNeedsCharging() {}
}