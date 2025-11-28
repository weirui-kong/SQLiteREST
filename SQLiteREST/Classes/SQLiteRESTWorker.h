//
//  SQLiteRESTWorker.h
//  SQLiteREST
//
//  Created by Weirui Kong on 11/28/2025.
//  Copyright (c) 2025 Weirui Kong. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SQLiteRESTWorker;

typedef void(^SQLiteRESTWorkerCompletionBlock)(BOOL success, id _Nullable result, NSString * _Nullable errorMessage, NSString * _Nullable errorCode);

@interface SQLiteRESTWorker : NSObject

@property (nonatomic, copy, nullable) void(^logHandler)(NSString *message);

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

- (void)listTablesWithCompletion:(SQLiteRESTWorkerCompletionBlock)completion;
- (void)listRowsFromTable:(NSString *)tableName filter:(NSString * _Nullable)filter completion:(SQLiteRESTWorkerCompletionBlock)completion;
- (void)insertRow:(NSDictionary *)row intoTable:(NSString *)tableName completion:(SQLiteRESTWorkerCompletionBlock)completion;
- (void)updateRowInTable:(NSString *)tableName primaryKey:(NSDictionary *)primaryKey newValues:(NSDictionary *)newValues completion:(SQLiteRESTWorkerCompletionBlock)completion;
- (void)deleteRowFromTable:(NSString *)tableName primaryKey:(NSDictionary *)primaryKey completion:(SQLiteRESTWorkerCompletionBlock)completion;
- (void)executeSQL:(NSString *)sql completion:(SQLiteRESTWorkerCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END

