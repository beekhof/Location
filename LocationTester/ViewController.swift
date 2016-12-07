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
    
    var lastSummary = Date()

    var batteryLevel: Float = 1.0
    let batteryMinimum: Float = 0.30
    var batteryState: UIDeviceBatteryState = UIDeviceBatteryState.unknown

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryStateChange), name: NSNotification.Name.UIDeviceBatteryStateDidChange, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryLevelChange), name: NSNotification.Name.UIDeviceBatteryLevelDidChange, object: nil)
        
//        NotificationCenter.default.addObserver(
//            self, selector: #selector(powerStateChanged), name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        let types = UIUserNotificationType.alert //| UIUserNotificationType.badge | UIUserNotificationType.sound
        let mySettings = UIUserNotificationSettings.init(types: types, categories: nil)
        UIApplication.shared.registerUserNotificationSettings(mySettings)
        
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        self.updateView()
        
        // Doesn't work in the background
        // let notifyTimer = Timer.init(timeInterval: 60*60, target: self, selector: #selector(self.notify), userInfo: nil, repeats: true)
        // RunLoop.main.add(notifyTimer, forMode: RunLoopMode.commonModes)
    }
    
    func notify() {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        AppDelegate.shared?.notification(withTitle: "Summary", action: "ok",
                                         andBody: "\(UIDevice.current.batteryLevel * 100)% - \(GPSManager.shared.stats()) calls since \(formatter.string(from:lastSummary)) for \(getpid())")
        self.resetStats()
    }
    
    func updateScreen() {
        if UIApplication.shared.applicationState != UIApplicationState.active {
            AppDelegate.shared?.notification(withTitle: "Background update", action: "ok", andBody: "Bad state: \(UIApplication.shared.applicationState.rawValue)")
            return
        }
        DispatchQueue.main.async {
            self.updateView()
            self.kickTimer(force: false)
        }
    }
    
    func resetStats() {
        lastSummary = Date()
        GPSManager.shared.resetStats()
        
        if UIApplication.shared.applicationState == UIApplicationState.active {
            DispatchQueue.main.async {
                self.updateView()
            }
        }
    }

    func updateView() {
        modeControl.selectedSegmentIndex = GPSManager.Options.mode.get()
        flavorControl.selectedSegmentIndex = GPSManager.shared.detail.flavour.rawValue
        filterMultiplier.selectedSegmentIndex = GPSManager.Options.factor.get()
        accuracy.selectedSegmentIndex = GPSManager.Options.accuracy.get()

        filter.text = "\(GPSManager.shared.detail.manager.distanceFilter)"
        info.text = " \(GPSManager.shared.stats()) calls in the last \(-lastSummary.timeIntervalSinceNow) seconds"
        errorInfo.text = "PID \(getpid())"
    }
    
    var timer: Timer? = nil
    
    func kickTimer(force: Bool) {
        DispatchQueue.global().async(execute: {
            //DispatchQueue.main.async {
            if force || UIApplication.shared.applicationState == UIApplicationState.active {
                self.timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(self.updateScreen), userInfo: nil, repeats: false)
                RunLoop.current.add(self.timer!, forMode: RunLoopMode.defaultRunLoopMode)
                RunLoop.current.run()
            }
        })
    }

    // MARK: User actions
    @IBAction func ChangeMode(_ sender: UISegmentedControl) {
        GPSManager.Options.mode.activate(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func ChangeFlavor(_ sender: UISegmentedControl) {
        GPSManager.Options.flavour.activate(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func updateFactor(_ sender: UISegmentedControl) {
        GPSManager.Options.factor.activate(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func ChangeAccuracy(_ sender: UISegmentedControl) {
        GPSManager.Options.accuracy.activate(value: sender.selectedSegmentIndex)
        GPSManager.Options.factor.activate(value: filterMultiplier.selectedSegmentIndex)
        self.resetStats()
    }
    
    // MARK: Callbacks
    override func viewDidAppear(_ animated: Bool) {
        self.updateView()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    func batteryStateChange() {
        let next = UIDevice.current.batteryState
        switch(next) {
        case UIDeviceBatteryState.unknown:
            break
            
        case UIDeviceBatteryState.unplugged:
            if UIDevice.current.batteryLevel < batteryMinimum {
                GPSManager.shared.setMode(value: .LowPower, reason: "Low battery: unplugged at \(UIDevice.current.batteryLevel * 100)")
            }
            break
            
        case UIDeviceBatteryState.charging:
            GPSManager.shared.kickManager(reason: "Charging from \(UIDevice.current.batteryLevel * 100)")
            break
            
        case UIDeviceBatteryState.full:
            break
        }
        batteryState = next;
    }
    
    func batteryLevelChange() {
        let next = UIDevice.current.batteryLevel
        
        if next < 0.0 {
            return
            
        } else if batteryLevel > next && next < batteryMinimum {
            GPSManager.shared.setMode(value: .LowPower, reason: "Low battery at \(next * 100)")
        }
        if batteryLevel > next {
            self.notify()
        }
        batteryLevel = next
    }
    
    func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            GPSManager.shared.setMode(value: .LowPower, reason: "Low power mode enabled")
            
        } else if UIDevice.current.batteryLevel > 20.0 {
            GPSManager.shared.kickManager(reason: "Low power mode disabled")
        }
    }
}

