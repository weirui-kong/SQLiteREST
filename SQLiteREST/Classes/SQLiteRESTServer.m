//
//  SQLiteRESTServer.m
//  SQLiteREST
//
//  Created by Weirui Kong on 11/28/2025.
//  Copyright (c) 2025 Weirui Kong. All rights reserved.
//

#import "SQLiteRESTServer.h"
#import "SQLiteRESTWorker.h"
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataRequest.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>

@interface SQLiteRESTServer ()

@property (nonatomic, strong) GCDWebServer *webServer;
@property (nonatomic, copy) NSString *databasePath;
@property (nonatomic, strong) SQLiteRESTWorker *worker;

- (void)log:(NSString *)message;

@end

@implementation SQLiteRESTServer

+ (instancetype)sharedInstance {
    static SQLiteRESTServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SQLiteRESTServer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _webServer = [[GCDWebServer alloc] init];
        [self setupHandlers];
    }
    return self;
}

- (void)setupHandlers {
    __weak typeof(self) weakSelf = self;
    
    // GET / - Serve HTML UI
    [_webServer addHandlerForMethod:@"GET"
                                path:@"/"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        [weakSelf logWebRequest:@"GET" path:@"/" parameters:nil];
        GCDWebServerResponse *response = [weakSelf handleIndexHTML];
        [weakSelf logWebResponse:0]; // HTML response, row count is 0
        return response;
    }];
    
    // GET /api/tables - List all tables and metadata
    [_webServer addHandlerForMethod:@"GET"
                                path:@"/api/tables"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        return [weakSelf handleListTables];
    }];
    
    // POST /api/table/{tableName}/rows - List rows with optional filter
    [_webServer addHandlerForMethod:@"POST"
                           pathRegex:@"^/api/table/([^/]+)/rows$"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSString *tableName = [weakSelf extractTableNameFromPath:request.path];
        return [weakSelf handleListRows:tableName request:(GCDWebServerDataRequest *)request];
    }];
    
    // POST /api/table/{tableName}/insert - Insert a row
    [_webServer addHandlerForMethod:@"POST"
                           pathRegex:@"^/api/table/([^/]+)/insert$"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSString *tableName = [weakSelf extractTableNameFromPath:request.path];
        return [weakSelf handleInsertRow:tableName request:(GCDWebServerDataRequest *)request];
    }];
    
    // POST /api/table/{tableName}/update - Update a row
    [_webServer addHandlerForMethod:@"POST"
                           pathRegex:@"^/api/table/([^/]+)/update$"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSString *tableName = [weakSelf extractTableNameFromPath:request.path];
        return [weakSelf handleUpdateRow:tableName request:(GCDWebServerDataRequest *)request];
    }];
    
    // POST /api/table/{tableName}/delete - Delete a row
    [_webServer addHandlerForMethod:@"POST"
                           pathRegex:@"^/api/table/([^/]+)/delete$"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSString *tableName = [weakSelf extractTableNameFromPath:request.path];
        return [weakSelf handleDeleteRow:tableName request:(GCDWebServerDataRequest *)request];
    }];
    
    // POST /api/sql - Execute raw SQL
    [_webServer addHandlerForMethod:@"POST"
                                path:@"/api/sql"
                        requestClass:[GCDWebServerDataRequest class]
                        processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        return [weakSelf handleExecuteSQL:(GCDWebServerDataRequest *)request];
    }];
}

- (NSString *)extractTableNameFromPath:(NSString *)path {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^/api/table/([^/]+)/" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (match && match.numberOfRanges > 1) {
        NSRange range = [match rangeAtIndex:1];
        return [path substringWithRange:range];
    }
    return nil;
}

#pragma mark - Request Handlers

- (GCDWebServerResponse *)handleIndexHTML {
    NSBundle *classBundle = [NSBundle bundleForClass:[self class]];
    NSString *htmlPath = nil;
    
    // Try to find in resource bundle first (for CocoaPods resource_bundles)
    NSString *resourceBundlePath = [classBundle pathForResource:@"SQLiteREST" ofType:@"bundle"];
    if (resourceBundlePath) {
        NSBundle *resourceBundle = [NSBundle bundleWithPath:resourceBundlePath];
        htmlPath = [resourceBundle pathForResource:@"index" ofType:@"html"];
    }
    
    // Fallback to class bundle directly
    if (!htmlPath) {
        htmlPath = [classBundle pathForResource:@"index" ofType:@"html"];
    }
    
    // Fallback to main bundle
    if (!htmlPath) {
        htmlPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    }
    
    if (htmlPath) {
        NSString *html = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
        if (html) {
            return [GCDWebServerDataResponse responseWithHTML:html];
        }
    }
    
    // Fallback error response if file not found
    return [GCDWebServerDataResponse responseWithHTML:@"<html><body><h1>Error</h1><p>index.html not found in bundle.</p></body></html>"];
}

- (GCDWebServerResponse *)handleListTables {
    // Web log: record request
    [self logWebRequest:@"GET" path:@"/api/tables" parameters:nil];
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0]; // Error response, row count is 0
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker listTablesWithCompletion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: record response row count
            NSArray *tables = result;
            NSInteger rowCount = [tables isKindOfClass:[NSArray class]] ? [tables count] : 0;
            [self logWebResponse:rowCount];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0]; // Error response, row count is 0
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

- (GCDWebServerResponse *)handleListRows:(NSString *)tableName request:(GCDWebServerDataRequest *)request {
    NSDictionary *jsonObject = request.jsonObject;
    NSString *filter = nil;
    if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
        filter = jsonObject[@"filter"];
    }
    
    // Web log: record request
    NSString *path = [NSString stringWithFormat:@"/api/table/%@/rows", tableName];
    NSDictionary *params = filter ? @{@"filter": filter} : nil;
    [self logWebRequest:@"POST" path:path parameters:params];
    
    if (!tableName) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Invalid table name",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker listRowsFromTable:tableName filter:filter completion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: record response row count
            NSDictionary *data = result;
            NSArray *rows = data[@"rows"];
            NSInteger rowCount = [rows isKindOfClass:[NSArray class]] ? [rows count] : 0;
            [self logWebResponse:rowCount];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

- (GCDWebServerResponse *)handleInsertRow:(NSString *)tableName request:(GCDWebServerDataRequest *)request {
    NSDictionary *jsonObject = request.jsonObject;
    NSDictionary *row = nil;
    if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
        row = jsonObject[@"row"];
    }
    
    // Web log: record request
    NSString *path = [NSString stringWithFormat:@"/api/table/%@/insert", tableName];
    NSDictionary *params = row ? @{@"row": row} : nil;
    [self logWebRequest:@"POST" path:path parameters:params];
    
    if (!tableName) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Invalid table name",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!row || ![row isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Missing or invalid 'row' parameter",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker insertRow:row intoTable:tableName completion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: insert operation returns 1 row
            [self logWebResponse:1];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

- (GCDWebServerResponse *)handleUpdateRow:(NSString *)tableName request:(GCDWebServerDataRequest *)request {
    NSDictionary *jsonObject = request.jsonObject;
    NSDictionary *primaryKey = nil;
    NSDictionary *newValues = nil;
    if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
        primaryKey = jsonObject[@"primaryKey"];
        newValues = jsonObject[@"newValues"];
    }
    
    // Web log: record request
    NSString *path = [NSString stringWithFormat:@"/api/table/%@/update", tableName];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (primaryKey) params[@"primaryKey"] = primaryKey;
    if (newValues) params[@"newValues"] = newValues;
    [self logWebRequest:@"POST" path:path parameters:params.count > 0 ? params : nil];
    
    if (!tableName) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Invalid table name",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!primaryKey || ![primaryKey isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Missing or invalid 'primaryKey' parameter",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!newValues || ![newValues isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Missing or invalid 'newValues' parameter",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker updateRowInTable:tableName primaryKey:primaryKey newValues:newValues completion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: update operation returns affected rows
            NSDictionary *data = result;
            NSNumber *rowsAffected = data[@"rowsAffected"];
            NSInteger rowCount = rowsAffected ? [rowsAffected integerValue] : 0;
            [self logWebResponse:rowCount];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

- (GCDWebServerResponse *)handleDeleteRow:(NSString *)tableName request:(GCDWebServerDataRequest *)request {
    NSDictionary *jsonObject = request.jsonObject;
    NSDictionary *primaryKey = nil;
    if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
        primaryKey = jsonObject[@"primaryKey"];
    }
    
    // Web log: record request
    NSString *path = [NSString stringWithFormat:@"/api/table/%@/delete", tableName];
    NSDictionary *params = primaryKey ? @{@"primaryKey": primaryKey} : nil;
    [self logWebRequest:@"POST" path:path parameters:params];
    
    if (!tableName) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Invalid table name",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!primaryKey || ![primaryKey isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Missing or invalid 'primaryKey' parameter",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker deleteRowFromTable:tableName primaryKey:primaryKey completion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: delete operation returns affected rows
            NSDictionary *data = result;
            NSNumber *rowsAffected = data[@"rowsAffected"];
            NSInteger rowCount = rowsAffected ? [rowsAffected integerValue] : 0;
            [self logWebResponse:rowCount];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

- (GCDWebServerResponse *)handleExecuteSQL:(GCDWebServerDataRequest *)request {
    NSDictionary *jsonObject = request.jsonObject;
    NSString *sql = nil;
    if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
        sql = jsonObject[@"sql"];
    }
    
    // Web log: record request
    NSDictionary *params = sql ? @{@"sql": sql} : nil;
    [self logWebRequest:@"POST" path:@"/api/sql" parameters:params];
    
    if (!self.worker) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Database not initialized",
            @"code": @"DATABASE_ERROR"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!jsonObject || ![jsonObject isKindOfClass:[NSDictionary class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Invalid JSON request body",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    if (!sql || ![sql isKindOfClass:[NSString class]]) {
        NSDictionary *errorResponse = @{
            @"ok": @NO,
            @"error": @"Missing or invalid 'sql' parameter",
            @"code": @"INVALID_REQUEST"
        };
        [self logWebResponse:0];
        return [GCDWebServerDataResponse responseWithJSONObject:errorResponse];
    }
    
    __block GCDWebServerResponse *response = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.worker executeSQL:sql completion:^(BOOL success, id result, NSString *errorMessage, NSString *errorCode) {
        if (success) {
            NSDictionary *responseDict = @{
                @"ok": @YES,
                @"data": result
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            // Web log: record response row count
            NSDictionary *data = result;
            NSInteger rowCount = 0;
            if (data[@"rows"]) {
                NSArray *rows = data[@"rows"];
                rowCount = [rows isKindOfClass:[NSArray class]] ? [rows count] : 0;
            } else if (data[@"rowsAffected"]) {
                NSNumber *rowsAffected = data[@"rowsAffected"];
                rowCount = rowsAffected ? [rowsAffected integerValue] : 0;
            }
            [self logWebResponse:rowCount];
        } else {
            NSDictionary *responseDict = @{
                @"ok": @NO,
                @"error": errorMessage ?: @"Unknown error",
                @"code": errorCode ?: @"UNKNOWN_ERROR"
            };
            response = [GCDWebServerDataResponse responseWithJSONObject:responseDict];
            [self logWebResponse:0];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return response;
}

#pragma mark - Logging

- (void)setLogHandler:(void (^)(NSString *))logHandler {
    _logHandler = [logHandler copy];
    // Sync log handler to worker if it exists
    if (self.worker) {
        self.worker.logHandler = logHandler;
    }
}

- (void)log:(NSString *)message {
    if (self.logHandler) {
        self.logHandler(message);
    } else {
        NSLog(@"%@", message);
    }
}

- (void)logWebRequest:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters {
    NSMutableString *logMessage = [NSMutableString stringWithFormat:@"[Web] %@ %@", method, path];
    if (parameters && parameters.count > 0) {
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:NSJSONWritingPrettyPrinted error:&error];
        if (jsonData && !error) {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [logMessage appendFormat:@"\nParameters: %@", jsonString];
        }
    }
    [self log:logMessage];
}

- (void)logWebResponse:(NSInteger)rowCount {
    NSString *logMessage = [NSString stringWithFormat:@"[Web] Response rows: %ld", (long)rowCount];
    [self log:logMessage];
}

#pragma mark - Public Methods

- (void)startServerOnPort:(NSUInteger)port withPath:(NSString *)path {
    // 如果服务器已经在运行，先停止它
    if ([_webServer isRunning]) {
        [self log:@"Server is already running, stopping it first"];
        [_webServer stop];
    }
    
    self.databasePath = path;
    self.worker = [[SQLiteRESTWorker alloc] initWithDatabasePath:path];
    self.worker.logHandler = self.logHandler;
    
    NSDictionary *options = @{
        GCDWebServerOption_Port: @(port),
        GCDWebServerOption_BindToLocalhost: @NO
    };
    
    NSError *error = nil;
    BOOL started = [_webServer startWithOptions:options error:&error];
    if (!started) {
        [self log:[NSString stringWithFormat:@"Failed to start server: %@", error.localizedDescription]];
    } else {
        [self log:[NSString stringWithFormat:@"SQLiteREST server started on port %lu at %@", (unsigned long)port, _webServer.serverURL]];
    }
}

- (void)stop {
    if (![_webServer isRunning]) {
        [self log:@"SQLiteREST server is not running"];
        return;
    }
    [_webServer stop];
    [self log:@"SQLiteREST server stopped"];
}

@end

