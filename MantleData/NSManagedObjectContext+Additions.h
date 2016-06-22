//
//  NSManagedObjectContext+Additions.h
//  MantleData
//
//  Created by Anders on 14/12/2015.
//  Copyright © 2015 Anders. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectContext (PerformBlockAndWaitNoEscape)
- (void)performBlockAndWaitNoEscape:(nonnull __attribute__((noescape)) void (^)(void))block;
@end
