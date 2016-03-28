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
    @IBOutlet weak var statsLabel: UILabel!
    @IBOutlet weak var captureCountLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var statusHistory: UILabel!
    var sensor : StructureSensor?
    var captureCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        statusHistory.lineBreakMode = .ByWordWrapping
        statusHistory.numberOfLines = 0
        statusHistory.hidden = true
        
        sensor = StructureSensor(observer: self);
        
        let statusSwipeDown = UISwipeGestureRecognizer(target: self, action: #selector(CaptureViewController.swipeStatus(_:)));
        statusSwipeDown.direction = .Down
        statusLabel.addGestureRecognizer(statusSwipeDown)
        let statusSwipeUp = UISwipeGestureRecognizer(target: self, action: #selector(CaptureViewController.swipeStatus(_:)));
        statusSwipeUp.direction = .Up
        statusLabel.addGestureRecognizer(statusSwipeUp)
    }
    
    func activateSensor() {
        sensor?.tryReconnect()
    }
    
    func swipeStatus(sender: UISwipeGestureRecognizer) {
        if (sender.direction == .Up) {
            statusHistory.hidden = true
        } else if(sender.direction == .Down) {
            statusHistory.hidden = false
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(CaptureViewController.activateSensor), name: UIApplicationWillEnterForegroundNotification, object: nil)
        
        activateSensor()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
    }
    
    func statusChange(status: String) {
        if statusLabel.text != status {
            statusLabel.text = status;
            if let text = statusHistory.text {
                statusHistory.text = text + "\n" + status
            } else {
                statusHistory.text = status;
            }
        }
    }
    
    func captureDepth(image: UIImage!) {
        capturedDepth.image = image
    }
    
    func captureImage(image: UIImage!) {
        capturedImage.image = image
    }
    
    func captureStats(centerDepth: Float) {
        statsLabel.text = "\(centerDepth / 1000.0) m"
    }
    
    func saveComplete() {
        captureCount += 1
        captureCountLabel.text = "Captures: \(captureCount)";
    }
    
    @IBAction func saveCapture(sender: AnyObject) {
        sensor?.saveNext()
    }
}
