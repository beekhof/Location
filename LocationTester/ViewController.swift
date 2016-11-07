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
            self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryStateChange), name: NSNotification.Name.UIDeviceBatteryStateDidChange, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryLevelChange), name: NSNotification.Name.UIDeviceBatteryLevelDidChange, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged), name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)


        print(UserDefaults.standard.dictionaryRepresentation())
        
        modeControl.selectedSegmentIndex =  GPSManager.Options.mode.restore()
        flavorControl.selectedSegmentIndex = GPSManager.Options.flavour.restore()
        accuracy.selectedSegmentIndex = GPSManager.Options.accuracy.restore()
        filterMultiplier.selectedSegmentIndex = GPSManager.Options.factor.restore()

        let types = UIUserNotificationType.alert //| UIUserNotificationType.badge | UIUserNotificationType.sound
        let mySettings = UIUserNotificationSettings.init(types: types, categories: nil)
        UIApplication.shared.registerUserNotificationSettings(mySettings)
        
        self.updateView()
        self.kickTimer(force: true)
        
        let notifyTimer = Timer.init(timeInterval: 60*60, target: self, selector: #selector(self.notify), userInfo: nil, repeats: true)
        RunLoop.main.add(notifyTimer, forMode: RunLoopMode.commonModes)
    }
    
    func notify() {
        AppDelegate.shared?.notification(withTitle: "Summary",
                                         action: "ok",
                                         andBody: "Got \(GPSManager.shared.callCount) \(GPSManager.shared.mode):\(GPSManager.shared.flavour) updates with \(GPSManager.shared.uniqueCount) points since \(lastSummary) \(getpid()):\(UIDevice.current.batteryLevel * 100)%")
        lastSummary = Date()
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
        GPSManager.shared.callCount = 0
        GPSManager.shared.uniqueCount = 0
        lastSummary = Date()
        
        if UIApplication.shared.applicationState == UIApplicationState.active {
            DispatchQueue.main.async {
                self.updateView()
            }
        }
    }

    func updateView() {
        modeControl.selectedSegmentIndex = GPSManager.Options.mode.get()
        flavorControl.selectedSegmentIndex = GPSManager.Options.flavour.get()
        filterMultiplier.selectedSegmentIndex = GPSManager.Options.factor.get()
        accuracy.selectedSegmentIndex = GPSManager.Options.accuracy.get()

        filter.text = "\(GPSManager.shared.manager.distanceFilter)"
        info.text = " \(GPSManager.shared.callCount) calls in the last \(-lastSummary.timeIntervalSinceNow) seconds"
        
        if ((GPSManager.shared.lastLocationError) != nil) {
            errorInfo.text = "Error \(GPSManager.shared.lastLocationError?.errorCode): \(GPSManager.shared.lastLocationError?.localizedDescription)"
            
        } else {
            errorInfo.text = "No error"
        }
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
        GPSManager.Options.mode.set(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func ChangeFlavor(_ sender: UISegmentedControl) {
        GPSManager.Options.flavour.set(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func updateFactor(_ sender: UISegmentedControl) {
        GPSManager.Options.factor.set(value: sender.selectedSegmentIndex)
        self.resetStats()
    }
    
    @IBAction func ChangeAccuracy(_ sender: UISegmentedControl) {
        GPSManager.Options.accuracy.set(value: sender.selectedSegmentIndex)
        GPSManager.Options.factor.set(value: filterMultiplier.selectedSegmentIndex)
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
            if UIDevice.current.batteryLevel > 0.0 && UIDevice.current.batteryLevel < batteryMinimum {
                GPSManager.shared.setFlavour(value: .LowPower, reason: "Low battery (unknown) at \(UIDevice.current.batteryLevel * 100)")
            }
            break
            
        case UIDeviceBatteryState.unplugged:
            if UIDevice.current.batteryLevel < batteryMinimum {
                GPSManager.shared.setFlavour(value: .LowPower, reason: "Low battery: unplugged at \(UIDevice.current.batteryLevel * 100)")
            }
            break
            
        case UIDeviceBatteryState.charging:
            if batteryState == UIDeviceBatteryState.unplugged {
                GPSManager.shared.setFlavour(value: .Foreground, reason: "Charging from \(UIDevice.current.batteryLevel * 100)")
            }
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
            GPSManager.shared.setFlavour(value: .LowPower, reason: "Low battery change \(next * 100)")
        } else if batteryLevel > next {
            self.notify()
        }
        batteryLevel = next
    }
    
    func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Low Power Mode is enabled. Start reducing activity to conserve energy.
            GPSManager.shared.setFlavour(value: .LowPower, reason: "Low power mode enabled")
            
        } else if UIDevice.current.batteryLevel > 0.0 {
            // Low Power Mode is not enabled.
            if UIDevice.current.batteryLevel < batteryMinimum {
                GPSManager.shared.setFlavour(value: .LowPower, reason: "Power mode \(UIDevice.current.batteryLevel * 100)")
                
            } else {
                GPSManager.shared.setFlavour(value: .Foreground, reason: "Low power mode disabled")
            }
        }
    }

}

