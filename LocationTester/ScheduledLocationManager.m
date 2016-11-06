//
//  ScheduledLlocationManager.m
//  LocationTester
//
//  Created by Andrew Beekhof on 2/10/16.
//  Copyright © 2016 Andrew Beekhof. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ScheduledLocationManager.h"

int const kMaxBGTime = 170; // 3 min - 10 seconds (as bg task is killed faster)
int const kTimeToGetLocations = 3; // time to wait for locations

@implementation ScheduledLocationManager
{
    UIBackgroundTaskIdentifier bgTask;
    CLLocationManager *locationManager;
    NSTimer *checkLocationTimer;
    NSTimer *waitForLocationUpdatesTimer;
}

- (id)init
{
    self = [super init];
    if (self) {
        locationManager = [[CLLocationManager alloc] init];
        locationManager.delegate = self;
        locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        locationManager.distanceFilter = kCLDistanceFilterNone;
        [locationManager requestAlwaysAuthorization];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

-(void)getUserLocationWithInterval:(int)interval
{
    self.checkLocationInterval = (interval > kMaxBGTime)? kMaxBGTime : interval;
    [locationManager startUpdatingLocation];
}

- (void)timerEvent:(NSTimer*)theTimer
{
    [self stopCheckLocationTimer];
    [locationManager startUpdatingLocation];
    
    // in iOS 7 we need to stop background task with delay, otherwise location service won't start
    [self performSelector:@selector(stopBackgroundTask) withObject:nil afterDelay:1];
}

-(void)startCheckLocationTimer
{
    [self stopCheckLocationTimer];
    checkLocationTimer = [NSTimer scheduledTimerWithTimeInterval:self.checkLocationInterval target:self selector:@selector(timerEvent:) userInfo:NULL repeats:NO];
}

-(void)stopCheckLocationTimer
{
    if(checkLocationTimer){
        [checkLocationTimer invalidate];
        checkLocationTimer=nil;
    }
}

-(void)startBackgroundTask
{
    [self stopBackgroundTask];
    bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        //in case bg task is killed faster than expected, try to start Location Service
        [self timerEvent:checkLocationTimer];
    }];
}

-(void)stopBackgroundTask
{
    if(bgTask!=UIBackgroundTaskInvalid){
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

-(void)stopWaitForLocationUpdatesTimer
{
    if(waitForLocationUpdatesTimer){
        [waitForLocationUpdatesTimer invalidate];
        waitForLocationUpdatesTimer =nil;
    }
}

-(void)startWaitForLocationUpdatesTimer
{
    [self stopWaitForLocationUpdatesTimer];
    waitForLocationUpdatesTimer = [NSTimer scheduledTimerWithTimeInterval:kTimeToGetLocations target:self selector:@selector(waitForLoactions:) userInfo:NULL repeats:NO];
}

- (void)waitForLoactions:(NSTimer*)theTimer
{
    [self stopWaitForLocationUpdatesTimer];
    
    if(([[UIApplication sharedApplication ]applicationState]==UIApplicationStateBackground ||
        [[UIApplication sharedApplication ]applicationState]==UIApplicationStateInactive) &&
       bgTask==UIBackgroundTaskInvalid){
        [self startBackgroundTask];
    }
    
    [self startCheckLocationTimer];
    [locationManager stopUpdatingLocation];
}

#pragma mark - CLLocationManagerDelegate methods

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    if(checkLocationTimer){
        //sometimes it happens that location manager does not stop even after stopUpdationLocations
        return;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(scheduledLocationManageDidUpdateLocations:)]) {
        [self.delegate scheduledLocationManageDidUpdateLocations:locations];
    }
    
    if(waitForLocationUpdatesTimer==nil){
        [self startWaitForLocationUpdatesTimer];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(scheduledLocationManageDidFailWithError:)]) {
        [self.delegate scheduledLocationManageDidFailWithError:error];
    }
}

#pragma mark - UIAplicatin notifications

- (void)applicationDidEnterBackground:(NSNotification *) notification
{
    if([self isLocationServiceAvailable]==YES){
        [self startBackgroundTask];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *) notification
{
    [self stopBackgroundTask];
    if([self isLocationServiceAvailable]==NO){
        NSError *error = [NSError errorWithDomain:@"your.domain" code:1 userInfo:[NSDictionary dictionaryWithObject:@"Authorization status denied" forKey:NSLocalizedDescriptionKey]];
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(scheduledLocationManageDidFailWithError:)]) {
            [self.delegate scheduledLocationManageDidFailWithError:error];
        }
    }
}

#pragma mark - Helpers

-(BOOL)isLocationServiceAvailable
{
    if([CLLocationManager locationServicesEnabled]==NO ||
       [CLLocationManager authorizationStatus]==kCLAuthorizationStatusDenied ||
       [CLLocationManager authorizationStatus]==kCLAuthorizationStatusRestricted){
        return NO;
    }else{
        return YES;
    }
}

@end
