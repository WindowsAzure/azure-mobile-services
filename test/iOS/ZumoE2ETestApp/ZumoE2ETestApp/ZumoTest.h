//
//  ZumoTest.h
//  ZumoE2ETestApp
//
//  Created by Carlos Figueira on 12/7/12.
//  Copyright (c) 2012 Microsoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZumoTestCallbacks.h"

typedef void (^ZumoTestCompletion)(BOOL testPassed);
typedef void (^ZumoTestExecution)(UIViewController *viewController, ZumoTestCompletion completion);

typedef enum { TSNotRun, TSRunning, TSFailed, TSPassed } TestStatus;

@interface ZumoTest : NSObject
{
    NSMutableArray *logs;
}

@property (nonatomic, weak) id<ZumoTestCallbacks> delegate;

@property (nonatomic, strong) NSString *testName;
@property (nonatomic, copy) ZumoTestExecution execution;
@property (nonatomic) TestStatus testStatus;

+ (ZumoTest *)createTestWithName:(NSString *)name andExecution:(ZumoTestExecution)steps;

- (void)resetStatus;
- (void)startExecutingFrom:(UIViewController *)currentViewController;
- (void)addLog:(NSString *)text;
- (NSArray *)getLogs;

@end
