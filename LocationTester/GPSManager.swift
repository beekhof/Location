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
    
    enum Flavour: Int {
        case None = 0
        case Paused
        case LowPower
        case Deferred
        case Foreground
        case Timer
    }
    
    let activeMode = Mode.Active.rawValue
    
    enum Mode: Int {
        case NotAuthorized = -1
        case Off
        case VisitsOnly
        case Active
        case Significant
    }
    
    static let sharedInstance: GPSManager = GPSManager()
    
    let visits = false
    var mode: Mode = .Off
    var flavour: Flavour = .None
    let deferrable = CLLocationManager.deferredLocationUpdatesAvailable()
    
    //    {
    //        set {
    //            super.backgroundColor = newValue
    //        }
    //        get {
    //            return super.backgroundColor!
    //        }
    //    }
    
    let batteryMinimum: Float = 0.30
    let contextFlushLimit: Int = 300
    let activeThresholdMeters: Double = 10.0
    let horizontalAccuracyThreshold: Double = 500.0
    
    let manager = CLLocationManager()
    
    var batteryLevel: Float = 1.0
    var batteryState: UIDeviceBatteryState = UIDeviceBatteryState.unknown
    
    var lastLocationError: CLError?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryStateChange), name: NSNotification.Name.UIDeviceBatteryStateDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryLevelChange), name: NSNotification.Name.UIDeviceBatteryLevelDidChange, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged), name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        //        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Control state changes
    
    func setFlavour(value: Flavour, reason: String) {
        if mode != .Active {
            return
        }
        
        var newFlavour = value
        
        if newFlavour == .Deferred && lastLocationError?.code == CLError.deferredFailed {
            AppDelegate.shared?.notification(withTitle: "Cannot defer updates", action: "ok", andBody: "Previous attempt failed")
            newFlavour = .Foreground
        }
        
        if newFlavour == flavour {
            return
        }
        
        AppDelegate.shared?.notification(withTitle: "\(self) Switching from \(flavour) updates to \(newFlavour)", action: "ok", andBody: reason)
        flavour = newFlavour
        
        switch flavour {
        case .None:
            manager.stopUpdatingLocation()
            UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
            break
        case .Paused:
            manager.startMonitoringSignificantLocationChanges()
            break
        case .LowPower:
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = 50000.0
            //manager.startMonitoringSignificantLocationChanges()
            break
        case .Deferred:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
            manager.allowDeferredLocationUpdates(untilTraveled: CLLocationDistanceMax, timeout: CLTimeIntervalMax)
            break
        case .Foreground:
            manager.pausesLocationUpdatesAutomatically = false
            // Best == GPS
            // BestForNavigation == GPS + Other sensor data
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 10.0
            //                manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            //                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            
            if deferrable {
                manager.disallowDeferredLocationUpdates()
            }
            
            UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
            manager.stopMonitoringSignificantLocationChanges()
            if visits {
                manager.startMonitoringVisits()
            } else {
                manager.stopMonitoringVisits()
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
    
    func setMode(value: Mode, reason: String) {
        if !self.authorized(value: value) {
            return
        }
        
        var newMode = value
        
        if newMode == mode {
            return
        }
        
        if newMode == .Active
            && UIApplication.shared.applicationState == UIApplicationState.background {
            AppDelegate.shared?.notification(withTitle: "Cannot change mode from \(mode) to \(value)", action: "ok", andBody: "Running in backgrounded")
            newMode = .Significant
        }
        
        AppDelegate.shared?.notification(withTitle: "Switching from \(mode) updates to \(value)", action: "ok", andBody: reason)
        mode = newMode
        
        switch mode {
        case .NotAuthorized:
            self.setFlavour(value: .None, reason: reason)
            flavour = .None
            break
        case .Off:
            self.setFlavour(value: .None, reason: reason)
            manager.stopMonitoringVisits()
            flavour = .None
            break
        case .VisitsOnly:
            self.setFlavour(value: .None, reason: reason)
            manager.startMonitoringVisits()
            flavour = .None
            break
        case .Significant:
            self.setFlavour(value: .None, reason: reason)
            manager.startMonitoringSignificantLocationChanges()
            if visits {
                manager.startMonitoringVisits()
            }
            break
        case .Active:
            self.setFlavour(value: .Foreground, reason: reason)
            self.batteryStateChange()
            self.powerStateChanged()
            break
        }
        
        return
    }
    
    // MARK: Location API
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        AppDelegate.shared?.notification(withTitle: "New visit", action: "ok", andBody: " \(visit)")
    }
    
    
    var logError = true
    var lastSummary = Date()
    var callCount: Int = 0
    var uniqueCount: Int  = 0
    let bgAccuracyMinimum = 50.0
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        callCount += 1
        
        //        AppDelegate.shared?.notification(withTitle: "Called", action: "ok", andBody: "Got \(locations.count) \(flavour) update")
        
        //        [self syntheticVisit:false];
        if locations.count == 1
            && deferrable
            && flavour == .Foreground
            && lastLocationError?.code != CLError.deferredFailed {
            self.setFlavour(value: .Deferred, reason: "Single Location")
            
            //        } else if locations.count > 1 {
            //            AppDelegate.shared?.notification(withTitle: "Batch update", action: "ok", andBody: "Got \(locations.count) updates: \(UIDevice.current.batteryLevel * 100)%")
            
        } else if flavour == .Paused {
            AppDelegate.shared?.notification(withTitle: "Called", action: "ok", andBody: "Got \(locations.count) updates")
            self.setFlavour(value: .Foreground, reason: #function)
            
        } else if flavour == .None {
            return
        }

        for location in locations {
            uniqueCount += 1
            print(location)
        }
        
        if -lastSummary.timeIntervalSinceNow > 60.0*60.0 {
            AppDelegate.shared?.notification(withTitle: "Summary", action: "ok",
                              andBody: "Got \(callCount) \(mode):\(flavour) updates with \(uniqueCount) points in \( -lastSummary.timeIntervalSinceNow) \(UIDevice.current.batteryLevel * 100)%")
            logError = true
            callCount = 0
            uniqueCount  = 0
            lastSummary = Date()
            //            self.setFlavour(value: .Timer, reason: "Test")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        lastLocationError = error as? CLError
        
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
            self.setFlavour(value: .Foreground, reason: "Deferred updates failed")
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
        self.setFlavour(value: .Foreground, reason: "Deferred updates failed \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.kickManager(reason: #function)
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        AppDelegate.shared?.notification(withTitle: "Location API paused", action: "ok", andBody: "\(UIApplication.shared.backgroundTimeRemaining)")
        self.setFlavour(value: .Paused, reason: #function)
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        AppDelegate.shared?.notification(withTitle: "Location API resumed", action: "ok", andBody: "\(UIApplication.shared.backgroundTimeRemaining)")
        self.setFlavour(value: .Foreground, reason: #function)
        //        flavour = .Foreground
        //        manager.distanceFilter = kCLDistanceFilterNone
    }
    
    // MARK: Notifications
    func applicationDidBecomeActive() {
//        self.kickManager(reason: #function)
//        self.setFlavour(value: .Foreground, reason: #function)
    }
    
    func applicationDidEnterBackground() {
        //        self.setFlavour(value: .Timer, reason: #function)
        //        self.haveCurrentPosition()
        //        AppDelegate.shared?.notification(withTitle: "Moved to background", action: "ok", andBody: "Timer")
        //        checkRemaining()
    }
    
    func preferencesUpdated() {
        self.kickManager(reason: #function)
    }
    
    func batteryStateChange() {
        let next = UIDevice.current.batteryState
        
        switch(next) {
        case UIDeviceBatteryState.unknown:
            if UIDevice.current.batteryLevel > 0.0 && UIDevice.current.batteryLevel < batteryMinimum {
                self.setFlavour(value: .LowPower, reason: "Low battery (unknown) at \(UIDevice.current.batteryLevel * 100)")
            }
            break
            
        case UIDeviceBatteryState.unplugged:
            if UIDevice.current.batteryLevel < batteryMinimum {
                self.setFlavour(value: .LowPower, reason: "Low battery: unplugged at \(UIDevice.current.batteryLevel * 100)")
            }
            break
            
        case UIDeviceBatteryState.charging:
            if batteryState == UIDeviceBatteryState.unplugged {
                self.setFlavour(value: .Foreground, reason: "Charging from \(UIDevice.current.batteryLevel * 100)")
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
            self.setFlavour(value: .LowPower, reason: "Low battery change \(next * 100)")
        }
        batteryLevel = next
    }
    
    func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Low Power Mode is enabled. Start reducing activity to conserve energy.
            self.setFlavour(value: .LowPower, reason: "Low power mode enabled")
            
        } else if UIDevice.current.batteryLevel > 0.0 {
            // Low Power Mode is not enabled.
            if UIDevice.current.batteryLevel < batteryMinimum {
                self.setFlavour(value: .LowPower, reason: "Power mode \(UIDevice.current.batteryLevel * 100)")
                
            } else {
                self.setFlavour(value: .Foreground, reason: "Low power mode disabled")
            }
        }
    }
    
    // MARK: Helpers
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

    func kickManager(reason: String) {
        let pref = UserDefaults.standard.integer(forKey: "option.mode")
        
        let prefMode = Mode.init(rawValue: pref)!
        self.setMode(value: prefMode, reason: reason)
    }
    
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
        
    var lastLocation: CLLocation?
    
    func filterLocation(location: CLLocation, withThreshold threshold: Double, save:Bool) -> Bool
    {
        if lastLocation == nil {
            if save {
                lastLocation = location
            }
            return false
        }
        
        if(save && location.timestamp < lastLocation!.timestamp) {
            //        BNotice(@"Detected location prior to %@ <%f,%f>: %@",
            //            [BKFLogging stringForTimestamp:timestamp], _latitude, _longitude, location);
            
        } else if(location.horizontalAccuracy > horizontalAccuracyThreshold) {
            //        BLog(@"%d Accuracy: %@", _updateStrategy, location);
            return true
        }
        
        let nextMap = MKMapPointForCoordinate(location.coordinate)
        let lastMap = MKMapPointForCoordinate(lastLocation!.coordinate)
        let meters = MKMetersBetweenMapPoints(lastMap, nextMap)
        
        if(meters < threshold) {
            return true
        }
        
        if(save) {
            lastLocation = location
        }
        
        //    BLog(@"%d Pass[%d]: %@", _updateStrategy, offset, location);
        return false
    }
    
}
