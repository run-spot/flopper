#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import <TargetConditionals.h>

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import "FlopperAppleShim.h"

@protocol KmpFlipperResponder <NSObject>
- (void)success:(NSDictionary*)response;
- (void)error:(NSDictionary*)response;
@end

typedef void (^KmpSonarReceiver)(NSDictionary*, id<KmpFlipperResponder>);

@protocol KmpFlipperConnection <NSObject>
- (void)send:(NSString*)method withParams:(NSDictionary*)params;
- (void)send:(NSString*)method withRawParams:(NSString*)params;
- (void)send:(NSString*)method withArrayParams:(NSArray*)params;
- (void)receive:(NSString*)method withBlock:(KmpSonarReceiver)receiver;
- (void)errorWithMessage:(NSString*)message stackTrace:(NSString*)stacktrace;
@end

@protocol KmpFlipperPlugin <NSObject>
- (NSString*)identifier;
- (void)didConnect:(id<KmpFlipperConnection>)connection;
- (void)didDisconnect;
@optional
- (BOOL)runInBackground;
@end

@interface FlopperKmpPluginBridge : NSObject <KmpFlipperPlugin>
@property(nonatomic, copy) NSString* identifierValue;
@property(nonatomic, assign) BOOL runInBackgroundValue;
@property(nonatomic, assign) void* pluginRef;
@property(nonatomic, assign) FlopperKmpDidConnectCallback connectCallback;
@property(nonatomic, assign) FlopperKmpDidDisconnectCallback disconnectCallback;
@property(nonatomic, strong) id connection;
@end

@implementation FlopperKmpPluginBridge

- (NSString*)identifier {
  return self.identifierValue;
}

- (void)didConnect:(id<KmpFlipperConnection>)connection {
  self.connection = connection;
  if (self.connectCallback != NULL) {
    self.connectCallback(self.pluginRef, (__bridge void*)connection);
  }
}

- (void)didDisconnect {
  if (self.disconnectCallback != NULL) {
    self.disconnectCallback(self.pluginRef);
  }
  self.connection = nil;
}

- (BOOL)runInBackground {
  return self.runInBackgroundValue;
}

@end

@interface FlopperKmpFallbackConnection : NSObject <KmpFlipperConnection>
@property(nonatomic, strong) NSMutableDictionary<NSString*, KmpSonarReceiver>* receivers;
@end

@protocol FlopperKmpBrowserClientMessaging <NSObject>
- (void)sendPluginMessageForApi:(NSString*)api method:(NSString*)method payload:(id)payload;
@end

@interface FlopperKmpBrowserConnection : NSObject <KmpFlipperConnection>
@property(nonatomic, weak) id<FlopperKmpBrowserClientMessaging> client;
@property(nonatomic, copy) NSString* pluginIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString*, KmpSonarReceiver>* receivers;
- (instancetype)initWithClient:(id<FlopperKmpBrowserClientMessaging>)client
              pluginIdentifier:(NSString*)pluginIdentifier;
- (void)dispatchMethod:(NSString*)method payload:(id)payload;
@end

@implementation FlopperKmpFallbackConnection

- (instancetype)init {
  if (self = [super init]) {
    _receivers = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)send:(NSString*)method withParams:(NSDictionary*)params {
  KmpSonarReceiver receiver = self.receivers[method];
  if (receiver != nil) {
    receiver(params ?: @{}, nil);
  }
}

- (void)send:(NSString*)method withRawParams:(NSString*)params {
  KmpSonarReceiver receiver = self.receivers[method];
  if (receiver != nil) {
    receiver(params == nil ? @{} : @{@"raw" : params}, nil);
  }
}

- (void)send:(NSString*)method withArrayParams:(NSArray*)params {
  KmpSonarReceiver receiver = self.receivers[method];
  if (receiver != nil) {
    receiver(@{@"items" : params ?: @[]}, nil);
  }
}

- (void)receive:(NSString*)method withBlock:(KmpSonarReceiver)receiver {
  if (method != nil && receiver != nil) {
    self.receivers[method] = [receiver copy];
  }
}

- (void)errorWithMessage:(NSString*)message stackTrace:(NSString*)stacktrace {
}

@end

@implementation FlopperKmpBrowserConnection

- (instancetype)initWithClient:(id<FlopperKmpBrowserClientMessaging>)client
              pluginIdentifier:(NSString*)pluginIdentifier {
  if (self = [super init]) {
    _client = client;
    _pluginIdentifier = [pluginIdentifier copy];
    _receivers = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)send:(NSString*)method withParams:(NSDictionary*)params {
  [self.client sendPluginMessageForApi:self.pluginIdentifier method:method payload:params ?: @{}];
}

- (void)send:(NSString*)method withRawParams:(NSString*)params {
  [self.client sendPluginMessageForApi:self.pluginIdentifier method:method payload:params ?: @""];
}

- (void)send:(NSString*)method withArrayParams:(NSArray*)params {
  [self.client sendPluginMessageForApi:self.pluginIdentifier method:method payload:params ?: @[]];
}

- (void)receive:(NSString*)method withBlock:(KmpSonarReceiver)receiver {
  if (method != nil && receiver != nil) {
    self.receivers[method] = [receiver copy];
  }
}

- (void)errorWithMessage:(NSString*)message stackTrace:(NSString*)stacktrace {
}

- (void)dispatchMethod:(NSString*)method payload:(id)payload {
  KmpSonarReceiver receiver = self.receivers[method];
  if (receiver == nil) {
    return;
  }

  if ([payload isKindOfClass:[NSDictionary class]]) {
    receiver(payload, nil);
  } else if ([payload isKindOfClass:[NSArray class]]) {
    receiver(@{@"items" : payload}, nil);
  } else if ([payload isKindOfClass:[NSString class]]) {
    receiver(@{@"raw" : payload}, nil);
  } else if (payload == nil) {
    receiver(@{}, nil);
  } else {
    receiver(@{@"value" : payload}, nil);
  }
}

@end

@interface FlopperKmpFallbackClient : NSObject
@property(nonatomic, strong) NSMutableArray<id<KmpFlipperPlugin>>* plugins;
@property(nonatomic, strong) FlopperKmpFallbackConnection* connection;
@property(nonatomic, assign, getter=isStarted) BOOL started;
@end

@interface FlopperKmpBrowserClient : NSObject <NSURLSessionWebSocketDelegate, FlopperKmpBrowserClientMessaging>
@property(nonatomic, strong) NSMutableArray<id<KmpFlipperPlugin>>* plugins;
@property(nonatomic, strong) NSMutableDictionary<NSString*, FlopperKmpBrowserConnection*>* connections;
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic, strong) NSURLSessionWebSocketTask* socketTask;
@property(nonatomic, assign, getter=isStarted) BOOL started;
@property(nonatomic, assign) BOOL desktopConnected;
@property(nonatomic, copy) NSString* transportState;
+ (instancetype)sharedClient;
- (void)addPlugin:(id<KmpFlipperPlugin>)plugin;
- (void)removePlugin:(id<KmpFlipperPlugin>)plugin;
- (id)pluginWithIdentifier:(NSString*)identifier;
- (void)start;
- (void)stop;
- (NSString*)getState;
- (NSArray<NSDictionary*>*)getStateElements;
- (BOOL)isConnected;
- (void)sendPluginMessageForApi:(NSString*)api method:(NSString*)method payload:(id)payload;
- (void)notifyPluginListChanged;
- (FlopperKmpBrowserConnection*)connectionForPlugin:(id<KmpFlipperPlugin>)plugin;
@end

@implementation FlopperKmpFallbackClient

+ (instancetype)sharedClient {
  static FlopperKmpFallbackClient* sharedClient = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedClient = [FlopperKmpFallbackClient new];
  });
  return sharedClient;
}

- (instancetype)init {
  if (self = [super init]) {
    _plugins = [NSMutableArray array];
    _connection = [FlopperKmpFallbackConnection new];
  }
  return self;
}

- (void)addPlugin:(id<KmpFlipperPlugin>)plugin {
  if (plugin == nil) {
    return;
  }
  [self.plugins addObject:plugin];
  if (self.started) {
    [plugin didConnect:self.connection];
  }
}

- (void)removePlugin:(id<KmpFlipperPlugin>)plugin {
  if (plugin == nil) {
    return;
  }
  if ([self.plugins containsObject:plugin]) {
    if (self.started) {
      [plugin didDisconnect];
    }
    [self.plugins removeObject:plugin];
  }
}

- (id)pluginWithIdentifier:(NSString*)identifier {
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    if ([[plugin identifier] isEqualToString:identifier]) {
      return plugin;
    }
  }
  return nil;
}

- (void)start {
  self.started = YES;
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    [plugin didConnect:self.connection];
  }
}

- (void)stop {
  if (!self.started) {
    return;
  }
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    [plugin didDisconnect];
  }
  self.started = NO;
}

- (NSString*)getState {
  return self.started ? @"CONNECTED" : @"DISCONNECTED";
}

- (NSArray<NSDictionary*>*)getStateElements {
  return @[
    @{@"name" : @"transport", @"state" : self.started ? @"fallback-connected" : @"fallback-idle"},
    @{@"name" : @"plugins", @"state" : [NSString stringWithFormat:@"%lu", (unsigned long)self.plugins.count]},
  ];
}

- (BOOL)isConnected {
  return self.started;
}

@end

static NSString* flopper_bundle_name(void) {
  NSBundle* bundle = [NSBundle mainBundle];
  NSString* appName = [bundle objectForInfoDictionaryKey:(NSString*)kCFBundleNameKey];
  if (appName.length == 0) {
    appName = [bundle bundleIdentifier];
  }
  return appName ?: @"FlopperKmp";
}

static NSString* flopper_device_name(void) {
#if TARGET_OS_OSX
  return [[NSHost currentHost] localizedName] ?: @"Mac";
#else
  UIDevice* device = [UIDevice currentDevice];
#if TARGET_OS_SIMULATOR
  return [NSString stringWithFormat:@"%@ Simulator", device.model ?: @"iOS"];
#else
  return device.name ?: device.model ?: @"iOS";
#endif
#endif
}

static NSString* flopper_device_identifier(void) {
  static NSString* const key = @"com.runspot.flopper.kmp.browserDeviceId";
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  NSString* existing = [defaults stringForKey:key];
  if (existing.length > 0) {
    return existing;
  }

  NSString* generated = [NSUUID UUID].UUIDString;
  [defaults setObject:generated forKey:key];
  return generated;
}

static NSUInteger flopper_browser_port(void) {
  NSString* value = NSProcessInfo.processInfo.environment[@"FLOPPER_BROWSER_PORT"];
  NSInteger port = value.integerValue;
  return port > 0 ? (NSUInteger)port : 8333;
}

static NSUInteger flopper_ui_port(void) {
  NSString* value = NSProcessInfo.processInfo.environment[@"FLOPPER_UI_PORT"];
  NSInteger port = value.integerValue;
  return port > 0 ? (NSUInteger)port : 52342;
}

static NSString* flopper_browser_host(void) {
  NSString* host = NSProcessInfo.processInfo.environment[@"FLOPPER_BROWSER_HOST"];
  return host.length > 0 ? host : @"localhost";
}

static id flopper_json_safe_payload(id payload) {
  if (payload == nil) {
    return [NSNull null];
  }
  if ([NSJSONSerialization isValidJSONObject:@{@"payload" : payload}]) {
    return payload;
  }
  if ([payload isKindOfClass:[NSString class]] ||
      [payload isKindOfClass:[NSNumber class]] ||
      [payload isKindOfClass:[NSNull class]]) {
    return payload;
  }
  return [payload description] ?: [NSNull null];
}

@implementation FlopperKmpBrowserClient

@synthesize plugins = _plugins;
@synthesize connections = _connections;
@synthesize session = _session;
@synthesize socketTask = _socketTask;
@synthesize started = _started;
@synthesize desktopConnected = _desktopConnected;
@synthesize transportState = _transportState;

+ (instancetype)sharedClient {
  static FlopperKmpBrowserClient* sharedClient = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedClient = [FlopperKmpBrowserClient new];
  });
  return sharedClient;
}

- (instancetype)init {
  if (self = [super init]) {
    _plugins = [NSMutableArray array];
    _connections = [NSMutableDictionary dictionary];
    _transportState = @"fallback-idle";
  }
  return self;
}

- (void)addPlugin:(id<KmpFlipperPlugin>)plugin {
  if (plugin == nil) {
    return;
  }
  [self.plugins addObject:plugin];
  if (self.started) {
    [plugin didConnect:[self connectionForPlugin:plugin]];
    [self notifyPluginListChanged];
  }
}

- (void)removePlugin:(id<KmpFlipperPlugin>)plugin {
  if (plugin == nil) {
    return;
  }
  if ([self.plugins containsObject:plugin]) {
    if (self.started) {
      [plugin didDisconnect];
    }
    [self.plugins removeObject:plugin];
    [self.connections removeObjectForKey:[plugin identifier]];
    [self notifyPluginListChanged];
  }
}

- (id)pluginWithIdentifier:(NSString*)identifier {
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    if ([[plugin identifier] isEqualToString:identifier]) {
      return plugin;
    }
  }
  return nil;
}

- (FlopperKmpBrowserConnection*)connectionForPlugin:(id<KmpFlipperPlugin>)plugin {
  NSString* identifier = [plugin identifier];
  FlopperKmpBrowserConnection* connection = self.connections[identifier];
  if (connection == nil) {
    connection = [[FlopperKmpBrowserConnection alloc] initWithClient:self pluginIdentifier:identifier];
    self.connections[identifier] = connection;
  }
  return connection;
}

- (void)start {
  self.started = YES;
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    [plugin didConnect:[self connectionForPlugin:plugin]];
  }
  [self connectToDesktop];
}

- (void)stop {
  if (!self.started) {
    return;
  }
  self.started = NO;
  self.desktopConnected = NO;
  self.transportState = @"fallback-idle";
  [self.socketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  self.socketTask = nil;
  [self.session invalidateAndCancel];
  self.session = nil;
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    [plugin didDisconnect];
  }
}

- (NSString*)getState {
  return self.started ? @"CONNECTED" : @"DISCONNECTED";
}

- (NSArray<NSDictionary*>*)getStateElements {
  NSUInteger backgroundCount = 0;
  for (id<KmpFlipperPlugin> plugin in self.plugins) {
    if ([plugin respondsToSelector:@selector(runInBackground)] && [plugin runInBackground]) {
      backgroundCount += 1;
    }
  }

  return @[
    @{@"name" : @"transport", @"state" : self.transportState ?: @"fallback-idle"},
    @{@"name" : @"plugins", @"state" : [NSString stringWithFormat:@"%lu", (unsigned long)self.plugins.count]},
    @{@"name" : @"background", @"state" : [NSString stringWithFormat:@"%lu", (unsigned long)backgroundCount]},
  ];
}

- (BOOL)isConnected {
  return self.started;
}

- (void)connectToDesktop {
  NSString* urlString = [NSString stringWithFormat:@"ws://%@:%lu?device_id=%@&device=%@&app=%@&os=iOS&sdk_version=4",
                                                   flopper_browser_host(),
                                                   (unsigned long)flopper_browser_port(),
                                                   flopper_device_identifier(),
                                                   [flopper_device_name() stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                                                   [flopper_bundle_name() stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
  NSURL* url = [NSURL URLWithString:urlString];
  if (url == nil) {
    self.transportState = @"fallback-connected";
    return;
  }

  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
  NSString* origin = [NSString stringWithFormat:@"http://localhost:%lu", (unsigned long)flopper_ui_port()];
  [request setValue:origin forHTTPHeaderField:@"Origin"];

  NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue mainQueue]];
  self.socketTask = [self.session webSocketTaskWithRequest:request];
  self.transportState = @"browser-connecting";
  [self.socketTask resume];
  [self receiveNextMessage];
}

- (void)receiveNextMessage {
  if (self.socketTask == nil) {
    return;
  }

  __weak typeof(self) weakSelf = self;
  [self.socketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage* message, NSError* error) {
    __strong typeof(self) strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.started) {
      return;
    }
    if (error != nil) {
      strongSelf.desktopConnected = NO;
      if (strongSelf.transportState.length == 0 || [strongSelf.transportState hasPrefix:@"browser"]) {
        strongSelf.transportState = @"fallback-connected";
      }
      return;
    }

    NSString* text = message.string ?: [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
    [strongSelf handleDesktopMessage:text];
    [strongSelf receiveNextMessage];
  }];
}

- (void)handleDesktopMessage:(NSString*)text {
  if (text.length == 0) {
    return;
  }

  NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* json = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![json isKindOfClass:[NSDictionary class]]) {
    return;
  }

  NSString* method = json[@"method"];
  NSNumber* requestId = json[@"id"];
  if (requestId != nil && [method isEqualToString:@"getPlugins"]) {
    NSArray<NSString*>* plugins = [self.plugins valueForKey:@"identifier"];
    [self sendJSONObject:@{@"id" : requestId, @"success" : @{@"plugins" : plugins ?: @[]}}];
    return;
  }

  if (requestId != nil && [method isEqualToString:@"getBackgroundPlugins"]) {
    NSMutableArray<NSString*>* backgroundPlugins = [NSMutableArray array];
    for (id<KmpFlipperPlugin> plugin in self.plugins) {
      if ([plugin respondsToSelector:@selector(runInBackground)] && [plugin runInBackground]) {
        [backgroundPlugins addObject:[plugin identifier]];
      }
    }
    [self sendJSONObject:@{@"id" : requestId, @"success" : @{@"plugins" : backgroundPlugins}}];
    return;
  }

  if ([method isEqualToString:@"execute"]) {
    NSDictionary* params = json[@"params"];
    NSString* api = params[@"api"];
    NSString* pluginMethod = params[@"method"];
    id payload = params[@"params"];
    FlopperKmpBrowserConnection* connection = api == nil ? nil : self.connections[api];
    [connection dispatchMethod:pluginMethod payload:payload];
  }
}

- (void)sendJSONObject:(NSDictionary*)json {
  if (!self.desktopConnected || self.socketTask == nil || json == nil) {
    return;
  }

  NSData* data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  if (data == nil) {
    return;
  }

  NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (text == nil) {
    return;
  }

  [self.socketTask sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:text]
             completionHandler:^(NSError* error) {
             }];
}

- (void)sendPluginMessageForApi:(NSString*)api method:(NSString*)method payload:(id)payload {
  NSDictionary* json = @{
    @"method" : @"execute",
    @"params" : @{
      @"api" : api ?: @"unknown-plugin",
      @"method" : method ?: @"unknown-method",
      @"params" : flopper_json_safe_payload(payload),
    },
  };
  [self sendJSONObject:json];
}

- (void)notifyPluginListChanged {
  if (!self.desktopConnected) {
    return;
  }
  [self sendJSONObject:@{@"method" : @"refreshPlugins"}];
}

- (void)URLSession:(NSURLSession*)session
      webSocketTask:(NSURLSessionWebSocketTask*)webSocketTask
  didOpenWithProtocol:(NSString*)protocol {
  self.desktopConnected = YES;
  self.transportState = @"browser-connected";
}

- (void)URLSession:(NSURLSession*)session
      webSocketTask:(NSURLSessionWebSocketTask*)webSocketTask
didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
            reason:(NSData*)reason {
  self.desktopConnected = NO;
  if (self.started) {
    self.transportState = @"fallback-connected";
  }
}

@end

static Class flopper_client_class(void) {
  Class runtimeClass = NSClassFromString(@"FlipperClient");
  return runtimeClass ?: [FlopperKmpBrowserClient class];
}

static id flopper_invoke0(id target, SEL selector) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  return [target performSelector:selector];
#pragma clang diagnostic pop
}

static void flopper_invoke1(id target, SEL selector, id arg) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [target performSelector:selector withObject:arg];
#pragma clang diagnostic pop
}

static NSString* flopper_payload_string(const char* payload) {
  return payload == NULL ? nil : [NSString stringWithUTF8String:payload];
}

static id flopper_parse_payload(const char* payload) {
  NSString* payloadString = flopper_payload_string(payload);
  if (payloadString == nil || payloadString.length == 0) {
    return nil;
  }

  unichar first = [payloadString characterAtIndex:0];
  if (first != '{' && first != '[') {
    return payloadString;
  }

  NSData* data = [payloadString dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return payloadString;
  }

  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return json ?: payloadString;
}

static const char* flopper_copy_utf8_string(NSString* value) {
  if (value == nil) {
    return NULL;
  }
  return strdup(value.UTF8String);
}

bool flopper_apple_client_is_available(void) {
  return flopper_client_class() != Nil;
}

void* flopper_apple_shared_client(void) {
  Class clientClass = flopper_client_class();
  if (clientClass == Nil) {
    return NULL;
  }

  id client = flopper_invoke0(clientClass, NSSelectorFromString(@"sharedClient"));
  return client == nil ? NULL : (__bridge_retained void*)client;
}

void flopper_apple_release(void* ref) {
  if (ref != NULL) {
    CFBridgingRelease(ref);
  }
}

void flopper_apple_client_start(void* clientRef) {
  id client = (__bridge id)clientRef;
  if (client != nil) {
    flopper_invoke0(client, NSSelectorFromString(@"start"));
  }
}

void flopper_apple_client_stop(void* clientRef) {
  id client = (__bridge id)clientRef;
  if (client != nil) {
    flopper_invoke0(client, NSSelectorFromString(@"stop"));
  }
}

bool flopper_apple_client_is_connected(void* clientRef) {
  id client = (__bridge id)clientRef;
  if (client == nil) {
    return false;
  }

  SEL selector = NSSelectorFromString(@"isConnected");
  BOOL (*msgSend)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
  return msgSend(client, selector);
}

const char* flopper_apple_client_copy_state(void* clientRef) {
  id client = (__bridge id)clientRef;
  if (client == nil) {
    return NULL;
  }

  NSString* state = flopper_invoke0(client, NSSelectorFromString(@"getState"));
  return flopper_copy_utf8_string(state);
}

const char* flopper_apple_client_copy_state_summary_json(void* clientRef) {
  id client = (__bridge id)clientRef;
  if (client == nil) {
    return NULL;
  }

  id elements = flopper_invoke0(client, NSSelectorFromString(@"getStateElements"));
  if (elements == nil) {
    return NULL;
  }

  NSData* data = [NSJSONSerialization dataWithJSONObject:elements options:0 error:nil];
  if (data == nil) {
    return NULL;
  }

  NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return flopper_copy_utf8_string(json);
}

void* flopper_apple_plugin_create(
    const char* identifier,
    bool runInBackground,
    void* pluginRef,
    FlopperKmpDidConnectCallback connectCallback,
    FlopperKmpDidDisconnectCallback disconnectCallback) {
  FlopperKmpPluginBridge* plugin = [FlopperKmpPluginBridge new];
  plugin.identifierValue = [NSString stringWithUTF8String:identifier ?: "unknown-plugin"];
  plugin.runInBackgroundValue = runInBackground;
  plugin.pluginRef = pluginRef;
  plugin.connectCallback = connectCallback;
  plugin.disconnectCallback = disconnectCallback;
  return (__bridge_retained void*)plugin;
}

void flopper_apple_client_add_plugin(void* clientRef, void* pluginRef) {
  id client = (__bridge id)clientRef;
  id plugin = (__bridge id)pluginRef;
  if (client != nil && plugin != nil) {
    flopper_invoke1(client, NSSelectorFromString(@"addPlugin:"), plugin);
  }
}

void flopper_apple_client_remove_plugin(void* clientRef, void* pluginRef) {
  id client = (__bridge id)clientRef;
  id plugin = (__bridge id)pluginRef;
  if (client != nil && plugin != nil) {
    flopper_invoke1(client, NSSelectorFromString(@"removePlugin:"), plugin);
  }
}

void flopper_apple_connection_send(void* connectionRef, const char* method, const char* payload) {
  id<KmpFlipperConnection> connection = (__bridge id<KmpFlipperConnection>)connectionRef;
  NSString* nsMethod = [NSString stringWithUTF8String:method ?: ""];
  id parsed = flopper_parse_payload(payload);

  if ([parsed isKindOfClass:[NSDictionary class]]) {
    [connection send:nsMethod withParams:(NSDictionary*)parsed];
  } else if ([parsed isKindOfClass:[NSArray class]]) {
    [connection send:nsMethod withArrayParams:(NSArray*)parsed];
  } else {
    [connection send:nsMethod withRawParams:parsed ?: @""];
  }
}

void flopper_apple_connection_receive(
    void* connectionRef,
    const char* method,
    void* receiverRef,
    FlopperKmpReceiverCallback receiverCallback) {
  id<KmpFlipperConnection> connection = (__bridge id<KmpFlipperConnection>)connectionRef;
  NSString* nsMethod = [NSString stringWithUTF8String:method ?: ""];
  [connection receive:nsMethod
            withBlock:^(NSDictionary* params, id<KmpFlipperResponder> responder) {
              NSData* jsonData = params == nil ? nil : [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
              NSString* json = jsonData == nil ? nil : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
              if (receiverCallback != NULL) {
                receiverCallback(receiverRef, json == nil ? NULL : json.UTF8String, (__bridge void*)responder);
              }
            }];
}

void flopper_apple_connection_report_error(
    void* connectionRef,
    const char* reason,
    const char* stackTrace) {
  id<KmpFlipperConnection> connection = (__bridge id<KmpFlipperConnection>)connectionRef;
  [connection errorWithMessage:flopper_payload_string(reason) ?: @"Unknown error"
                    stackTrace:flopper_payload_string(stackTrace) ?: @""];
}

static NSDictionary* flopper_dictionary_from_payload(const char* payload) {
  id parsed = flopper_parse_payload(payload);
  if ([parsed isKindOfClass:[NSDictionary class]]) {
    return parsed;
  }
  if ([parsed isKindOfClass:[NSString class]]) {
    return @{@"message" : parsed};
  }
  return @{};
}

void flopper_apple_responder_success(void* responderRef, const char* payload) {
  id<KmpFlipperResponder> responder = (__bridge id<KmpFlipperResponder>)responderRef;
  [responder success:flopper_dictionary_from_payload(payload)];
}

void flopper_apple_responder_error(void* responderRef, const char* payload) {
  id<KmpFlipperResponder> responder = (__bridge id<KmpFlipperResponder>)responderRef;
  [responder error:flopper_dictionary_from_payload(payload)];
}

void flopper_apple_buffer_free(void* value) {
  if (value != NULL) {
    free(value);
  }
}
