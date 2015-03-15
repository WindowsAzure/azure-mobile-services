//
//  MSManagedObjectObserverTests.m
//  WindowsAzureMobileServices
//
//  Created by Damien Pontifex on 13/03/2015.
//  Copyright (c) 2015 Windows Azure. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MSCoreDataStore.h"
#import "MSCoreDataStore+TestHelper.h"
#import "MSJSONSerializer.h"
#import "TodoItem.h"
#import "MSManagedObjectObserver.h"
#import "MSTableOperation.h"

@interface MSManagedObjectObserverTests : XCTestCase
@property (nonatomic, strong) MSClient *client;
@property (nonatomic, strong) MSCoreDataStore *store;
@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) MSManagedObjectObserver *observer;

@property (nonatomic, strong) TodoItem *item;
@end

@implementation MSManagedObjectObserverTests

/// Helper method so we can start observing at the point we want to rather than initialized during setup
- (void)startObservingContextWithObservationCompletion:(MSManagedObjectObserverCompletionBlock)completionBlock
{
	self.observer = [[MSManagedObjectObserver alloc] initWithClient:self.client];
	self.observer.observerActionCompleted = completionBlock;
}

- (void)insertTestItem
{
	self.item = [NSEntityDescription insertNewObjectForEntityForName:@"TodoItem" inManagedObjectContext:self.context];
	
	self.item.text = @"Test item";
	self.item.id = @"ABC";
	
	[self.context save:nil];
}

- (void)setUp
{
    [super setUp];
	
	self.context = [MSCoreDataStore inMemoryManagedObjectContext];
	self.store = [[MSCoreDataStore alloc] initWithManagedObjectContext:self.context];
	
	self.client = [[MSClient alloc] initWithApplicationURL:nil applicationKey:nil];
	self.client.syncContext = [[MSSyncContext alloc] initWithDelegate:nil dataSource:self.store callback:nil];
}

- (void)tearDown
{
	self.store = nil;
	
    [super tearDown];
}

- (void)testObservingInsertOperation
{
	XCTestExpectation *expectation = [self expectationWithDescription:@"Table operation observed"];
	
	[self startObservingContextWithObservationCompletion:^(MSTableOperationTypes operationType, NSDictionary *item, NSError *error) {
		NSFetchRequest *tableOperationsRequest = [NSFetchRequest fetchRequestWithEntityName:@"MS_TableOperations"];
		NSArray *tableOperations = [self.context executeFetchRequest:tableOperationsRequest error:nil];
		
		XCTAssertEqual(tableOperations.count, 1, @"Should have one insert operation after the save of TodoItem %@", self.item);
		
		NSManagedObject *tableOperation = tableOperations.firstObject;
		NSString *operationTable = [tableOperation valueForKey:@"table"];
		XCTAssertEqualObjects(operationTable, self.item.entity.name, @"The operation should be associated for the %@ table", self.item.entity.name);
		
		NSString *operationItemId = [tableOperation valueForKey:@"itemId"];
		XCTAssertEqualObjects(operationItemId, self.item.id, @"The operation should be associated for the inserted item with id %@", self.item.id);
		
		NSDictionary *properties = [[MSJSONSerializer JSONSerializer] itemFromData:[tableOperation valueForKey:@"properties"] withOriginalItem:nil ensureDictionary:YES orError:nil];
		
		XCTAssertEqual([properties[@"type"] integerValue], MSTableOperationInsert, @"Associated operation should be an insert with newly created object");
		
		[expectation fulfill];
	}];
	
	[self insertTestItem];
	
	[self waitForExpectationsWithTimeout:3 handler:^(NSError *error) {
		if (error != nil)
		{
			XCTFail(@"Expectation for observer save failed");
		}
	}];
}

- (void)testObservingUpdateOperation
{
	[self insertTestItem];
	
	XCTestExpectation *expectation = [self expectationWithDescription:@"Update object expectation"];
	
	// Start observing after insert as we are only concerned about subsequent updates
	[self startObservingContextWithObservationCompletion:^(MSTableOperationTypes operationType, NSDictionary *item, NSError *error) {
		NSFetchRequest *tableOperationsRequest = [NSFetchRequest fetchRequestWithEntityName:@"MS_TableOperations"];
		NSArray *tableOperations = [self.context executeFetchRequest:tableOperationsRequest error:nil];
		
		XCTAssertEqual(tableOperations.count, 1, @"Should have one insert operation after the save of TodoItem %@", self.item);
		
		NSManagedObject *tableOperation = tableOperations.firstObject;
		NSString *operationTable = [tableOperation valueForKey:@"table"];
		XCTAssertEqualObjects(operationTable, self.item.entity.name, @"The operation should be associated for the %@ table", self.item.entity.name);
		
		NSString *operationItemId = [tableOperation valueForKey:@"itemId"];
		XCTAssertEqualObjects(operationItemId, self.item.id, @"The operation should be associated for the inserted item with id %@", self.item.id);
		
		NSDictionary *properties = [[MSJSONSerializer JSONSerializer] itemFromData:[tableOperation valueForKey:@"properties"] withOriginalItem:nil ensureDictionary:YES orError:nil];
		
		XCTAssertEqual([properties[@"type"] integerValue], MSTableOperationUpdate, @"Associated operation should be an insert with newly created object");
		
		[expectation fulfill];
	}];
	
	self.item.text = @"Test item updated";
	[self.context save:nil];
	
	[self waitForExpectationsWithTimeout:3 handler:^(NSError *error) {
		if (error != nil)
		{
			XCTFail(@"Failed to perform update operation in 3 seconds");
		}
	}];
}

- (void)testObservingDeleteOperation
{
	[self insertTestItem];
	
	XCTestExpectation *expectation = [self expectationWithDescription:@"Update object expectation"];
	
	NSString *originalItemId = self.item.id;
	
	[self startObservingContextWithObservationCompletion:^(MSTableOperationTypes operationType, NSDictionary *item, NSError *error) {
		NSFetchRequest *tableOperationsRequest = [NSFetchRequest fetchRequestWithEntityName:@"MS_TableOperations"];
		NSArray *tableOperations = [self.context executeFetchRequest:tableOperationsRequest error:nil];
		
		XCTAssertEqual(tableOperations.count, 1, @"Should have one insert operation after the save of TodoItem %@", self.item);
		
		NSManagedObject *tableOperation = tableOperations.firstObject;
		NSString *operationTable = [tableOperation valueForKey:@"table"];
		XCTAssertEqualObjects(operationTable, self.item.entity.name, @"The operation should be associated for the %@ table", self.item.entity.name);
		
		NSString *operationItemId = [tableOperation valueForKey:@"itemId"];
		XCTAssertEqualObjects(operationItemId, originalItemId, @"The operation should be associated for the inserted item with id %@", originalItemId);
		
		NSDictionary *properties = [[MSJSONSerializer JSONSerializer] itemFromData:[tableOperation valueForKey:@"properties"] withOriginalItem:nil ensureDictionary:YES orError:nil];
		
		XCTAssertEqual([properties[@"type"] integerValue], MSTableOperationDelete, @"Associated operation should be an insert with newly created object");
		
		XCTAssertNotNil(properties[@"item"], @"Properties should contain the deleted item");
		
		[expectation fulfill];
	}];
	
	[self.context deleteObject:self.item];
	[self.context save:nil];
	
	[self waitForExpectationsWithTimeout:3 handler:^(NSError *error) {
		if (error != nil)
		{
			XCTFail(@"Failed to perform delete in 3 seconds");
		}
	}];
}

@end