#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

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

@interface FlopperKmpFallbackClient : NSObject
@property(nonatomic, strong) NSMutableArray<id<KmpFlipperPlugin>>* plugins;
@property(nonatomic, strong) FlopperKmpFallbackConnection* connection;
@property(nonatomic, assign, getter=isStarted) BOOL started;
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

static Class flopper_client_class(void) {
  Class runtimeClass = NSClassFromString(@"FlipperClient");
  return runtimeClass ?: [FlopperKmpFallbackClient class];
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
