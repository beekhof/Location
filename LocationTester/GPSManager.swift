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
    
    enum Options: String {
        case mode = "option.mode"
        case flavour = "option.flavour"
        case factor = "option.factor"
        case accuracy = "option.accuracy"

        func get() -> Int {
            return UserDefaults.standard.integer(forKey: self.rawValue)
        }
        
        func set(value: Int) {
            UserDefaults.standard.set(value, forKey: self.rawValue)
            setActive(value: value)
        }

        func restore() -> Int {
            let value = UserDefaults.standard.integer(forKey: self.rawValue)
            setActive(value: value)
            return value
        }
        
        func getActive() -> Int {
            switch self {
            case .mode:
                return GPSManager.shared.mode.rawValue
            case .flavour:
                return GPSManager.shared.flavour.rawValue
            case .accuracy:
                switch GPSManager.shared.manager.desiredAccuracy {
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
                    AppDelegate.shared?.notification(withTitle: "Unhandle accuracy", action: "ok", andBody: "Active: \(GPSManager.shared.manager.desiredAccuracy)")
                    
                    return 0
                }
            case .factor:
                var value: Int = 0
                
                if GPSManager.shared.manager.desiredAccuracy > 0 {
                    value = Int(GPSManager.shared.manager.distanceFilter / GPSManager.shared.manager.desiredAccuracy)
                }
                
                return value
            }
        }

        func setActive(value: Int) {
            switch self {
            case .mode:
                GPSManager.shared.setMode(value: GPSManager.Mode(rawValue: value)!, reason: #function)
                break
            case .flavour:
                GPSManager.shared.setFlavour(value: GPSManager.Flavour(rawValue: value)!, reason: #function)
                break
            case .accuracy:
                switch value {
                case 5:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                    break
                case 4:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyBest
                    break
                case 3:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                    break
                case 2:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    break
                case 1:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyKilometer
                    break
                case 0:
                    GPSManager.shared.manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
                    break
                default:
                    AppDelegate.shared?.notification(withTitle: "Invalid accuracy", action: "ok", andBody: "Selected: \(value)")
                    break
                }                
                break
            case .factor:
                if value <= 0 {
                    GPSManager.shared.manager.distanceFilter = kCLDistanceFilterNone
                } else {
                    GPSManager.shared.manager.distanceFilter = GPSManager.shared.manager.desiredAccuracy * Double(value)
                }
                break
            }
        }
    }
    
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
    
    static let shared: GPSManager = GPSManager()
    
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
    
    let contextFlushLimit: Int = 300
    let activeThresholdMeters: Double = 10.0
    let horizontalAccuracyThreshold: Double = 500.0
    
    let manager = CLLocationManager()
        
    var lastLocationError: CLError?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
    }
    
    // MARK: Control state changes
 
    func setFlavour(sender: UISegmentedControl, reason: String) {
        self.setFlavour(value: GPSManager.Flavour(rawValue: sender.selectedSegmentIndex)!, reason: reason)
    }

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
            manager.stopMonitoringVisits()
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
            manager.distanceFilter = 20.0
            
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
    
    func setMode(sender: UISegmentedControl, reason: String) {
        self.setMode(value: GPSManager.Mode(rawValue: sender.selectedSegmentIndex)!, reason: reason)
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
        UIApplication.shared.applicationIconBadgeNumber = callCount
       
        if locations.count == 1
            && deferrable
            && flavour == .Foreground
            && lastLocationError?.code != CLError.deferredFailed {
            self.setFlavour(value: .Deferred, reason: "Single Location")
            
        } else if flavour == .Paused {
            AppDelegate.shared?.notification(withTitle: "Called", action: "ok", andBody: "Got \(locations.count) \(flavour) updates")
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
    
    func kickManager(reason: String) {
        let pref = Options.mode.get()
        let prefMode = Mode.init(rawValue: pref)!
        self.setMode(value: prefMode, reason: reason)
        
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Low Power Mode is enabled. Start reducing activity to conserve energy.
            GPSManager.shared.setFlavour(value: .LowPower, reason: "Low power mode already enabled")
        }
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
            //        print(@"Detected location prior to %@ <%f,%f>: %@",
            //            [BKFLogging stringForTimestamp:timestamp], _latitude, _longitude, location);
            
        } else if(location.horizontalAccuracy > horizontalAccuracyThreshold) {
            //        print(@"%d Accuracy: %@", _updateStrategy, location);
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
        
        //    print(@"%d Pass[%d]: %@", _updateStrategy, offset, location);
        return false
    }
    
}
