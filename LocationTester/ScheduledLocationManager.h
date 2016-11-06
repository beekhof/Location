//
//  ScheduledLlocationManager.h
//  LocationTester
//
//  Created by Andrew Beekhof on 2/10/16.
//  Copyright © 2016 Andrew Beekhof. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@protocol ScheduledLocationManagerDelegate <NSObject>

-(void)scheduledLocationManageDidFailWithError:(NSError*)error;
-(void)scheduledLocationManageDidUpdateLocations:(NSArray*)locations;

@end

@interface ScheduledLocationManager : NSObject <CLLocationManagerDelegate>

-(void)getUserLocationWithInterval:(int)interval;

@property int checkLocationInterval;
@property (nonatomic, weak) id<ScheduledLocationManagerDelegate> delegate;

@end
