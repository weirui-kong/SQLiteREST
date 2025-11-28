//
//  SQLiteRESTWorker.m
//  SQLiteREST
//
//  Created by Weirui Kong on 11/28/2025.
//  Copyright (c) 2025 Weirui Kong. All rights reserved.
//

#import "SQLiteRESTWorker.h"
#import <sqlite3.h>

@interface SQLiteRESTWorker ()

@property (nonatomic, copy) NSString *databasePath;
@property (nonatomic, strong) dispatch_queue_t databaseQueue;

@end

@implementation SQLiteRESTWorker

- (instancetype)initWithDatabasePath:(NSString *)databasePath {
    self = [super init];
    if (self) {
        _databasePath = [databasePath copy];
        _databaseQueue = dispatch_queue_create("com.sqliterest.database", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Database Connection

- (void)log:(NSString *)message {
    if (self.logHandler) {
        self.logHandler(message);
    } else {
        NSLog(@"%@", message);
    }
}

- (void)logDBSQL:(NSString *)sql {
    NSString *logMessage = [NSString stringWithFormat:@"[DB] SQL: %@", sql];
    [self log:logMessage];
}

- (void)logDBResult:(NSInteger)rowCount {
    NSString *logMessage = [NSString stringWithFormat:@"[DB] Result rows: %ld", (long)rowCount];
    [self log:logMessage];
}

- (sqlite3 *)openDatabase {
    sqlite3 *db = NULL;
    const char *path = [self.databasePath UTF8String];
    int result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
    if (result != SQLITE_OK) {
        NSString *errorMsg = [NSString stringWithFormat:@"Failed to open database: %s", sqlite3_errmsg(db)];
        [self log:errorMsg];
        if (db) {
            sqlite3_close(db);
        }
        return NULL;
    }
    return db;
}

- (void)closeDatabase:(sqlite3 *)db {
    if (db) {
        sqlite3_close(db);
    }
}

#pragma mark - List Tables

- (void)listTablesWithCompletion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        NSMutableArray *tables = [NSMutableArray array];
        NSString *sqlString = @"SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name";
        const char *sql = [sqlString UTF8String];
        
        // DB log: record SQL
        [self logDBSQL:sqlString];
        
        sqlite3_stmt *stmt = NULL;
        int result = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        
        if (result != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *name = (const char *)sqlite3_column_text(stmt, 0);
            const char *type = (const char *)sqlite3_column_text(stmt, 1);
            
            if (name) {
                NSString *tableName = [NSString stringWithUTF8String:name];
                NSString *tableType = type ? [NSString stringWithUTF8String:type] : @"table";
                
                NSMutableDictionary *tableInfo = [NSMutableDictionary dictionary];
                tableInfo[@"name"] = tableName;
                tableInfo[@"type"] = tableType;
                
                if ([tableType isEqualToString:@"table"]) {
                    [self fillTableMetadata:tableInfo forTable:tableName inDatabase:db];
                }
                
                [tables addObject:tableInfo];
            }
        }
        
        sqlite3_finalize(stmt);
        [self closeDatabase:db];
        
        // DB log: record result row count
        [self logDBResult:(NSInteger)tables.count];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, tables, nil, nil);
        });
    });
}

- (void)fillTableMetadata:(NSMutableDictionary *)tableInfo forTable:(NSString *)tableName inDatabase:(sqlite3 *)db {
    // Get table info
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", [self escapeTableName:tableName]];
    const char *sqlStr = [sql UTF8String];
    
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL) != SQLITE_OK) {
        return;
    }
    
    NSMutableArray *columns = [NSMutableArray array];
    NSMutableArray *primaryKeys = [NSMutableArray array];
    BOOL hasRowId = YES;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *name = (const char *)sqlite3_column_text(stmt, 1);
        const char *type = (const char *)sqlite3_column_text(stmt, 2);
        int notnull = sqlite3_column_int(stmt, 3);
        const char *defaultValue = (const char *)sqlite3_column_text(stmt, 4);
        int pk = sqlite3_column_int(stmt, 5);
        
        if (name) {
            NSMutableDictionary *column = [NSMutableDictionary dictionary];
            column[@"name"] = [NSString stringWithUTF8String:name];
            column[@"type"] = type ? [NSString stringWithUTF8String:type] : @"TEXT";
            column[@"notnull"] = @(notnull);
            column[@"pk"] = @(pk);
            column[@"default"] = defaultValue ? [NSString stringWithUTF8String:defaultValue] : [NSNull null];
            
            [columns addObject:column];
            
            if (pk > 0) {
                [primaryKeys addObject:column[@"name"]];
            }
        }
    }
    
    sqlite3_finalize(stmt);
    
    // Check if table uses ROWID
    NSString *createSql = [NSString stringWithFormat:@"SELECT sql FROM sqlite_master WHERE type='table' AND name='%@'", [self escapeTableName:tableName]];
    sqlite3_stmt *createStmt = NULL;
    if (sqlite3_prepare_v2(db, [createSql UTF8String], -1, &createStmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(createStmt) == SQLITE_ROW) {
            const char *sql = (const char *)sqlite3_column_text(createStmt, 0);
            if (sql) {
                NSString *createStatement = [NSString stringWithUTF8String:sql];
                hasRowId = ![createStatement containsString:@"WITHOUT ROWID"];
            }
        }
        sqlite3_finalize(createStmt);
    }
    
    tableInfo[@"columns"] = columns;
    tableInfo[@"primaryKey"] = primaryKeys;
    tableInfo[@"hasRowId"] = @(hasRowId);
}

#pragma mark - List Rows

- (void)listRowsFromTable:(NSString *)tableName filter:(NSString *)filter completion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        NSString *escapedTableName = [self escapeTableName:tableName];
        NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT * FROM %@", escapedTableName];
        
        // Note: filter is directly concatenated into SQL as per API specification.
        // This allows flexible WHERE clauses but requires the caller to ensure SQL safety.
        if (filter && filter.length > 0) {
            [sql appendFormat:@" WHERE %@", filter];
        }
        
        // DB log: record SQL
        [self logDBSQL:sql];
        
        sqlite3_stmt *stmt = NULL;
        const char *sqlStr = [sql UTF8String];
        int sqlResult = sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL);
        
        if (sqlResult != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        NSMutableArray *columns = [NSMutableArray array];
        int columnCount = sqlite3_column_count(stmt);
        for (int i = 0; i < columnCount; i++) {
            const char *columnName = sqlite3_column_name(stmt, i);
            if (columnName) {
                [columns addObject:[NSString stringWithUTF8String:columnName]];
            }
        }
        
        NSMutableArray *rows = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableArray *row = [NSMutableArray array];
            for (int i = 0; i < columnCount; i++) {
                id value = [self valueFromStatement:stmt atIndex:i];
                [row addObject:value];
            }
            [rows addObject:row];
        }
        
        sqlite3_finalize(stmt);
        [self closeDatabase:db];
        
        // DB log: record result row count
        [self logDBResult:(NSInteger)rows.count];
        
        NSDictionary *result = @{
            @"columns": columns,
            @"rows": rows
        };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, result, nil, nil);
        });
    });
}

#pragma mark - Insert Row

- (void)insertRow:(NSDictionary *)row intoTable:(NSString *)tableName completion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        NSArray *keys = [row allKeys];
        if (keys.count == 0) {
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Empty row data", @"INVALID_REQUEST");
            });
            return;
        }
        
        NSString *escapedTableName = [self escapeTableName:tableName];
        NSMutableString *sql = [NSMutableString stringWithFormat:@"INSERT INTO %@ (", escapedTableName];
        NSMutableString *values = [NSMutableString stringWithString:@"VALUES ("];
        
        for (NSUInteger i = 0; i < keys.count; i++) {
            NSString *key = keys[i];
            [sql appendString:[self escapeIdentifier:key]];
            [values appendString:@"?"];
            
            if (i < keys.count - 1) {
                [sql appendString:@", "];
                [values appendString:@", "];
            }
        }
        
        [sql appendString:@") "];
        [values appendString:@")"];
        [sql appendString:values];
        
        // DB log: record SQL
        [self logDBSQL:sql];
        
        sqlite3_stmt *stmt = NULL;
        const char *sqlStr = [sql UTF8String];
        int sqlResult = sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL);
        
        if (sqlResult != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        // Bind values
        for (NSUInteger i = 0; i < keys.count; i++) {
            NSString *key = keys[i];
            id value = row[key];
            [self bindValue:value toStatement:stmt atIndex:(int)(i + 1)];
        }
        
        sqlResult = sqlite3_step(stmt);
        sqlite3_int64 lastInsertRowId = sqlite3_last_insert_rowid(db);
        sqlite3_finalize(stmt);
        
        if (sqlResult != SQLITE_DONE) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        [self closeDatabase:db];
        
        // DB log: record result row count (insert operation returns 1)
        [self logDBResult:1];
        
        NSNumber *rowId = (lastInsertRowId > 0) ? @(lastInsertRowId) : [NSNull null];
        NSDictionary *result = @{
            @"insertedRowId": rowId
        };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, result, nil, nil);
        });
    });
}

#pragma mark - Update Row

- (void)updateRowInTable:(NSString *)tableName primaryKey:(NSDictionary *)primaryKey newValues:(NSDictionary *)newValues completion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        if (primaryKey.count == 0) {
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Primary key is required", @"INVALID_REQUEST");
            });
            return;
        }
        
        if (newValues.count == 0) {
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"No values to update", @"INVALID_REQUEST");
            });
            return;
        }
        
        NSString *escapedTableName = [self escapeTableName:tableName];
        NSMutableString *sql = [NSMutableString stringWithFormat:@"UPDATE %@ SET ", escapedTableName];
        
        NSArray *valueKeys = [newValues allKeys];
        for (NSUInteger i = 0; i < valueKeys.count; i++) {
            NSString *key = valueKeys[i];
            [sql appendFormat:@"%@ = ?", [self escapeIdentifier:key]];
            if (i < valueKeys.count - 1) {
                [sql appendString:@", "];
            }
        }
        
        [sql appendString:@" WHERE "];
        NSArray *pkKeys = [primaryKey allKeys];
        for (NSUInteger i = 0; i < pkKeys.count; i++) {
            NSString *key = pkKeys[i];
            [sql appendFormat:@"%@ = ?", [self escapeIdentifier:key]];
            if (i < pkKeys.count - 1) {
                [sql appendString:@" AND "];
            }
        }
        
        // DB log: record SQL
        [self logDBSQL:sql];
        
        sqlite3_stmt *stmt = NULL;
        const char *sqlStr = [sql UTF8String];
        int sqlResult = sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL);
        
        if (sqlResult != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        // Bind new values
        int paramIndex = 1;
        for (NSString *key in valueKeys) {
            id value = newValues[key];
            [self bindValue:value toStatement:stmt atIndex:paramIndex++];
        }
        
        // Bind primary key values
        for (NSString *key in pkKeys) {
            id value = primaryKey[key];
            [self bindValue:value toStatement:stmt atIndex:paramIndex++];
        }
        
        sqlResult = sqlite3_step(stmt);
        int rowsAffected = sqlite3_changes(db);
        sqlite3_finalize(stmt);
        
        if (sqlResult != SQLITE_DONE) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        [self closeDatabase:db];
        
        // DB log: record result row count
        [self logDBResult:rowsAffected];
        
        NSDictionary *result = @{
            @"rowsAffected": @(rowsAffected)
        };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, result, nil, nil);
        });
    });
}

#pragma mark - Delete Row

- (void)deleteRowFromTable:(NSString *)tableName primaryKey:(NSDictionary *)primaryKey completion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        if (primaryKey.count == 0) {
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Primary key is required", @"INVALID_REQUEST");
            });
            return;
        }
        
        NSString *escapedTableName = [self escapeTableName:tableName];
        NSMutableString *sql = [NSMutableString stringWithFormat:@"DELETE FROM %@ WHERE ", escapedTableName];
        
        NSArray *pkKeys = [primaryKey allKeys];
        for (NSUInteger i = 0; i < pkKeys.count; i++) {
            NSString *key = pkKeys[i];
            [sql appendFormat:@"%@ = ?", [self escapeIdentifier:key]];
            if (i < pkKeys.count - 1) {
                [sql appendString:@" AND "];
            }
        }
        
        // DB log: record SQL
        [self logDBSQL:sql];
        
        sqlite3_stmt *stmt = NULL;
        const char *sqlStr = [sql UTF8String];
        int sqlResult = sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL);
        
        if (sqlResult != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        // Bind primary key values
        int paramIndex = 1;
        for (NSString *key in pkKeys) {
            id value = primaryKey[key];
            [self bindValue:value toStatement:stmt atIndex:paramIndex++];
        }
        
        sqlResult = sqlite3_step(stmt);
        int rowsAffected = sqlite3_changes(db);
        sqlite3_finalize(stmt);
        
        if (sqlResult != SQLITE_DONE) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_ERROR");
            });
            return;
        }
        
        [self closeDatabase:db];
        
        // DB log: record result row count
        [self logDBResult:rowsAffected];
        
        NSDictionary *result = @{
            @"rowsAffected": @(rowsAffected)
        };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, result, nil, nil);
        });
    });
}

#pragma mark - Execute SQL

- (void)executeSQL:(NSString *)sql completion:(SQLiteRESTWorkerCompletionBlock)completion {
    dispatch_async(self.databaseQueue, ^{
        sqlite3 *db = [self openDatabase];
        if (!db) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, @"Failed to open database", @"DATABASE_ERROR");
            });
            return;
        }
        
        // DB log: record SQL
        [self logDBSQL:sql];
        
        const char *sqlStr = [sql UTF8String];
        sqlite3_stmt *stmt = NULL;
        int sqlResult = sqlite3_prepare_v2(db, sqlStr, -1, &stmt, NULL);
        
        if (sqlResult != SQLITE_OK) {
            NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
            [self closeDatabase:db];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, errorMsg, @"SQL_EXEC_ERROR");
            });
            return;
        }
        
        // Check if it's a SELECT query (returns rows) or write operation
        BOOL isSelect = sqlite3_column_count(stmt) > 0;
        
        if (isSelect) {
            // SELECT query - return rows
            NSMutableArray *columns = [NSMutableArray array];
            int columnCount = sqlite3_column_count(stmt);
            for (int i = 0; i < columnCount; i++) {
                const char *columnName = sqlite3_column_name(stmt, i);
                if (columnName) {
                    [columns addObject:[NSString stringWithUTF8String:columnName]];
                }
            }
            
            NSMutableArray *rows = [NSMutableArray array];
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                NSMutableArray *row = [NSMutableArray array];
                for (int i = 0; i < columnCount; i++) {
                    id value = [self valueFromStatement:stmt atIndex:i];
                    [row addObject:value];
                }
                [rows addObject:row];
            }
            
            sqlite3_finalize(stmt);
            [self closeDatabase:db];
            
            // DB log: record result row count
            [self logDBResult:(NSInteger)rows.count];
            
            NSDictionary *result = @{
                @"columns": columns,
                @"rows": rows
            };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, result, nil, nil);
            });
        } else {
            // Write operation (INSERT, UPDATE, DELETE, etc.)
            sqlResult = sqlite3_step(stmt);
            int rowsAffected = sqlite3_changes(db);
            sqlite3_finalize(stmt);
            
            if (sqlResult != SQLITE_DONE) {
                NSString *errorMsg = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
                [self closeDatabase:db];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nil, errorMsg, @"SQL_EXEC_ERROR");
                });
                return;
            }
            
            [self closeDatabase:db];
            
            // DB log: record result row count
            [self logDBResult:rowsAffected];
            
            NSDictionary *result = @{
                @"rowsAffected": @(rowsAffected)
            };
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, result, nil, nil);
            });
        }
    });
}

#pragma mark - Helper Methods

- (id)valueFromStatement:(sqlite3_stmt *)stmt atIndex:(int)index {
    int type = sqlite3_column_type(stmt, index);
    
    switch (type) {
        case SQLITE_INTEGER:
            return @(sqlite3_column_int64(stmt, index));
        case SQLITE_FLOAT:
            return @(sqlite3_column_double(stmt, index));
        case SQLITE_TEXT: {
            const char *text = (const char *)sqlite3_column_text(stmt, index);
            return text ? [NSString stringWithUTF8String:text] : [NSNull null];
        }
        case SQLITE_BLOB: {
            int length = sqlite3_column_bytes(stmt, index);
            const void *blob = sqlite3_column_blob(stmt, index);
            return blob ? [NSData dataWithBytes:blob length:length] : [NSNull null];
        }
        case SQLITE_NULL:
        default:
            return [NSNull null];
    }
}

- (void)bindValue:(id)value toStatement:(sqlite3_stmt *)stmt atIndex:(int)index {
    if ([value isKindOfClass:[NSNull class]] || value == nil) {
        sqlite3_bind_null(stmt, index);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)value;
        const char *objcType = [number objCType];
        if (strcmp(objcType, @encode(int)) == 0 || strcmp(objcType, @encode(long)) == 0 || strcmp(objcType, @encode(long long)) == 0) {
            sqlite3_bind_int64(stmt, index, [number longLongValue]);
        } else if (strcmp(objcType, @encode(float)) == 0 || strcmp(objcType, @encode(double)) == 0) {
            sqlite3_bind_double(stmt, index, [number doubleValue]);
        } else {
            sqlite3_bind_int64(stmt, index, [number longLongValue]);
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)value;
        sqlite3_bind_text(stmt, index, [string UTF8String], -1, SQLITE_TRANSIENT);
    } else if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        sqlite3_bind_blob(stmt, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, index);
    }
}

- (NSString *)escapeTableName:(NSString *)name {
    // Simple escaping - wrap in double quotes
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

- (NSString *)escapeIdentifier:(NSString *)identifier {
    // Simple escaping - wrap in double quotes
    return [NSString stringWithFormat:@"\"%@\"", [identifier stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

@end

