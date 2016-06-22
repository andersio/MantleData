//
//  NSManagedObjectContext+Additions.m
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

#import <CoreData/CoreData.h>

@implementation NSManagedObjectContext (PerformBlockAndWaitNoEscape)
- (void)performBlockAndWaitNoEscape:(__attribute__((noescape)) void (^)(void))block {
	@try {
		[self performBlockAndWait:block];
	}
	@catch(NSException* exception) {
		NSLog(@"EXCEPTION: %@\nREASON: %@", exception.name, exception.reason);
		@throw;
	}
}
@end
