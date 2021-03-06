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
    
    // Hacks for Obj-C
    let activeMode = Mode.Best.rawValue
    func setMode(sender: UISegmentedControl, reason: String) {
        Options.mode.set(value: sender.selectedSegmentIndex)
        self.setMode(value: GPSManager.Mode(rawValue: sender.selectedSegmentIndex)!, reason: reason)
    }
    
    // MARK: Development tunables
    static let filterSlotsMaximum = 3
    static let defaultDesiredAccuracy = kCLLocationAccuracyNearestTenMeters
    static let passiveCheckMinimumMeters = 3 * defaultDesiredAccuracy
    static let passiveCheckMinimumSeconds = 60.0
    static let passiveCheckMinimumHeading = 30.0
    static let passiveCheckMinimumAccuracy = 100.0

   // MARK: State Enums
    enum Mode: Int {
        case NotAuthorized = -1
        case Off
        case LowPower
        case Best
        case Smart
    }
    
    enum Flavour: Int {
        case None = 0
        case Paused
        case GPS
    }
    
    // MARK: Members
    static let shared: GPSManager = GPSManager()
    
    var mode: Mode = .Off
    var delegate: CLLocationManagerDelegate?
    
    let poll = LocationPoller()
    let detail = LocationDetail()
    let significant = LocationPassive()
    var lastDate = Date()

    override init() {
        super.init()
        poll.delegate = self
        detail.delegate = self
        significant.delegate = self
        
        let oldKey = "points.option.tracking_type"
        if UserDefaults.standard.string(forKey: oldKey) != nil {
            let old = UserDefaults.standard.integer(forKey: oldKey)
            Options.mode.set(value: old)
            UserDefaults.standard.removeObject(forKey: oldKey)
        }
    }
    
    func stats() -> String {
        return "\(detail.count).\(poll.count) \(mode):\(detail.flavour)"
    }

    func resetStats() {
        poll.count = 0
        detail.count = 0
    }
    
    func get(reason: String) {
        if fabs(lastDate.timeIntervalSinceNow).isLess(than: GPSManager.passiveCheckMinimumSeconds) {
            return
        }
        
        AppDelegate.shared?.notification(withTitle: "\(getpid()) Location detail", action: "ok", andBody: "\(reason)")
        poll.manager.requestLocation()
        lastDate = Date()
    }
    
    // MARK: Control state changes
    func kickManager(reason: String) {
        let configured = Mode(rawValue: Options.mode.get())
        if configured == .Best || configured == .Smart {
            self.setMode(value: configured!, reason: reason)
        }
    }
    
    func setMode(value: Mode, reason: String) {
        if value == .Off || value == .NotAuthorized {
            // continue
        } else if !self.authorized(value: value) {
            return
        } else if mode == value {
            return
        }
        
        if value == .Smart || value == .Best {
            let configured = Options.mode.get()
            if configured != Mode.Best.rawValue && configured != Mode.Smart.rawValue {
                AppDelegate.shared?.notification(withTitle: "Not switching from \(mode) updates to \(value)", action: "ok", andBody: "Need \(configured)")
                return
            }
        }
        
        AppDelegate.shared?.notification(withTitle: "Switching from \(mode) updates to \(value)", action: "ok", andBody: reason)
        //        PTSModelDelegate.save(pointsContext, caller: #function)
        mode = value
        
        switch mode {
        case .NotAuthorized:
            significant.stop(reason: reason)
            detail.stop(reason: reason)
            break
            
        case .Off:
            significant.stop(reason: reason)
            detail.stop(reason: reason)
            break
            
        case .LowPower:
            detail.stop(reason: reason)
            significant.start(reason: reason)
            break
            
        case .Best:
            significant.start(reason: reason)

            // Best == GPS
            // BestForNavigation == GPS + Other sensor data
            detail.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            detail.manager.pausesLocationUpdatesAutomatically = false
            
            Options.accuracy.activate(value: Options.accuracy.getActive(from: detail.manager), for: detail.manager)
            Options.filter.activate(value: 10, for: detail.manager)

            detail.start(reason: reason)
            break
            
        case .Smart:
            significant.start(reason: reason)
            
            detail.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            detail.manager.pausesLocationUpdatesAutomatically = true

            Options.accuracy.activate(value: Options.accuracy.getActive(from: detail.manager), for: detail.manager)
            Options.factor.activate(value: 3, for: detail.manager)

            detail.start(reason: reason)
            break
        }
    }
    
    // MARK: Location API Callbacks
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        if(Options.mode.get() == Mode.Best.rawValue && mode == .NotAuthorized) {
            AppDelegate.shared?.notification(withTitle: "GPS tracking is currently paused", action: "re-enable", andBody: "Recording Stopped")
        }
        
        if(visit.departureDate < Date.distantPast) {
            detail.setFlavour(value: .GPS, reason: "Departed from \(visit.departureDate)")
        }
        
        delegate?.locationManager?(manager, didVisit: visit)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        //        [self syntheticVisit:false];
        if mode == .Off ||  mode == .NotAuthorized {
            AppDelegate.shared?.notification(withTitle: "\(getpid()) Called", action: "ok", andBody: "Got \(locations.count) \(mode):\(detail.flavour):\(manager == significant.manager) updates from \(locations[0])")
            return
    
        } else if manager == significant.manager {
            AppDelegate.shared?.notification(withTitle: "\(getpid()) Called", action: "ok", andBody: "Got \(locations.count) \(mode):\(detail.flavour) updates from \(locations[0])")

            if mode == .Smart {
                detail.setFlavour(value: .GPS, reason: "Significant movement")

            } else if mode == .LowPower {
                delegate?.locationManager?(manager, didUpdateLocations: locations)
            }

        } else {
            delegate?.locationManager?(manager, didUpdateLocations: locations)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        let locationError = error as? CLError
        
        switch(locationError!.code) {
        case .locationUnknown: // location is currently unknown, but CL will keep trying
            return
        case .denied: // Access to location or ranging has been denied by the user
            self.setMode(value: .NotAuthorized, reason: "Location error \(manager == detail.manager)")
            return
            
        case .network: // general, network-related error
            return
            
        case .headingFailure: // heading could not be determined
            break
            
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
            detail.setFlavour(value: .GPS, reason: "Deferred updates failed: \(error.localizedDescription)")
            return
            
        case .deferredNotUpdatingLocation: // Deferred mode failed because location updates disabled or paused
            return
            
        case .deferredAccuracyTooLow: // Deferred mode not supported for the requested accuracy
            detail.deferrable = false
            detail.setFlavour(value: .GPS, reason: "Deferred updates failed: \(error.localizedDescription)")
            return
            
        case .deferredDistanceFiltered: // Deferred mode does not support distance filters
            detail.deferrable = false
            detail.setFlavour(value: .GPS, reason: "Deferred updates failed: \(error.localizedDescription)")
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
        
        AppDelegate.shared?.notification(withTitle: "Location API error", action: "ok", andBody: "\(locationError!.code.rawValue) \(locationError!.localizedDescription)")
//        detail.setFlavour(value: .GPS, reason: "Deferred updates failed \(error.localizedDescription)")
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
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                GPSManager.shared.setMode(value: .LowPower, reason: "(Low power) didChangeAuthorization")
                
            } else {
                let pref = Options.mode.get()
                let prefMode = Mode.init(rawValue: pref)!
                self.setMode(value: prefMode, reason: "didChangeAuthorization")
            }
        }
    }
    
    // MARK: Helpers
    func authorized(value: Mode) -> Bool {
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            if value != .Off {
                
                if(value == .Best && UIApplication.shared.applicationState == UIApplicationState.active) {
                    detail.manager.requestAlwaysAuthorization()
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
    
    static func managerInit(lm: CLLocationManager) {
        lm.allowsBackgroundLocationUpdates = true
        lm.pausesLocationUpdatesAutomatically = false
        
//        _ = Options.accuracy.restore(to: lm)
//        _ = Options.filter.restore(to: lm)

        lm.headingFilter = passiveCheckMinimumHeading
        lm.desiredAccuracy = defaultDesiredAccuracy
    }
    
    func restore(to manager: CLLocationManager) {
        _ = Options.mode.restore(to: manager)
        _ = Options.flavour.restore(to: manager)
        _ = Options.accuracy.restore(to: manager)
        _ = Options.filter.restore(to: manager)
    }
    
    // MARK: Options
    enum Options: String {
        case mode     = "option.gps.mode"
        case flavour  = "option.gps.flavour"
        case accuracy = "option.gps.accuracy"
        case filter   = "option.gps.filter"
        case factor   = "option.gps.factor"
        
        func get() -> Int {
            return UserDefaults.standard.integer(forKey: self.rawValue)
        }
        
        func set(value: Int) {
            UserDefaults.standard.set(value, forKey: self.rawValue)
        }
        
        func activate(value: Int, for manager: CLLocationManager) {
            UserDefaults.standard.set(value, forKey: self.rawValue)
            self.setActive(value: value, with: manager)
        }
        
        func restore(to manager: CLLocationManager) -> Int {
            let stored = UserDefaults.standard.integer(forKey: self.rawValue)
            self.setActive(value: stored, with: manager)
            return stored
        }
        
        func getActive(from manager: CLLocationManager) -> Int {
            switch self {
            case .mode:
                return GPSManager.shared.mode.rawValue
            case .flavour:
                return GPSManager.shared.detail.flavour.rawValue
            case .accuracy:
                return self.indexFor(accuracy: manager.desiredAccuracy)
            case .filter:
                return Int(manager.distanceFilter)
            case .factor:
                if Options.accuracy.get() > filterSlotsMaximum {
                    return Int(manager.distanceFilter)
                } else if manager.desiredAccuracy > 0 {
                    return Int(manager.distanceFilter / manager.desiredAccuracy)
                }
                return 0
            }
        }
        
        func setActive(value: Int, with manager: CLLocationManager) {
            switch self {
            case .mode:
                let mode = GPSManager.Mode(rawValue: value)
                GPSManager.shared.setMode(value: mode!, reason: #function)
                break
            case .flavour:
                GPSManager.shared.detail.setFlavour(value: Flavour(rawValue: value)!, reason: #function)
                break
            case .accuracy:
                manager.desiredAccuracy = self.accuracyFor(index: value)
                break
            case .filter:
                manager.distanceFilter = Double(value)
                break
            case .factor:
                if value <= 0 {
                    Options.filter.activate(value: Int(kCLDistanceFilterNone), for: manager)
                    
                } else if Options.accuracy.get() > filterSlotsMaximum {
                    Options.filter.activate(value: value, for: manager)
                    
                } else {
                    Options.filter.activate(value: Int(manager.desiredAccuracy) *  value, for: manager)
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
                AppDelegate.shared?.notification(withTitle: "Unhandled accuracy", action: "ok", andBody: "Active: \(GPSManager.shared.detail.manager.desiredAccuracy)")
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
