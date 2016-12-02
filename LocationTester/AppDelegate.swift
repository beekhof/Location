//
//  AppDelegate.swift
//  LocationTester
//
//  Created by Andrew Beekhof on 2/10/16.
//  Copyright © 2016 Andrew Beekhof. All rights reserved.
//

import UIKit
import CoreData
import UserNotifications
import AVFoundation
import MapKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CLLocationManagerDelegate {

    var window: UIWindow?
    let manager: GPSManager = GPSManager.shared

    static var shared: AppDelegate? {
        get {
            return UIApplication.shared.delegate as? AppDelegate
        }
    }

    func notification(withTitle title: String, action: String, andBody body: String) {
        
        print("[Notify] \(UIApplication.shared.applicationState.rawValue):\(UIApplicationState.background.rawValue) \(title): \(body)")
        
        if UIApplication.shared.applicationState == UIApplicationState.active {
            OperationQueue.main.addOperation({
                let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: action, style: .cancel, handler: nil))
                self.window?.rootViewController?.present(alert, animated: true, completion: nil)
            })
            
        } else if UIApplication.shared.applicationState == UIApplicationState.background {
            let notify = UILocalNotification()
            notify.fireDate = Date()
            notify.timeZone = NSTimeZone.default
            notify.alertBody = body
            notify.alertAction = action
            notify.alertTitle = title
            notify.soundName = UILocalNotificationDefaultSoundName
            //        gpsNotify.applicationIconBadgeNumber = 6;
            notify.repeatInterval = NSCalendar.Unit(rawValue: UInt(0))
            UIApplication.shared.presentLocalNotificationNow(notify)
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        manager.delegate = self
        self.notification(withTitle: "Launch", action: "ok", andBody: "Launch \(launchOptions?[UIApplicationLaunchOptionsKey.location] != nil) \(launchOptions)")

        return true
    }

    // MARK: Location API
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            print(location)
        }
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.notification(withTitle: "Fetching", action: "ok", andBody: "\(getpid()) fetching at \(Date())")
        completionHandler(UIBackgroundFetchResult.newData)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        self.notification(withTitle: "Deactivating", action: "ok", andBody: "\(getpid()) deactivating at \(Date())")
   }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        GPSManager.shared.locationManager(GPSManager.shared.manager, didChangeAuthorization: CLLocationManager.authorizationStatus())
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
//        self.saveContext()
        self.notification(withTitle: "Exiting", action: "ok", andBody: "\(getpid()) exiting at \(Date())")
    }
}

