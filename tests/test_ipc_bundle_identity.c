#include "harness.h"
#include "ipc.h"

#include <limits.h>
#include <sys/socket.h>
#include <unistd.h>

static char gExecutablePath[PATH_MAX];

TEST_CASE(adhoc_app_bundle_uses_exact_main_executable_path) {
    int sockets[2] = {-1, -1};
    int socketResult = socketpair(AF_UNIX, SOCK_STREAM, 0, sockets);
    EXPECT_EQ_INT(socketResult, 0);
    if (socketResult != 0) {
        return;
    }

    xipc_t* peer = xipc_ctx_create(NULL, NULL);
    EXPECT_NOT_NULL(peer);
    if (peer == NULL) {
        close(sockets[0]);
        close(sockets[1]);
        return;
    }

    peer->fd = sockets[0];
    EXPECT_EQ_INT(xipc_is_trusted_peer(peer,
                                       "NOT_AN_OFFICIAL_TEAM",
                                       "com.byungho.osxrdp.testpeer",
                                       gExecutablePath),
                  0);
    EXPECT_TRUE(xipc_is_trusted_peer(peer,
                                     "NOT_AN_OFFICIAL_TEAM",
                                     "com.byungho.osxrdp.testpeer",
                                     "/tmp/fake/IPCBundlePeer.app/Contents/MacOS/ipc_bundle_peer") != 0);

    close(sockets[1]);
    xipc_destroy(peer);
}

int main(int argc, char** argv) {
    if (argc != 1 || realpath(argv[0], gExecutablePath) == NULL) {
        fprintf(stderr, "FAIL could not resolve app bundle executable path\n");
        return 1;
    }

    RUN_TEST(adhoc_app_bundle_uses_exact_main_executable_path);
    return test_main_finish("test_ipc_bundle_identity");
}
