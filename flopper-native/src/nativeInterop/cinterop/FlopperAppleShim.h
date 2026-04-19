#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FlopperKmpDidConnectCallback)(void* pluginRef, void* connectionRef);
typedef void (*FlopperKmpDidDisconnectCallback)(void* pluginRef);
typedef void (*FlopperKmpReceiverCallback)(void* receiverRef, const char* paramsJson, void* responderRef);

bool flopper_apple_client_is_available(void);
void* flopper_apple_shared_client(void);
void flopper_apple_release(void* ref);

void flopper_apple_client_start(void* clientRef);
void flopper_apple_client_stop(void* clientRef);
bool flopper_apple_client_is_connected(void* clientRef);
const char* flopper_apple_client_copy_state(void* clientRef);
const char* flopper_apple_client_copy_state_summary_json(void* clientRef);

void* flopper_apple_plugin_create(
    const char* identifier,
    bool runInBackground,
    void* pluginRef,
    FlopperKmpDidConnectCallback connectCallback,
    FlopperKmpDidDisconnectCallback disconnectCallback);
void flopper_apple_client_add_plugin(void* clientRef, void* pluginRef);
void flopper_apple_client_remove_plugin(void* clientRef, void* pluginRef);

void flopper_apple_connection_send(void* connectionRef, const char* method, const char* payload);
void flopper_apple_connection_receive(
    void* connectionRef,
    const char* method,
    void* receiverRef,
    FlopperKmpReceiverCallback receiverCallback);
void flopper_apple_connection_report_error(
    void* connectionRef,
    const char* reason,
    const char* stackTrace);

void flopper_apple_responder_success(void* responderRef, const char* payload);
void flopper_apple_responder_error(void* responderRef, const char* payload);
void flopper_apple_buffer_free(void* value);

#ifdef __cplusplus
}
#endif
