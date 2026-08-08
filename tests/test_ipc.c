#include "harness.h"
#include "ipc.h"

#include <errno.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct SendContext {
    xipc_t* ipc;
    int sends;
} SendContext;

static void* send_messages(void* opaque) {
    SendContext* context = (SendContext*)opaque;
    int payload = 42;
    for (int i = 0; i < context->sends; i++) {
        xipc_send_data(context->ipc, &payload, sizeof(payload));
    }
    return NULL;
}

TEST_CASE(exact_path_does_not_accept_suffix_forgery) {
    const char* installed = "/Applications/osxrdp/OSXRDP.app/Contents/MacOS/xrdp";
    EXPECT_TRUE(xipc_path_matches_exact(installed, installed));
    EXPECT_TRUE(!xipc_path_matches_exact("/tmp/fake/OSXRDP.app/Contents/MacOS/xrdp", installed));
    EXPECT_TRUE(!xipc_path_matches_exact(NULL, installed));
}

TEST_CASE(identity_policy_covers_team_identifier_and_adhoc_matrix) {
    const char* official = "33X7M69J4B";
    const char* installed = "/Applications/osxrdp/OSXRDP.app/Contents/MacOS/xrdp";

    EXPECT_TRUE(xipc_identity_policy_allows(official, NULL, official, "xrdp", "xrdp", NULL, installed));
    EXPECT_TRUE(xipc_identity_policy_allows("DEVTEAM", "DEVTEAM", official, "xrdp", "xrdp", NULL, installed));
    EXPECT_TRUE(!xipc_identity_policy_allows("OTHER", "DEVTEAM", official, "xrdp", "xrdp", NULL, installed));
    EXPECT_TRUE(!xipc_identity_policy_allows(official, NULL, official, "fake", "xrdp", NULL, installed));
    EXPECT_TRUE(xipc_identity_policy_allows(NULL, NULL, official, "xrdp", "xrdp", installed, installed));
    EXPECT_TRUE(!xipc_identity_policy_allows(NULL, NULL, official, "xrdp", "xrdp",
                                             "/tmp/fake/OSXRDP.app/Contents/MacOS/xrdp", installed));
}

TEST_CASE(connection_limit_is_enforced_at_boundary) {
    EXPECT_TRUE(!xipc_can_accept_client_count(-1));
    EXPECT_TRUE(xipc_can_accept_client_count(XIPC_MAX_CLIENTS - 1));
    EXPECT_TRUE(!xipc_can_accept_client_count(XIPC_MAX_CLIENTS));
}

TEST_CASE(private_directory_rejects_bad_mode_and_symlink) {
    char directory[] = "/tmp/osxrdp-ipc-test.XXXXXX";
    EXPECT_NOT_NULL(mkdtemp(directory));
    EXPECT_EQ_INT(xipc_prepare_private_directory(directory, geteuid(), (gid_t)-1), 0);
    EXPECT_EQ_INT(chmod(directory, 0755), 0);
    EXPECT_EQ_INT(xipc_prepare_private_directory(directory, geteuid(), (gid_t)-1), EPERM);
    EXPECT_EQ_INT(chmod(directory, 0700), 0);

    char linkPath[160];
    snprintf(linkPath, sizeof(linkPath), "%s-link", directory);
    EXPECT_EQ_INT(symlink(directory, linkPath), 0);
    EXPECT_EQ_INT(xipc_prepare_private_directory(linkPath, geteuid(), (gid_t)-1), EPERM);
    unlink(linkPath);
    rmdir(directory);
}

TEST_CASE(peer_euid_comes_from_unix_socket) {
    int sockets[2] = {-1, -1};
    EXPECT_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets), 0);
    xipc_t* ipc = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(ipc);
    ipc->fd = sockets[0];
    uid_t peerUid = (uid_t)-1;
    EXPECT_EQ_INT(xipc_get_peer_euid(ipc, &peerUid), 0);
    EXPECT_EQ_INT((int)peerUid, (int)geteuid());
    close(sockets[1]);
    xipc_destroy(ipc);
}

TEST_CASE(verified_connect_checks_socket_owner_and_private_parent) {
    char directory[] = "/private/tmp/osxrdp-ipc-connect.XXXXXX";
    EXPECT_NOT_NULL(mkdtemp(directory));
    EXPECT_EQ_INT(chmod(directory, 0700), 0);

    char socketPath[180];
    snprintf(socketPath, sizeof(socketPath), "%s/server.sock", directory);
    xipc_t* server = xipc_ctx_create(NULL, NULL);
    xipc_t* client = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(server);
    EXPECT_NOT_NULL(client);
    EXPECT_EQ_INT(xipc_validate_private_directory(directory, geteuid(), (gid_t)-1), 0);
    int createResult = xipc_create_server(server, socketPath, NULL, NULL, NULL, NULL);
    if (createResult == EPERM) {
        xipc_destroy(client);
        xipc_destroy(server);
        rmdir(directory);
        SKIP_TEST("verified AF_UNIX bind (sandbox denied bind)");
    }
    EXPECT_EQ_INT(createResult, 0);
    if (createResult != 0) {
        xipc_destroy(client);
        xipc_destroy(server);
        rmdir(directory);
        return;
    }
    EXPECT_EQ_INT(xipc_connect_server_verified(client, socketPath, geteuid(), (gid_t)-1), 0);
    xipc_destroy(client);
    xipc_destroy(server);
    rmdir(directory);
}

TEST_CASE(concurrent_senders_share_one_queue_lock) {
    xipc_t* ipc = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(ipc);
    enum { THREADS = 4, SENDS = 250 };
    pthread_t threads[THREADS];
    SendContext context = {ipc, SENDS};
    for (int i = 0; i < THREADS; i++) {
        EXPECT_EQ_INT(pthread_create(&threads[i], NULL, send_messages, &context), 0);
    }
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
    }

    int messageCount = 0;
    pthread_mutex_lock(&ipc->lock);
    for (xipc_msg_t* message = ipc->out_msgs; message != NULL; message = message->next) {
        messageCount++;
    }
    pthread_mutex_unlock(&ipc->lock);
    EXPECT_EQ_INT(messageCount, THREADS * SENDS);
    xipc_destroy(ipc);
}

TEST_CASE(closed_context_rejects_new_messages) {
    xipc_t* ipc = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(ipc);
    int payload = 1;
    EXPECT_EQ_INT(xipc_send_data(ipc, &payload, sizeof(payload)), (int)sizeof(payload));
    xipc_close(ipc);
    EXPECT_EQ_INT(xipc_send_data(ipc, &payload, sizeof(payload)), -1);
    pthread_mutex_lock(&ipc->lock);
    EXPECT_NULL(ipc->out_msgs);
    EXPECT_NULL(ipc->out_msgs_end);
    pthread_mutex_unlock(&ipc->lock);
    xipc_destroy(ipc);
}

TEST_CASE(close_racing_senders_leaves_no_queued_messages) {
    xipc_t* ipc = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(ipc);
    enum { THREADS = 4, SENDS = 2000 };
    pthread_t threads[THREADS];
    SendContext context = {ipc, SENDS};
    for (int i = 0; i < THREADS; i++) {
        EXPECT_EQ_INT(pthread_create(&threads[i], NULL, send_messages, &context), 0);
    }
    xipc_close(ipc);
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    pthread_mutex_lock(&ipc->lock);
    EXPECT_NULL(ipc->out_msgs);
    pthread_mutex_unlock(&ipc->lock);
    xipc_destroy(ipc);
}

int main(void) {
    RUN_TEST(exact_path_does_not_accept_suffix_forgery);
    RUN_TEST(identity_policy_covers_team_identifier_and_adhoc_matrix);
    RUN_TEST(connection_limit_is_enforced_at_boundary);
    RUN_TEST(private_directory_rejects_bad_mode_and_symlink);
    RUN_TEST(peer_euid_comes_from_unix_socket);
    RUN_TEST(verified_connect_checks_socket_owner_and_private_parent);
    RUN_TEST(concurrent_senders_share_one_queue_lock);
    RUN_TEST(closed_context_rejects_new_messages);
    RUN_TEST(close_racing_senders_leaves_no_queued_messages);
    return test_main_finish("test_ipc");
}
