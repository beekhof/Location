//
//  LocationPassive.swift
//  Points
//
//  Created by Andrew Beekhof on 7/12/16.
//  Copyright © 2016 ___ANDREWBEEKHOF___. All rights reserved.
//

import UIKit
import MapKit

class LocationPassive: NSObject, CLLocationManagerDelegate {

    let manager = CLLocationManager()
    var delegate: CLLocationManagerDelegate?
    
    let once = LocationOnce()
    
    override init() {
        super.init()
        
        manager.delegate = self
        GPSManager.managerInit(lm: manager)
    }
    
    func start(reason: String) {
        AppDelegate.shared?.notification(withTitle: "\(getpid()) Starting passive updates", action: "ok", andBody: "Starting passive updates \(reason)")
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        manager.startUpdatingHeading()
    }

    func stop(reason: String) {
        AppDelegate.shared?.notification(withTitle: "\(getpid()) Stopping passive updates", action: "ok", andBody: "Stopping passive updates \(reason)")
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        manager.stopUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        delegate?.locationManager?(manager, didVisit: visit)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        once.get(with: self.delegate, reason: "New heading \(newHeading)") // Get a reading when we turn a corner?
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        once.get(with: self.delegate, reason: "Significant change \(locations[0])")
        return
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let locationError = error as? CLError
        AppDelegate.shared?.notification(withTitle: "(Sig) Location API error", action: "ok", andBody: "\(locationError!.code.rawValue) \(locationError!.localizedDescription)")
        
        if locationError!.code == .denied {
            delegate?.locationManager?(manager, didFailWithError: error)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        AppDelegate.shared?.notification(withTitle: "(Sig) Auth change", action: "ok", andBody: "Sig auth status \(status))")
        delegate?.locationManager?(manager, didChangeAuthorization: status)
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        AppDelegate.shared?.notification(withTitle: "(Sig) GPS Paused", action: "ok", andBody: "Sig Paused \(UIApplication.shared.backgroundTimeRemaining))")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        AppDelegate.shared?.notification(withTitle: "(Sig) GPS Resumed", action: "ok", andBody: "Sig Resumed \(UIApplication.shared.backgroundTimeRemaining))")
    }
    
    class LocationOnce: NSObject, CLLocationManagerDelegate {
        let manager = CLLocationManager()
        var notify: CLLocationManagerDelegate?
        
        var count = 0
        var last: CLLocation?
      
        override init() {
            super.init()
            
            manager.delegate = self
            GPSManager.managerInit(lm: manager)
        }
        
        func get(with delegate: CLLocationManagerDelegate?, reason: String) {
            if last != nil && fabs(last!.timestamp.timeIntervalSinceNow).isLess(than: 120.0) {
                return
            }

            AppDelegate.shared?.notification(withTitle: "\(getpid()) Location detail", action: "ok", andBody: "\(reason) \(delegate != nil)")
            self.notify = delegate
            manager.requestLocation()
        }
        
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            count += 1
            
            for location in locations {
                let distance = last?.distance(from: location)
                
                if location.horizontalAccuracy > 100.0 {
                    AppDelegate.shared?.notification(withTitle: "Insignificant change (accuracy)", action: "ok", andBody: "\(getpid()).\(locations.count) Insignificant accuracy \(location.horizontalAccuracy)")
                    continue
                    
                } else if last == nil {
                    AppDelegate.shared?.notification(withTitle: "First significant", action: "ok", andBody: "\(getpid()).\(locations.count) First significant \(location)")
                    last = location
                    
                } else if distance != nil && distance!.isLess(than: 30.0) == false {
                    AppDelegate.shared?.notification(withTitle: "Significant change", action: "ok", andBody: "\(getpid()).\(locations.count) \(distance)m : Significant \(location)")
                    notify?.locationManager?(manager, didUpdateLocations: [ location ])
                    last = location
                    
                } else {
                    AppDelegate.shared?.notification(withTitle: "Insignificant change (distance)", action: "ok", andBody: "\(getpid()).\(locations.count) Insignificant \(distance)m : \(location)")
                }
            }
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            let locationError = error as? CLError
            AppDelegate.shared?.notification(withTitle: "(Once) Location API error", action: "ok", andBody: "\(locationError!.code.rawValue) \(locationError!.localizedDescription)")
            
            if locationError!.code == .denied {
                notify?.locationManager?(manager, didFailWithError: error)
            }
        }

    }
    

}
