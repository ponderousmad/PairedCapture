//
//  RootViewController.swift
//  PairedCapture
//
//  Created by Adrian Smith on 2016-01-15.
//  Copyright © 2016 Adrian Smith. All rights reserved.
//

import UIKit

class RootViewController: UIViewController {
    
    var captureController : CaptureViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        if let controller = self.storyboard?.instantiateViewController(withIdentifier: "CaptureViewController") as? CaptureViewController {
            self.captureController = controller
            self.view.addSubview(self.captureController!.view)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    var modelController: ModelController {
        // Return the model controller object, creating it if necessary.
        // In more complex implementations, the model controller may be passed to the view controller.
        if _modelController == nil {
            _modelController = ModelController()
        }
        return _modelController!
    }

    var _modelController: ModelController? = nil
}

