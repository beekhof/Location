//
//  LocationPoller.swift
//  Points
//
//  Created by Andrew Beekhof on 8/12/16.
//  Copyright © 2016 ___ANDREWBEEKHOF___. All rights reserved.
//

import UIKit
import MapKit

class LocationPoller: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var delegate: CLLocationManagerDelegate?
    
    var count = 0
    var last: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        GPSManager.managerInit(lm: manager)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        count += 1
        
        for location in locations {
            let distance = last?.distance(from: location)
            
            if location.horizontalAccuracy > GPSManager.passiveCheckMinimumAccuracy {
                AppDelegate.shared?.notification(withTitle: "Insignificant change (accuracy)", action: "ok", andBody: "\(getpid()).\(locations.count) Insignificant accuracy \(location.horizontalAccuracy)")
                continue
                
            } else if last == nil {
                last = location
                
            } else if distance != nil && distance!.isLess(than: GPSManager.passiveCheckMinimumMeters) == false {
                AppDelegate.shared?.notification(withTitle: "Significant change", action: "ok", andBody: "\(getpid()).\(locations.count) \(distance)m : Significant \(location)")
                delegate?.locationManager?(manager, didUpdateLocations: [ location ])
                last = location
                
//            } else {
//                AppDelegate.shared?.notification(withTitle: "Insignificant change (distance)", action: "ok", andBody: "\(getpid()).\(locations.count) Insignificant \(distance)m : \(location)")
            }
        }

    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let locationError = error as? CLError
        AppDelegate.shared?.notification(withTitle: "(Once) Location API error", action: "ok", andBody: "\(locationError!.code.rawValue) \(locationError!.localizedDescription)")
        
        if locationError!.code == .denied {
            delegate?.locationManager?(manager, didFailWithError: error)
        }
    }
    
}
