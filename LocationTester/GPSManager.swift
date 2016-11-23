//
//  GPSManager.swift
//  Points
//
//  Created by Andrew Beekhof on 3/10/16.
//  Copyright © 2016 ___ANDREWBEEKHOF___. All rights reserved.
//

import UIKit
import MapKit

class GPSManager: NSObject, CLLocationManagerDelegate {
    
    // Hack for Obj-C
    let activeMode = Mode.Active.rawValue
    
    static let shared: GPSManager = GPSManager()
//    let pointsContext = PTSModelDelegate.trueInstance().modelContext()
    
    let manager = CLLocationManager()
    let significant = CLLocationManager()
    
    var mode: Mode = .Off
    var flavour: Flavour = .None
    
    var sigCount:Int = 0
    var callCount: Int = 0
    var lastSignificant: CLLocation?
    
    // MARK: Developement tunables
    let visits = true
    let contextFlushLimit: Int = 300
    let activeThresholdMeters: Double = 10.0
    let horizontalAccuracyThreshold: Double = 500.0
    let deferrable = CLLocationManager.deferredLocationUpdatesAvailable()
    
    // MARK: State Enums
    enum Mode: Int {
        case NotAuthorized = -1
        case Off
        case VisitsOnly
        case Active
        case LowPower
    }
    
    enum Flavour: Int {
        case None = 0
        case Paused
        case GPS
        case Timer
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        
        significant.delegate = self
        significant.startMonitoringSignificantLocationChanges()        
    }
    
    func restore() {
        _ = Options.mode.restore()
        _ = Options.flavour.restore()
        _ = Options.accuracy.restore()
        _ = Options.filter.restore()
    }
    
    func standalone() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
    }
    
    // MARK: Control state changes
    
    func setFlavour(sender: UISegmentedControl, reason: String) {
        Options.flavour.set(value: sender.selectedSegmentIndex)
        setFlavour(value: Flavour(rawValue: sender.selectedSegmentIndex)!, reason: reason)
    }
    
    func setFlavour(value: Flavour, reason: String) {
        if (mode != .Active && mode != .LowPower) || value == flavour {
            return
        }
        
        AppDelegate.shared?.notification(withTitle: "Flavor change", action: "ok", andBody: "Switching from \(flavour) updates to \(value) - \(reason)")
        flavour = value
        
        switch flavour {
        case .None:
            manager.stopUpdatingLocation()
            manager.stopMonitoringVisits()
            manager.disallowDeferredLocationUpdates()
            manager.stopMonitoringSignificantLocationChanges()
            UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
            break
        case .Paused:
            break
        case .GPS:
            // Best == GPS
            // BestForNavigation == GPS + Other sensor data
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            
            Options.accuracy.activate(value: Options.accuracy.getActive())
            Options.filter.activate(value: 10)
            
            if deferrable {
                manager.disallowDeferredLocationUpdates()
            }
            
            if visits {
                manager.startMonitoringVisits()
            }
            manager.startUpdatingLocation()
            break
        case .Timer:
            manager.stopUpdatingLocation()
            manager.pausesLocationUpdatesAutomatically = false
            UIApplication.shared.setMinimumBackgroundFetchInterval(600)
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            self.obtainCurrentPosition()
            break
        }
    }
    
    func setMode(sender: UISegmentedControl, reason: String) {
        Options.mode.set(value: sender.selectedSegmentIndex)
        self.setMode(value: GPSManager.Mode(rawValue: sender.selectedSegmentIndex)!, reason: reason)
    }
    
    func setMode(value: Mode, reason: String) {
        if !self.authorized(value: value) {
            return
        }
        
        if mode == value {
            return
        }
        
        if value == .LowPower || value == .Active {
            let configured = Options.mode.get()
            if configured != Mode.Active.rawValue && configured != Mode.LowPower.rawValue {
                AppDelegate.shared?.notification(withTitle: "Not switching from \(mode) updates to \(value)", action: "ok", andBody: "Need \(configured)")
                return
            }
        }
        
        AppDelegate.shared?.notification(withTitle: "Switching from \(mode) updates to \(value)", action: "ok", andBody: reason)
        mode = value
        
        switch mode {
        case .NotAuthorized:
            significant.stopMonitoringSignificantLocationChanges()
            self.setFlavour(value: .None, reason: reason)
            manager.stopMonitoringVisits()
            break
        case .Off:
            significant.stopMonitoringSignificantLocationChanges()
            self.setFlavour(value: .None, reason: reason)
            manager.stopMonitoringVisits()
            break
        case .VisitsOnly:
            self.setFlavour(value: .None, reason: reason)
            manager.startMonitoringVisits()
            break
        case .Active:
            self.setFlavour(value: .GPS, reason: reason)
            manager.pausesLocationUpdatesAutomatically = false
            break
        case .LowPower:
            //            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            //            Options.accuracy.activate(value: Options.accuracy.getActive())
            //            Options.factor.activate(value: 3)
            self.setFlavour(value: .GPS, reason: reason)
            manager.pausesLocationUpdatesAutomatically = true
            
            break
        }
        
        return
    }
    
    // MARK: Location API
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        if manager == self.significant {
            sigCount += 1
            for location in locations {
                let distance = lastSignificant?.distance(from: location)
                if location.horizontalAccuracy > 1000.0 {
                    AppDelegate.shared?.notification(withTitle: "Insignificant change (accuracy)", action: "ok", andBody: "\(getpid()).\(sigCount).\(locations.count) \(location)")
                    continue
                    
                } else if lastSignificant == nil {
                    self.setFlavour(value: GPSManager.Flavour.GPS, reason: "First significant")
                    
                } else if distance != nil && distance!.isLess(than: 20.0) == false {
                    AppDelegate.shared?.notification(withTitle: "Significant change", action: "ok", andBody: "\(getpid()).\(sigCount).\(locations.count) \(distance)m :  \(location)")
                    self.setFlavour(value: GPSManager.Flavour.GPS, reason: "Significant change \(distance)")
                    
                } else {
                    AppDelegate.shared?.notification(withTitle: "Insignificant change (distance)", action: "ok", andBody: "\(getpid()).\(sigCount).\(locations.count) \(distance)m :  \(location)")
                }
                lastSignificant = location
            }
            return
        }
        
        callCount += 1

        if flavour == .Paused {
            AppDelegate.shared?.notification(withTitle: "Called", action: "ok", andBody: "Got \(locations.count) updates")
            
        } else if flavour == .None {
            return
        }

        for location in locations {
            print(location)
        }

    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        let lastLocationError = error as? CLError
        
        if needLocation {
            AppDelegate.shared?.notification(withTitle: "Location API error", action: "ok", andBody: "\(lastLocationError!.code.rawValue) \(lastLocationError!.localizedDescription) \(manager.location)")
        }
        
        switch(lastLocationError!.code) {
        case .locationUnknown: // location is currently unknown, but CL will keep trying
            return
        case .denied: // Access to location or ranging has been denied by the user
            return
            
        case .network: // general, network-related error
            return
            
        case .headingFailure: // heading could not be determined
            return
            
        case .regionMonitoringDenied: // Location region monitoring has been denied by the user
            break
            
        case .regionMonitoringFailure: // A registered region cannot be monitored
            break
            
        case .regionMonitoringSetupDelayed: // CL could not immediately initialize region monitoring
            break
            
        case .regionMonitoringResponseDelayed: // While events for this fence will be delivered, delivery will not occur immediately
            break
            
        case .geocodeFoundNoResult: // A geocode request yielded no result
            break
            
        case .geocodeFoundPartialResult: // A geocode request yielded a partial result
            return
            
        case .geocodeCanceled: // A geocode request was cancelled
            return
            
        case .deferredFailed: // Deferred mode failed
            self.setFlavour(value: .GPS, reason: "Deferred updates failed")
            return
            
        case .deferredNotUpdatingLocation: // Deferred mode failed because location updates disabled or paused
            return
            
        case .deferredAccuracyTooLow: // Deferred mode not supported for the requested accuracy
            break
            
        case .deferredDistanceFiltered: // Deferred mode does not support distance filters
            return
            
        case .deferredCanceled: // Deferred mode request canceled a previous request
            //            PTSPoint *point = [_model pointForLocation:manager.location inContext:self.pointsContext];
            //            point.flags |= point_flag_deferred;
            return
            
        case .rangingUnavailable: // Ranging cannot be performed
            break
            
        case .rangingFailure: // General ranging failure
            break
        }
        
        AppDelegate.shared?.notification(withTitle: "Location API error", action: "ok", andBody: "\(lastLocationError!.code.rawValue) \(lastLocationError!.localizedDescription)")
        self.setFlavour(value: .GPS, reason: "Deferred updates failed \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        
        switch status {
        case .notDetermined:
            return
        case .denied:
            self.setMode(value: .NotAuthorized, reason: "didChangeAuthorization")
            break
        case .restricted:
            self.setMode(value: .NotAuthorized, reason: "didChangeAuthorization")
            break
            
        default:
            self.mode = .NotAuthorized
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                GPSManager.shared.setMode(value: .LowPower, reason: "(Low power) didChangeAuthorization")
                
            } else {
                let pref = Options.mode.get()
                let prefMode = Mode.init(rawValue: pref)!
                self.setMode(value: prefMode, reason: "didChangeAuthorization")
            }
        }
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        self.setFlavour(value: .Paused, reason: "GPS paused \(UIApplication.shared.backgroundTimeRemaining)")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        self.setFlavour(value: .GPS, reason: "GPS resumed \(UIApplication.shared.backgroundTimeRemaining)")
    }
    
    // MARK: Notifications
    func applicationDidBecomeActive() {
    }
    
    func applicationDidEnterBackground() {
    }
    
    // MARK: Helpers
    func authorized(value: Mode) -> Bool {
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            if value != .Off {
                
                if(value == .Active && UIApplication.shared.applicationState == UIApplicationState.active) {
                    manager.requestAlwaysAuthorization()
                }
                
                AppDelegate.shared?.notification(withTitle: "Cannot change mode to \(value)", action: "ok", andBody: "Tracking not setup")
                return false
            }
            break
            
            // This application is not authorized to use location services.  Due
            // to active restrictions on location services, the user cannot change
        // this status, and may not have personally denied authorization
        case .restricted:
            if value != .Off {
                AppDelegate.shared?.notification(withTitle: "Cannot change mode to \(value)", action: "ok", andBody: "Tracking denied (device)")
                return false
            }
            break
            
            // User has explicitly denied authorization for this application, or
        // location services are disabled in Settings.
        case .denied:
            if value != .Off {
                AppDelegate.shared?.notification(withTitle: "Cannot change mode to \(value)", action: "ok", andBody: "Tracking denied (device)")
                return false
            }
            break
            
            
            // User has granted authorization to use their location at any time,
            // including monitoring for regions, visits, or significant location changes.
            //
            // This value should be used on iOS, tvOS and watchOS.  It is available on
        // MacOS, but kCLAuthorizationStatusAuthorized is synonymous and preferred.
        case .authorizedAlways:
            break
            
            
            // User has granted authorization to use their location only when your app
            // is visible to them (it will be made visible to them if you continue to
            // receive location updates while in the background).  Authorization to use
            // launch APIs has not been granted.
            //
            // This value is not available on MacOS.  It should be used on iOS, tvOS and
        // watchOS.
        case .authorizedWhenInUse:
            break
        }
        return true
    }
    
    func updateExistingVisit(visit: CLVisit) -> Bool {
        return true;
    }
    
    // MARK: Timer based solution
    let bgAccuracyMinimum = 50.0
    var backgroundUpdateTask: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    func beginBackgroundUpdateTask() {
        self.backgroundUpdateTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.endBackgroundUpdateTask()
        })
    }
    
    func endBackgroundUpdateTask() {
        if self.backgroundUpdateTask != UIBackgroundTaskInvalid {
            UIApplication.shared.endBackgroundTask(self.backgroundUpdateTask)
            self.backgroundUpdateTask = UIBackgroundTaskInvalid
        }
    }
    
    var needLocation = false
    func obtainCurrentPosition() {
        if flavour == .Timer {
            needLocation = true
            
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
            //            manager.requestLocation()
            
            AppDelegate.shared?.notification(withTitle: #function, action: "ok", andBody: "Requesting location \(getpid()) \(UIDevice.current.batteryLevel*100)  \(UIApplication.shared.backgroundTimeRemaining)")
            
        }
    }
    
    func checkCurrentPosition(location: CLLocation) -> Bool {
        
        if needLocation == false {
            return true
            
        } else if UIApplication.shared.backgroundTimeRemaining < 10.0 {
            AppDelegate.shared?.notification(withTitle: #function, action: "ok", andBody: "Accepting bad location \(location.horizontalAccuracy)  \(UIApplication.shared.backgroundTimeRemaining)")
            
        } else if location.horizontalAccuracy > bgAccuracyMinimum {
            return true
        }
        
        manager.stopUpdatingLocation()
        needLocation = false
        
//        _ = PTSModelDelegate.trueInstance().point(for: location, in: pointsContext)
        
        AppDelegate.shared?.notification(withTitle: #function, action: "ok", andBody: "Got timed location \(getpid()) \(UIDevice.current.batteryLevel*100)  \(UIApplication.shared.backgroundTimeRemaining)")
        
        self.endBackgroundUpdateTask()
        _ = self.kickTimer()
        return true
    }
    
    func kickTimer() -> UIBackgroundFetchResult {
        
        DispatchQueue.global().async(execute: {
            self.beginBackgroundUpdateTask()
            var delay = UIApplication.shared.backgroundTimeRemaining - 20.0
            if delay > 180.0 {
                delay = 180.0
            } else if delay < 0.0 {
                self.obtainCurrentPosition()
                return
            } else {
                AppDelegate.shared?.notification(withTitle: #function, action: "ok", andBody: "Setting timer \(getpid()) \(UIDevice.current.batteryLevel*100)  \(delay)")
            }
            
            let timer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.obtainCurrentPosition), userInfo: nil, repeats: false)
            RunLoop.current.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
            RunLoop.current.run()
        })
        
        return UIBackgroundFetchResult.newData
    }
    
    // MARK: Options
    enum Options: String {
        case mode = "points.option.tracking_type"
        case flavour = "option.flavour"
        case accuracy = "option.accuracy"
        case filter = "option.filter"
        case factor = "option.factor"
        
        func get() -> Int {
            return UserDefaults.standard.integer(forKey: self.rawValue)
        }
        
        func set(value: Int) {
            UserDefaults.standard.set(value, forKey: self.rawValue)
        }
        
        func activate(value: Int) {
            UserDefaults.standard.set(value, forKey: self.rawValue)
            self.setActive(value: value)
        }
        
        func restore() -> Int {
            let stored = UserDefaults.standard.integer(forKey: self.rawValue)
            self.setActive(value: stored)
            return stored
        }
        
        func getActive() -> Int {
            switch self {
            case .mode:
                return GPSManager.shared.mode.rawValue
            case .flavour:
                return GPSManager.shared.flavour.rawValue
            case .accuracy:
                return self.indexFor(accuracy: GPSManager.shared.manager.desiredAccuracy)
            case .filter:
                return Int(GPSManager.shared.manager.distanceFilter)
            case .factor:
                if Options.accuracy.get() > 3 {
                    return Int(GPSManager.shared.manager.distanceFilter)
                } else if GPSManager.shared.manager.desiredAccuracy > 0 {
                    return Int(GPSManager.shared.manager.distanceFilter / GPSManager.shared.manager.desiredAccuracy)
                }
                return 0
            }
        }
        
        func setActive(value: Int) {
            switch self {
            case .mode:
                let configured = Mode(rawValue: value)
                if configured != nil {
                    GPSManager.shared.setMode(value: configured!, reason: #function)
                } else {
                    GPSManager.shared.setMode(value: .Off, reason: "Invalid preference: \(value)")
                }
                break
            case .flavour:
                let configured = Flavour(rawValue: value)
                if configured != nil {
                    GPSManager.shared.setFlavour(value: configured!, reason: #function)
                } else {
                    GPSManager.shared.setFlavour(value: .None, reason: "Invalid preference: \(value)")
                }
                break
            case .accuracy:
                GPSManager.shared.manager.desiredAccuracy = self.accuracyFor(index: value)
                break
            case .filter:
                GPSManager.shared.manager.distanceFilter = Double(value)
                break
            case .factor:
                if value <= 0 {
                    Options.filter.activate(value: Int(kCLDistanceFilterNone))
                    
                } else if Options.accuracy.get() > 3 {
                    Options.filter.activate(value: value)
                    
                } else {
                    Options.filter.activate(value: Int(GPSManager.shared.manager.desiredAccuracy) *  value)
                }
                break
            }
        }
        
        func indexFor(accuracy: CLLocationAccuracy) -> Int {
            switch accuracy {
            case kCLLocationAccuracyBestForNavigation:
                return 5
            case kCLLocationAccuracyBest:
                return 4
            case kCLLocationAccuracyNearestTenMeters:
                return 3
            case kCLLocationAccuracyHundredMeters:
                return 2
            case kCLLocationAccuracyKilometer:
                return 1
            case kCLLocationAccuracyThreeKilometers:
                return 0
            default:
                AppDelegate.shared?.notification(withTitle: "Unhandled accuracy", action: "ok", andBody: "Active: \(GPSManager.shared.manager.desiredAccuracy)")
                return 0
            }
        }
        
        func accuracyFor(index: Int) -> CLLocationAccuracy {
            switch index {
            case 5:
                return kCLLocationAccuracyBestForNavigation
            case 4:
                return kCLLocationAccuracyBest
            case 3:
                return kCLLocationAccuracyNearestTenMeters
            case 2:
                return kCLLocationAccuracyHundredMeters
            case 1:
                return kCLLocationAccuracyKilometer
            case 0:
                return kCLLocationAccuracyThreeKilometers
            default:
                AppDelegate.shared?.notification(withTitle: "Invalid accuracy", action: "ok", andBody: "Selected: \(index)")
                return kCLLocationAccuracyThreeKilometers
            }
        }
        
    }
}
