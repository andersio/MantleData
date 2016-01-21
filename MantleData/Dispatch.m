//
//  Dispatch.m
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Dispatch.h"

void _mantleData_dispatch_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block) {
	dispatch_sync(queue, block);
}

void _mantleData_dispatch_barrier_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block) {
	_mantleData_dispatch_barrier_sync(queue, block);
}

@implementation NSManagedObjectContext (PerformBlockAndWaitNoEscape)
- (void)performBlockAndWaitNoEscape:(__attribute__((noescape)) void (^)(void))block {
	[self performBlockAndWait:block];
}
@end