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
    @IBOutlet weak var capturedDepth: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var statusHistory: UILabel!
    var sensor : StructureSensor?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        statusHistory.lineBreakMode = .ByWordWrapping
        statusHistory.numberOfLines = 0
        
        sensor = StructureSensor(observer: self);
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
        if let text = statusHistory.text {
            statusHistory.text = text + "\n" + status
        } else {
            statusHistory.text = status;
        }
    }
    
    func captureDepth(image: UIImage!) {
        capturedDepth.image = image;
        
    }
    
    func captureImage(image: UIImage!) {
        capturedImage.image = image;
    }
}