//
//  SQLiteRESTServer.h
//  SQLiteREST
//
//  Created by Weirui Kong on 11/28/2025.
//  Copyright (c) 2025 Weirui Kong. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SQLiteRESTServer : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, copy, nullable) void(^logHandler)(NSString *message);

- (void)startServerOnPort:(NSUInteger)port withPath:(NSString *)path;

- (void)stop;

@end

NS_ASSUME_NONNULL_END

