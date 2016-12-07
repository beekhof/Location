//
//  LocationDetail.swift
//  Points
//
//  Created by Andrew Beekhof on 7/12/16.
//  Copyright © 2016 ___ANDREWBEEKHOF___. All rights reserved.
//

import UIKit
import MapKit

class LocationDetail: NSObject, CLLocationManagerDelegate {
    
    let manager = CLLocationManager()

    var count: Int = 0
    var flavour: GPSManager.Flavour = .None
    var delegate: CLLocationManagerDelegate?
    var deferrable = CLLocationManager.deferredLocationUpdatesAvailable()
    
    override init() {
        super.init()
        manager.delegate = self
        GPSManager.managerInit(lm: manager)
    }
    
    func start(reason: String) {
        self.setFlavour(value: .GPS, reason: reason)
    }

    func stop(reason: String) {
        self.setFlavour(value: .None, reason: reason)
    }

    func setFlavour(value: GPSManager.Flavour, reason: String) {
        if value == flavour {
            return
            
        } else if value == .None {
            // continue
            
        } else if GPSManager.shared.mode != .Best && GPSManager.shared.mode != .Smart {
            AppDelegate.shared?.notification(withTitle: "\(getpid()) Ignoring flavour change", action: "ok", andBody: "Not switching from \(flavour) updates to \(value) - \(reason)")
            return
        }
        
        AppDelegate.shared?.notification(withTitle: "\(getpid()) Flavour change", action: "ok", andBody: "Switching from \(flavour) updates to \(value) - \(reason)")
        flavour = value
        
        // Note to self: Use heading in low power &/or smart mode?
        // Might be useful to know when to grab a new location, eg. turned a corner.
        
        switch flavour {
        case .None:
            manager.stopUpdatingLocation()
            manager.disallowDeferredLocationUpdates()
            UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
            break
        case .GPS:
            if deferrable {
                manager.disallowDeferredLocationUpdates()
            }
            
            manager.startUpdatingLocation()
            break
        case .Paused:
//            significant.manager.startUpdatingHeading()
            break
        }
    }
    
    // MARK: Location API
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        count += 1
        
        //        [self syntheticVisit:false];
        if flavour == .Paused {
            AppDelegate.shared?.notification(withTitle: "\(getpid()) Called", action: "ok", andBody: "Got \(locations.count) \(GPSManager.shared.mode):\(flavour) updates from \(locations[0])")
            
        } else if flavour == .None {
            return
        }
        
        if false && deferrable && locations.count == 1 {
            AppDelegate.shared?.notification(withTitle: "\(getpid()) Deferring", action: "ok", andBody: "\(GPSManager.shared.mode):\(flavour) Deferring from \(locations[0])")
            manager.allowDeferredLocationUpdates(untilTraveled: CLLocationDistanceMax, timeout: CLTimeIntervalMax)
        }
        
        delegate?.locationManager?(manager, didUpdateLocations: locations)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        let locationError = error as? CLError
        
        switch(locationError!.code) {
        case .locationUnknown: // location is currently unknown, but CL will keep trying
            delegate?.locationManager?(manager, didFailWithError: error)
            return

        case .denied: // Access to location or ranging has been denied by the user
            delegate?.locationManager?(manager, didFailWithError: error)
            return
            
        case .network: // general, network-related error
            delegate?.locationManager?(manager, didFailWithError: error)
            return
            
        case .deferredFailed: // Deferred mode failed
            delegate?.locationManager?(manager, didFailWithError: error)
            return
            
        case .deferredNotUpdatingLocation: // Deferred mode failed because location updates disabled or paused
            delegate?.locationManager?(manager, didFailWithError: error)
            return
            
        case .deferredAccuracyTooLow: // Deferred mode not supported for the requested accuracy
            delegate?.locationManager?(manager, didFailWithError: error)
            return
            
        case .deferredDistanceFiltered: // Deferred mode does not support distance filters
            AppDelegate.shared?.notification(withTitle: "Location API error", action: "ok", andBody: "\(locationError!.code.rawValue) \(locationError!.localizedDescription)")
            return
            
        case .deferredCanceled: // Deferred mode request canceled a previous request
            //            PTSPoint *point = [_model pointForLocation:manager.location inContext:self.pointsContext];
            //            point.flags |= point_flag_deferred;
            return
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.locationManager?(manager, didChangeAuthorization: status)
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        self.setFlavour(value: .Paused, reason: "GPS paused \(UIApplication.shared.backgroundTimeRemaining)")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        self.setFlavour(value: .GPS, reason: "GPS resumed \(UIApplication.shared.backgroundTimeRemaining)")
    }
}
