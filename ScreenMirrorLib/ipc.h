#ifndef ipc_h
#define ipc_h

#define MAX_BUFFER (1024 * 16)
#define XIPC_MAX_CLIENTS 128

#include <pthread.h>
#include <stdbool.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

struct xipc;

typedef int (*xipc_client_onconnected)(struct xipc* ipc, struct xipc* client);
typedef int (*xipc_client_ondisconnected)(struct xipc* ipc, struct xipc* client);
/* return 0 to allow the client, otherwise the server closes the connection */
typedef int (*xipc_client_onauthorize)(struct xipc* ipc, struct xipc* client);
/* called only when onauthorize rejects the client */
typedef int (*xipc_client_onrejected)(struct xipc* ipc, struct xipc* client);
typedef int (*xipc_data_callback)(struct xipc* ipc, struct xipc* client, void* data, int len);

typedef struct xipc_msg {
    int len;
    int num_send;
    struct xipc_msg* next;
    char data[];
} xipc_msg_t;


typedef struct xipc {
    int fd;
    int isServer;
    /* Access only through xipc_close()/xipc_is_closed() or the atomic
     * helpers in ipc.c. Keeping the storage type C/C++ neutral avoids
     * leaking C11 stdatomic macros into Objective-C++ consumers. */
    int closed;
    int unused;
    int wakeup_pipe[2];
    
    char in_buf[MAX_BUFFER];
    int in_len;
    int expected_len;
    
    char* server_name;
    
    pthread_mutex_t lock;
    xipc_msg_t* out_msgs;
    xipc_msg_t* out_msgs_end;
    xipc_data_callback on_data;
    xipc_client_onconnected on_client_connected;
    xipc_client_ondisconnected on_client_disconnected;
    xipc_client_onauthorize on_client_authorize;
    xipc_client_onrejected on_client_rejected;
    void* user_data;
    struct xipc* next;
} xipc_t;

xipc_t* xipc_ctx_create(xipc_data_callback on_data, void* userData);
void xipc_destroy(xipc_t* ipc);

int xipc_create_server(xipc_t* ipc, const char* path, xipc_client_onconnected on_client_connected, xipc_client_ondisconnected on_client_disconnected, xipc_client_onauthorize on_client_authorize, xipc_client_onrejected on_client_rejected);
int xipc_connect_server(xipc_t* ipc, const char* path);
/* Validate the parent directory and socket node before connecting. Peer code
 * identity must still be checked after connect to close the TOCTOU window. */
int xipc_connect_server_verified(xipc_t* ipc, const char* path, uid_t ownerUid, gid_t ownerGid);
int xipc_get_peer_pid(xipc_t* client, pid_t* pid);
int xipc_get_peer_euid(xipc_t* client, uid_t* uid);
int xipc_is_client_signed_by(xipc_t* client, const char* expectedTeamId, const char* expectedSigningIdentifier);
/* Trust a peer with the exact identifier when it is signed by officialTeamId,
 * by the same Team ID as this process, or ad-hoc at expectedAdhocPath.
 * expectedAdhocPath must be an exact absolute executable path. */
int xipc_is_trusted_peer(xipc_t* client,
                         const char* officialTeamId,
                         const char* expectedSigningIdentifier,
                         const char* expectedAdhocPath);
bool xipc_path_matches_exact(const char* actualPath, const char* expectedPath);
/* Pure identity-policy helper used by the Security.framework adapter and unit
 * tests. A NULL peerTeamId represents a valid ad-hoc signature. */
bool xipc_identity_policy_allows(const char* peerTeamId,
                                 const char* selfTeamId,
                                 const char* officialTeamId,
                                 const char* peerIdentifier,
                                 const char* expectedIdentifier,
                                 const char* peerPath,
                                 const char* expectedAdhocPath);
bool xipc_can_accept_client_count(int currentClientCount);

/* Create (if absent) and validate a private socket directory. Existing paths
 * must be real directories owned by ownerUid with no group/other permissions.
 * Pass (gid_t)-1 when group ownership is intentionally not part of policy. */
int xipc_prepare_private_directory(const char* path, uid_t ownerUid, gid_t ownerGid);
int xipc_validate_private_directory(const char* path, uid_t ownerUid, gid_t ownerGid);

/* Atomically mark a context closed and wake its I/O loop. */
void xipc_close(xipc_t* ipc);
int xipc_is_closed(const xipc_t* ipc);

int xipc_send_data(xipc_t* ipc, const void* data, int len);
void xipc_loop(xipc_t* ipc);
void xipc_end_loop(xipc_t* ipc);
void xipc_loop_once(xipc_t* ipc);

#ifdef __cplusplus
}
#endif

#endif /* ipc_h */
