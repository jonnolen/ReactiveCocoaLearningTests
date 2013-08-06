//
//  rac_signal_testTests.m
//  rac_signal_testTests
//
//  Created by Jonathan Nolen on 7/30/13.
//  Copyright (c) 2013 test. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>
#import <SenTestingKit/SenTestingKit.h>
#import <ReactiveCocoa/NSNotificationCenter+RACSupport.h>

NSString *const kTestNotification = @"TEST_NOTIFICATION";
NSString *const kTestNotification2 = @"TEST_NOTIFICATION2";

@interface RACTestObject :NSObject
@property (nonatomic, weak) NSObject *property;
@end
@implementation RACTestObject
@end



@interface rac_signal_testTests : SenTestCase

@end


@interface NSNotificationCenter (PW_RAC_EXTENSION)
-(RACSignal *)pw_rac_addOneShotObserverForName:(NSString *)name object:(id)object;
@end

@implementation NSNotificationCenter(PW_RAC_EXTENSION)

-(RACSignal *)pw_rac_addOneShotObserverForName:(NSString *)name object:(id)object{
    return [[[NSNotificationCenter defaultCenter] rac_addObserverForName:name object:object] take:1];        
}

@end
@implementation rac_signal_testTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}


- (void)test_notification_signal_signal
{
    __block BOOL hitNext;
    __block BOOL hitComplete;
    __block BOOL hitDispose;
    
    RACSignal *signal = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber){
        RACSignal *inner_signal = [[NSNotificationCenter defaultCenter] rac_addObserverForName:kTestNotification object:self];
        
        RACDisposable *inner_signal_disposer = [inner_signal subscribeNext:^(NSNotification *notification){
            [subscriber sendNext:notification];
            [subscriber sendCompleted];
        }];
        
        return [RACDisposable disposableWithBlock:^{
            [inner_signal_disposer dispose];
            hitDispose = YES;
        }];
    }];    
    
    RACDisposable *signal_disposer = [signal subscribeNext:^(NSNotification *notification){
        hitNext = YES;
                }
                completed:^{
                    hitComplete = YES;
                }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kTestNotification object:self];
    
    [signal_disposer dispose];
    
    STAssertTrue(hitComplete, nil);
    STAssertTrue(hitNext, nil);
    STAssertTrue(hitDispose, nil);
}

-(void)test_merged_notifications_not_complete_after_one{
    RACSignal *notification1_signal = [[NSNotificationCenter defaultCenter] pw_rac_addOneShotObserverForName:kTestNotification object:self];
    RACSignal *notification2_signal = [[NSNotificationCenter defaultCenter] pw_rac_addOneShotObserverForName:kTestNotification2 object:self];
    
    
    RACSignal *merged = [RACSignal merge:@[notification1_signal, notification2_signal]];
    
    __block BOOL hitComplete = NO;

    [merged subscribeNext:^(NSNotification *notification){
        
    }
                completed:^{
                    hitComplete = YES;
    }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kTestNotification object:self];
    
    STAssertFalse(hitComplete, nil);
}

-(void)test_merged_notifications_complete{
    RACSignal *notification1_signal = [[NSNotificationCenter defaultCenter] pw_rac_addOneShotObserverForName:kTestNotification object:self];
    RACSignal *notification2_signal = [[NSNotificationCenter defaultCenter] pw_rac_addOneShotObserverForName:kTestNotification2 object:self];
    
    
    RACSignal *merged = [RACSignal merge:@[notification1_signal, notification2_signal]];
    
    __block BOOL hitComplete = NO;
    
    [merged subscribeNext:^(NSNotification *notification){
        
    }
                                          completed:^{
                                              hitComplete = YES;
                                          }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kTestNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTestNotification2 object:self];
    STAssertTrue(hitComplete, nil);
}

-(void)test_merged_subjects_will_complete{
    RACSubject *subject1 = [[RACSubject subject] setNameWithFormat:@"subject1"];
    RACSubject *subject2 = [[RACSubject subject] setNameWithFormat:@"subject2"];
    
    RACSignal *merged = [RACSignal merge:@[subject1, subject2]];
    
    __block BOOL completed_fired = NO;
    
    [merged subscribeCompleted:^{
        completed_fired = YES;
    }];
    
    [subject1 sendNext:@"1"];
    [subject2 sendNext:@"2"];
    
    [subject1 sendCompleted];
    [subject2 sendCompleted];
    
    STAssertTrue(completed_fired, nil);
}

-(void)test_merged_subjects_will_complete_if_one_of_them_has_a_throttled_subscriber{
    RACSubject *subject1 = [[RACSubject subject] setNameWithFormat:@"subject1"];
    RACSubject *subject2 = [[RACSubject subject] setNameWithFormat:@"subject2"];
    
    __block NSString * hit_subject2_next = nil;
    [[subject2 throttle:.5] subscribeNext:^(NSString *value){
        hit_subject2_next = value;
    }];
    
    RACSignal *merged = [RACSignal merge:@[subject1, subject2]];
    
    __block BOOL completed_fired = NO;
    
    [merged subscribeCompleted:^{
        completed_fired = YES;
    }];

    [subject2 sendNext:@"2"];
    [subject2 sendCompleted];
    [subject1 sendCompleted];
    STAssertEqualObjects(@"2", hit_subject2_next, nil);
    STAssertTrue(completed_fired, nil);
}

-(void)test_assert_gcd_scheduler{
    __block RACScheduler *scheduler = nil;
    __block BOOL done = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        scheduler = RACScheduler.currentScheduler;
        done = YES;
    });

    NSDate *startTime = NSDate.date;
    do{
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }while(!done && [NSDate.date timeIntervalSinceDate:startTime] <= 10.0);
    
    STAssertNil(scheduler, nil);

}

-(void)test_maybe_its_the_background_thread{
    __block BOOL complete = NO;
    [[RACScheduler scheduler] schedule:^{
        RACSubject *subject1 = [[RACSubject subject] setNameWithFormat:@"subject1"];
        RACSubject *subject2 = [[RACSubject subject] setNameWithFormat:@"subject2"];
        
        
        RACSignal *sig1 = [[subject1 logAll] deliverOn:RACScheduler.mainThreadScheduler];
        RACSignal *sig2 = [[subject2 logAll] deliverOn:RACScheduler.mainThreadScheduler];
        
        
        RACSignal *merged = [RACSignal merge:@[sig1, sig2]];
        
        [merged subscribeNext:^(NSString *next){
            NSLog(@"GOT NEXT.");
        } completed:^{
            complete = YES;
        }];
        
        [subject2 sendNext:@"2"];
//        dispatch_async(dispatch_get_main_queue(), ^{
            [subject1 sendCompleted];
            [subject2 sendCompleted];
//        });
    }];
    
    NSDate *startTime = NSDate.date;
    do{
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }while(!complete && [NSDate.date timeIntervalSinceDate:startTime] <= 10.0);
    
    STAssertTrue(complete, nil);
}

-(void)test_flatten_map_maps_next_to_error{
    
    RACSignal *completeSignal = [RACSignal return:@"hello"];
    __block NSString *completeSignalErrorMessage;
    
    __block BOOL hit_error = NO;
    [[completeSignal flattenMap:^RACSignal *(NSString *aMessage){
        return [RACSignal error:[NSError errorWithDomain:@"RAC_TEST_DOMAIN" code:1 userInfo:@{@"message":aMessage}]];
    }] subscribeError:^(NSError *error){
        completeSignalErrorMessage = error.userInfo[@"message"];
        hit_error = YES;
    }];
    STAssertEqualObjects(@"hello", completeSignalErrorMessage, nil);
    STAssertTrue(hit_error, nil);
}

-(void)test_flatten_signal_of_signals_and_complete{
    RACSubject *errorNotification = [RACSubject subject];
    RACSubject *completeNotification = [RACSubject subject];
    
    RACSignal *signalOfSignals = [RACSignal
                                  createSignal:^RACDisposable *(id<RACSubscriber> subscriber){
                                      RACDisposable *successDisposer = [completeNotification
                                                                        subscribeNext:^(NSNotification *notification){
                                                                            [subscriber sendNext:notification];
                                                                        }
                                                                        completed:^{
                                                                            [subscriber sendCompleted];
                                                                        }];
                                      
                                      RACDisposable *failureDisposer = [errorNotification
                                                                        subscribeError:^(NSError *err){
                                                                            [subscriber sendError:err];
                                                                        }];
                                      
                                      return [RACDisposable disposableWithBlock:^{
                                          [successDisposer dispose];
                                          [failureDisposer dispose];
                                      }];
                                  }];
    

    __block BOOL hitCompleted = NO;
    __block NSString *nextVal = nil;

    [signalOfSignals
     subscribeNext:^(id val){
         nextVal = val;
     }
     error:^(NSError *err){
         STFail(nil);
     }
     completed:^{
         hitCompleted = YES;
     }];
    
    [completeNotification sendNext:@"hello"];
    [completeNotification sendCompleted];
    
    STAssertTrue(hitCompleted, nil);
    STAssertEqualObjects(nextVal, @"hello", nil);
}


-(void)test_flatten_signal_of_signals_and_error{
    RACSubject *errorNotification = [RACSubject subject];
    RACSubject *completeNotification = [RACSubject subject];
    
    RACSignal *signalOfSignals = [RACSignal
                                  createSignal:^RACDisposable *(id<RACSubscriber> subscriber){
                                      RACDisposable *successDisposer = [completeNotification
                                                                        subscribeNext:^(NSNotification *notification){
                                                                            [subscriber sendNext:notification];
                                                                        }
                                                                        completed:^{
                                                                            [subscriber sendCompleted];
                                                                        }];
                                      
                                      RACDisposable *failureDisposer = [errorNotification
                                                                        subscribeError:^(NSError *err){
                                                                            [subscriber sendError:err];
                                                                        }];
                                      
                                      return [RACDisposable disposableWithBlock:^{
                                          [successDisposer dispose];
                                          [failureDisposer dispose];
                                      }];
                                  }];

    
    
    __block BOOL hitCompleted = NO;

    [signalOfSignals
     subscribeNext:^(id val){
         STAssertFalse(YES, nil);
     }
     error:^(NSError *err){
          hitCompleted = YES;
     }
     completed:^{
         STAssertFalse(YES, nil);
     }];

    [errorNotification sendError:[NSError errorWithDomain:@"RAC_TEST" code:1 userInfo:nil]];
    
    STAssertTrue(hitCompleted, nil);
}

-(void)test_flatten_signal_of_signals_and_convert_notification_to_error{
    RACSignal *errorNotification = [[[NSNotificationCenter defaultCenter] rac_addObserverForName:@"TEST_FAILURE" object:nil] take:1];
    
    
    errorNotification = [errorNotification flattenMap:^(NSNotification *notification){
        return [RACSignal error:[NSError errorWithDomain:@"RAC_TEST" code:1 userInfo:nil]];
    }];
    
    RACSubject *completeNotification = [RACSubject subject];
    
    RACSignal *signalOfSignals = [RACSignal
                                  createSignal:^RACDisposable *(id<RACSubscriber> subscriber){
                                      RACDisposable *successDisposer = [completeNotification
                                                                        subscribeNext:^(NSNotification *notification){
                                                                            [subscriber sendNext:notification];
                                                                        }
                                                                        completed:^{
                                                                            [subscriber sendCompleted];
                                                                        }];
                                      
                                      RACDisposable *failureDisposer = [errorNotification
                                                                        subscribeError:^(NSError *err){
                                                                            [subscriber sendError:err];
                                                                        }];
                                      
                                      return [RACDisposable disposableWithBlock:^{
                                          [successDisposer dispose];
                                          [failureDisposer dispose];
                                      }];
                                  }];
    
    
    __block BOOL hitCompleted = NO;
    
    [signalOfSignals
     subscribeNext:^(id val){
         STFail(nil);
     }
     error:^(NSError *err){
         hitCompleted = YES;
     }
     completed:^{
         STFail(nil);
     }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TEST_FAILURE" object:self];
    
    STAssertTrue(hitCompleted, nil);
}

-(void)test_flatten_signal_of_signals_and_hits_next_complete_on_notification{
    RACSubject *errorNotification = [RACSubject subject];
    
    RACSignal *completeNotification = [[[NSNotificationCenter defaultCenter] rac_addObserverForName:@"TEST_SUCCESS" object:nil] take:1];
    
    RACSignal *signal = [RACSignal
                                   createSignal:^RACDisposable *(id<RACSubscriber> subscriber){
                                       RACDisposable *successDisposer = [completeNotification
                                                                         subscribeNext:^(NSNotification *notification){
                                                                             [subscriber sendNext:notification];
                                                                         }
                                                                         completed:^{
                                                                             [subscriber sendCompleted];
                                                                         }];
                                       
                                       RACDisposable *failureDisposer = [errorNotification
                                                                         subscribeError:^(NSError *err){
                                                                             [subscriber sendError:err];
                                                                         }];
                                       
                                       return [RACDisposable disposableWithBlock:^{
                                           [successDisposer dispose];
                                           [failureDisposer dispose];
                                       }];
                                   }];
    
    
    
    __block BOOL hitCompleted = NO;
    __block BOOL hitNext = NO;
    [signal
     subscribeNext:^(id val){
         hitNext = YES;
     }
     error:^(NSError *err){
         STFail(nil);
     }
     completed:^{
         hitCompleted = YES;
     }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TEST_SUCCESS" object:self];
    
    STAssertTrue(hitCompleted, nil);
    STAssertTrue(hitNext, nil);
}

-(void)test_willDeallocSignal_works_as_expected_when_applied_strong_instance_and_doesnt_impact_weak_reference{
    id val = [@{} mutableCopy];
    
    RACTestObject *test_object = [RACTestObject new];
    
    test_object.property = val;
    
    __block BOOL hitNext = NO;
    [[val rac_willDeallocSignal] subscribeCompleted:^{
        hitNext = YES;
    }];
    
    val = nil;
    STAssertNil(val, nil);
    STAssertNil(test_object.property, nil);
    STAssertTrue(hitNext, nil);
}

-(void)test_willDeallocSignal_works_as_expected_when_applied_weak_property_and_doesnt_impact_weak_reference{
    id val = [@{} mutableCopy];
    
    RACTestObject *test_object = [RACTestObject new];
    
    test_object.property = val;
    
    __block BOOL hitNext = NO;
    @autoreleasepool {
        [[test_object.property rac_willDeallocSignal] subscribeCompleted:^{
            hitNext = YES;
        }];
    }
    val = nil;
    STAssertNil(val, nil);
    STAssertNil(test_object.property, nil);
    STAssertTrue(hitNext, nil);
}


-(void)test_willDeallocSignal_applied_to_strong_reference_works_as_expected_with_local_weak_reference{
    id val = [@{} mutableCopy];
    id __weak weak_val = val;
    
    __block BOOL hitNext = NO;
    [[val rac_willDeallocSignal] subscribeCompleted:^{
        hitNext = YES;
    }];
    
    val = nil;
    STAssertNil(val, nil);
    STAssertNil(weak_val, nil);
    STAssertTrue(hitNext, nil);
}

-(void)test_willDeallocSignal_applied_to_weak_reference_prevents_weak_reference_from_being_released{
    id val = [@{} mutableCopy];
    id __weak weak_val = val;
    
    __block BOOL hitNext = NO;
    
    @autoreleasepool {
        [[weak_val rac_willDeallocSignal] subscribeCompleted:^{
            hitNext = YES;
        }];
    }
    
    val = nil;
    STAssertNil(val, nil);
    
    STAssertNil(weak_val, nil);
    STAssertTrue(hitNext, nil);
}

-(void)test_if_else_signal{
    RACSignal *reachabilitySignal = [[[NSNotificationCenter defaultCenter] rac_addObserverForName:@"test_reach" object:nil]
                                     map:^NSNumber *(NSNotification *notification){
                                         return @([notification.object boolValue]);
                                     }];
    
    RACSignal *test_signal = [RACSignal if:reachabilitySignal
                               then:[RACSignal return:@"sig_true"]
                               else:[RACSignal return:@"sig_false"]];

    __block NSMutableSet *result_set = [NSMutableSet setWithCapacity:2];
    [test_signal subscribeNext:^(NSString *val){
        [result_set addObject:val];
    }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(YES)];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(NO)];
    
    NSSet *expected_set = [NSSet setWithObjects:@"sig_true", @"sig_false", nil];
    STAssertEqualObjects(result_set, expected_set, nil);
}

-(void)test_notification_signal_with_concatenate_start{
    
    RACSignal *initialValueSignal = [RACSignal return:@(YES)];
    RACSignal *reachabilitySignal = [[[NSNotificationCenter defaultCenter] rac_addObserverForName:@"test_reach" object:nil]
                                     map:^NSNumber *(NSNotification *notification){
                                         return @([notification.object boolValue]);
                                     }];
    
    RACSignal *test_signal = [initialValueSignal concat:reachabilitySignal];
    
    RACSignal *collector = [[[RACSignal if:test_signal then:[RACSignal return:@"sig_true"] else:[RACSignal return:@"sig_false"]] take:5] collect];
    
    __block NSArray *results;
    [collector subscribeNext:^(NSArray *collection){
        results = collection;
    }];
    
    NSArray *expected = @[@"sig_true", @"sig_false", @"sig_false", @"sig_true", @"sig_false"];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(NO)];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(NO)];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(YES)];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"test_reach" object:@(NO)];
    
    STAssertEqualObjects(expected, results, nil);
}

@end
