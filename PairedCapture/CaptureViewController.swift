//
//  CaptureViewController.swift
//  PairedCapture
//
//  Created by Adrian Smith on 2016-01-16.
//  Copyright © 2016 Adrian Smith. All rights reserved.
//

import Foundation

class CaptureViewController: UIViewController, SensorObserverDelegate {
    
    @IBOutlet weak var capturedImage: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    var sensor : StructureSensor?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        self.sensor = StructureSensor(observer: self);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    func statusChange(status: String) {
        statusLabel.text = status;
    }
    
    func captureImage(image: UIImage!) {
        capturedImage.image = image;
    }
}
