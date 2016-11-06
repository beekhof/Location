//
//  ViewController.swift
//  LocationTester
//
//  Created by Andrew Beekhof on 2/10/16.
//  Copyright © 2016 Andrew Beekhof. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var filterMultiplier: UISegmentedControl!
    @IBOutlet weak var accuracy: UISegmentedControl!
    @IBOutlet weak var filter: UITextField!
    @IBOutlet weak var errorInfo: UILabel!
    @IBOutlet weak var info: UILabel!
    @IBOutlet weak var modeControl: UISegmentedControl!
    @IBOutlet weak var flavorControl: UISegmentedControl!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)

        print(UserDefaults.standard.dictionaryRepresentation())
        
        modeControl.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "option.mode")
        AppDelegate.shared?.manager.setMode(value: GPSManager.Mode(rawValue: modeControl.selectedSegmentIndex)!, reason: #function)

        if UserDefaults.standard.integer(forKey: "option.flavour") > 0 {
            flavorControl.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "option.flavour")
            AppDelegate.shared?.manager.setFlavour(value: GPSManager.Flavour(rawValue: flavorControl.selectedSegmentIndex)!, reason: #function)
        }

        accuracy.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "option.accuracy")
        self.setAccuracy(index: accuracy.selectedSegmentIndex)

        filterMultiplier.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "option.factor")
        self.updateFactor(filterMultiplier)

        let types = UIUserNotificationType.alert //| UIUserNotificationType.badge | UIUserNotificationType.sound
        let mySettings = UIUserNotificationSettings.init(types: types, categories: nil)
        UIApplication.shared.registerUserNotificationSettings(mySettings)
        
        self.updateView()
        self.kickTimer(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
//        self.updateView()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func ChangeMode(_ sender: AnyObject) {
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: "option.mode")
        print("option.mode", UserDefaults.standard.integer(forKey: "option.mode"))
        AppDelegate.shared?.manager.setMode(value: GPSManager.Mode(rawValue: sender.selectedSegmentIndex)!, reason: #function)
        self.resetStats()
    }
    
    @IBAction func ChangeFlavor(_ sender: AnyObject) {
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: "option.flavour")
        print("option.flavour", UserDefaults.standard.integer(forKey: "option.flavour"))
        AppDelegate.shared?.manager.setFlavour(value: GPSManager.Flavour(rawValue: sender.selectedSegmentIndex)!, reason: #function)
        self.resetStats()
    }
    
    @IBAction func updateFactor(_ sender: AnyObject) {
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: "option.factor")
        print("option.factor", UserDefaults.standard.integer(forKey: "option.factor"))

        switch sender.selectedSegmentIndex {
        case 0:
            GPSManager.sharedInstance.manager.distanceFilter = kCLDistanceFilterNone
            break
        default:
            GPSManager.sharedInstance.manager.distanceFilter = GPSManager.sharedInstance.manager.desiredAccuracy * Double(sender.selectedSegmentIndex)
            print(GPSManager.sharedInstance.manager.distanceFilter, GPSManager.sharedInstance.manager.desiredAccuracy, Double(sender.selectedSegmentIndex))
        }
        self.resetStats()
    }

    @IBAction func ChangeAccuracy(_ sender: AnyObject) {
        self.setAccuracy(index: sender.selectedSegmentIndex)
        self.updateFactor(filterMultiplier)
        self.resetStats()
    }
    
    func setAccuracy(index: Int) {
        UserDefaults.standard.set(index, forKey: "option.accuracy")
        print("option.accuracy", UserDefaults.standard.integer(forKey: "option.accuracy"))

        switch index {
        case 5:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            break
        case 4:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyBest
            break
        case 3:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            break
        case 2:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            break
        case 1:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyKilometer
            break
        case 0:
            GPSManager.sharedInstance.manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            break
        default:
            AppDelegate.shared?.notification(withTitle: "Invalid accuracy", action: "ok", andBody: "Selected: \(index)")
            break
        }
    }

    var timer: Timer? = nil

    func kickTimer(force: Bool) {
        DispatchQueue.global().async(execute: {
        //DispatchQueue.main.async {
            if force || UIApplication.shared.applicationState == UIApplicationState.active {
                self.timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(self.updateStats), userInfo: nil, repeats: false)
                RunLoop.current.add(self.timer!, forMode: RunLoopMode.defaultRunLoopMode)
                RunLoop.current.run()
            }
        })
    }

    func applicationDidBecomeActive() {
        DispatchQueue.main.async {
            self.viewDidAppear(true)
            self.kickTimer(force: true)
        }
    }

    func applicationDidEnterBackground() {
        if timer != nil && timer!.isValid {
            timer!.invalidate()
        }
    }
    
    func updateStats() {
        if UIApplication.shared.applicationState != UIApplicationState.active {
            AppDelegate.shared?.notification(withTitle: "Background update", action: "ok", andBody: "Bad \(UIApplication.shared.applicationState)")
        }
        DispatchQueue.main.async {
            self.updateView()
            self.kickTimer(force: false)
        }
    }
    
    func resetStats() {
        AppDelegate.shared?.manager.callCount = 0
        AppDelegate.shared?.manager.lastSummary = Date()
        DispatchQueue.main.async {
            self.updateView()
        }
    }

    func updateView() {
        var mode = (AppDelegate.shared?.manager.mode.rawValue)!
        if mode < 0 {
            mode = 0
        }
        modeControl.selectedSegmentIndex = mode
        flavorControl.selectedSegmentIndex = (AppDelegate.shared?.manager.flavour.rawValue)!
        
        info.text = " \((AppDelegate.shared?.manager.callCount)!) calls in the last \(0-(AppDelegate.shared?.manager.lastSummary.timeIntervalSinceNow)!) seconds"
        if ((AppDelegate.shared?.manager.lastLocationError) != nil) {
            errorInfo.text = "Error \(AppDelegate.shared?.manager.lastLocationError?.errorCode): \(AppDelegate.shared?.manager.lastLocationError?.localizedDescription)"
            
        } else {
            errorInfo.text = "No error"
        }
        
        var factor: Int = 0
        
        if GPSManager.sharedInstance.manager.desiredAccuracy > 0 {
            factor = Int(GPSManager.sharedInstance.manager.distanceFilter / GPSManager.sharedInstance.manager.desiredAccuracy)
            print(GPSManager.sharedInstance.manager.distanceFilter, GPSManager.sharedInstance.manager.desiredAccuracy, factor)
        }
        
        if factor < filterMultiplier.numberOfSegments {
            print(GPSManager.sharedInstance.manager.desiredAccuracy, GPSManager.sharedInstance.manager.distanceFilter)
            filterMultiplier.selectedSegmentIndex = factor
        } else {
            AppDelegate.shared?.notification(withTitle: "Unhandled multiplier", action: "ok", andBody: "Calculated: \(factor)")
        }
        
        filter.text = "\(GPSManager.sharedInstance.manager.distanceFilter)"
        
        switch GPSManager.sharedInstance.manager.desiredAccuracy {
        case kCLLocationAccuracyBestForNavigation:
            accuracy.selectedSegmentIndex = 5
            break
        case kCLLocationAccuracyBest:
            accuracy.selectedSegmentIndex = 4
            break
        case kCLLocationAccuracyNearestTenMeters:
            accuracy.selectedSegmentIndex = 3
            break
        case kCLLocationAccuracyHundredMeters:
            accuracy.selectedSegmentIndex = 2
            break
        case kCLLocationAccuracyKilometer:
            accuracy.selectedSegmentIndex = 1
            break
        case kCLLocationAccuracyThreeKilometers:
            accuracy.selectedSegmentIndex = 0
            break
        default:
            AppDelegate.shared?.notification(withTitle: "Unhandle accuracy", action: "ok", andBody: "Active: \(GPSManager.sharedInstance.manager.desiredAccuracy)")
            
            break
        }
        
        print("option.mode", modeControl.selectedSegmentIndex)
        print("option.flavor", flavorControl.selectedSegmentIndex)
        print("option.accuracy", accuracy.selectedSegmentIndex)
        print("option.factor", filterMultiplier.selectedSegmentIndex)
        print("updated")
    }
}

