//
//  Dispatch.h
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

#import <CoreData/CoreData.h>

void _mantleData_dispatch_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block);
void _mantleData_dispatch_barrier_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block);

@interface NSManagedObjectContext (PerformBlockAndWaitNoEscape)
- (void)performBlockAndWaitNoEscape:(__attribute__((noescape)) void (^)(void))block;
@end