#include "ipc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <limits.h>
#include <Security/Security.h>

#define MAX_POLL_FDS ((XIPC_MAX_CLIENTS + 1) * 2)

static int xipc_load_closed(const xipc_t* ipc)
{
    return __atomic_load_n(&ipc->closed, __ATOMIC_ACQUIRE);
}

static void xipc_store_closed(xipc_t* ipc, int closed)
{
    __atomic_store_n(&ipc->closed, closed, __ATOMIC_RELEASE);
}

static void xipc_wake(xipc_t* ipc)
{
    if (ipc == NULL || ipc->wakeup_pipe[1] < 0)
    {
        return;
    }

    ssize_t result = write(ipc->wakeup_pipe[1], "W", 1);
    if (result < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
    {
        xipc_store_closed(ipc, 1);
    }
}

static void xipc_drain_wakeup(xipc_t* ipc)
{
    char buffer[64];
    while (read(ipc->wakeup_pipe[0], buffer, sizeof(buffer)) > 0)
    {
    }
}

static int cfstring_equals_cstring(CFStringRef value, const char* expected)
{
    if (value == NULL || expected == NULL)
    {
        return 0;
    }

    CFStringRef expectedValue = CFStringCreateWithCString(kCFAllocatorDefault, expected, kCFStringEncodingUTF8);
    if (expectedValue == NULL)
    {
        return 0;
    }

    int isEqual = CFStringCompare(value, expectedValue, 0) == kCFCompareEqualTo;
    CFRelease(expectedValue);

    return isEqual;
}

void set_nonBlocking(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0)
    {
        return;
    }

    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
}

void remove_at_clients_list(xipc_t* server, xipc_t* client)
{
    if (server == NULL || client == NULL)
    {
        return;
    }
    
    if (server->isServer == 0)
    {
        return;
    }
    
    if (client->isServer != 0)
    {
        return;
    }
    
    if (server->next == NULL)
    {
        return;
    }
    
    if (server->next == client)
    {
        server->next = server->next->next;
    }
    else
    {
        xipc_t* tmp = server->next;
        xipc_t* prev = server->next;
        while (tmp != NULL)
        {
            if (tmp == client)
            {
                prev->next = client->next;
                break;
            }
            
            prev = tmp;
            tmp = tmp->next;
        }
    }
    
    client->next = NULL;
}

void prepare_wait_poll(int* currentIndex, struct pollfd* fds, xipc_t** ipcs, xipc_t* ipc);
int accept_new_client(xipc_t* ipc);

int send_data_to_client(xipc_t* client, int* needClose);
int write_data_to_socket(xipc_t* client, xipc_msg_t* msg);

int recv_data_from_client(xipc_t* ipc, xipc_t* client, int* needClose);
int read_header_from_socket(xipc_t* client, int* needClose);
int read_data_from_socket(xipc_t* client, int* needClose);

xipc_t* xipc_ctx_create(xipc_data_callback on_data, void* userData)
{
    xipc_t* ipc = (xipc_t*)malloc(sizeof(xipc_t));
    if (ipc == NULL)
    {
        return NULL;
    }
    
    memset(ipc, 0x00, sizeof(xipc_t));
    xipc_store_closed(ipc, 0);
    ipc->fd = -1;
    ipc->wakeup_pipe[0] = -1;
    ipc->wakeup_pipe[1] = -1;
    
    ipc->on_data = on_data;
    pthread_mutex_init(&ipc->lock, NULL);
    
    if (pipe(ipc->wakeup_pipe) < 0)
    {
        pthread_mutex_destroy(&ipc->lock);
        free(ipc);
        return NULL;
    }
    
    ipc->user_data = userData;
    set_nonBlocking(ipc->wakeup_pipe[0]);
    set_nonBlocking(ipc->wakeup_pipe[1]);
    
    return ipc;
}


void xipc_destroy(xipc_t* ipc)
{
    if (ipc == NULL)
    {
        return;
    }
    
    xipc_store_closed(ipc, 1);

    xipc_t* clients = NULL;
    if (ipc->isServer)
    {
        pthread_mutex_lock(&ipc->lock);
        clients = ipc->next;
        ipc->next = NULL;
        pthread_mutex_unlock(&ipc->lock);
    }

    if (ipc->isServer == 1 && ipc->on_client_disconnected)
    {
        for (xipc_t* client = clients; client != NULL; client = client->next)
        {
            ipc->on_client_disconnected(ipc, client);
        }
    }

    while (clients != NULL)
    {
        xipc_t* next = clients->next;
        clients->next = NULL;
        xipc_destroy(clients);
        clients = next;
    }

    if (ipc->fd >= 0)
    {
        close(ipc->fd);
        ipc->fd = -1;
    }

    if (ipc->wakeup_pipe[0] >= 0)
    {
        close(ipc->wakeup_pipe[0]);
        ipc->wakeup_pipe[0] = -1;
    }

    if (ipc->wakeup_pipe[1] >= 0)
    {
        close(ipc->wakeup_pipe[1]);
        ipc->wakeup_pipe[1] = -1;
    }

    pthread_mutex_lock(&ipc->lock);
    xipc_msg_t* messages = ipc->out_msgs;
    ipc->out_msgs = NULL;
    ipc->out_msgs_end = NULL;
    pthread_mutex_unlock(&ipc->lock);

    while (messages != NULL)
    {
        xipc_msg_t* next = messages->next;
        free(messages);
        messages = next;
    }

    pthread_mutex_destroy(&ipc->lock);

    if (ipc->isServer)
    {
        struct stat socketInfo;
        if (ipc->server_name != NULL && lstat(ipc->server_name, &socketInfo) == 0 &&
            S_ISSOCK(socketInfo.st_mode) && socketInfo.st_uid == geteuid())
        {
            unlink(ipc->server_name);
        }
    }
    
    free(ipc->server_name);
    free(ipc);
}

int xipc_validate_private_directory(const char* path, uid_t ownerUid, gid_t ownerGid)
{
    if (path == NULL || path[0] != '/')
    {
        return EINVAL;
    }

    struct stat info;
    if (lstat(path, &info) != 0)
    {
        return errno;
    }

    if (!S_ISDIR(info.st_mode) || S_ISLNK(info.st_mode) || info.st_uid != ownerUid ||
        (ownerGid != (gid_t)-1 && info.st_gid != ownerGid) ||
        (info.st_mode & (S_IRWXG | S_IRWXO)) != 0 ||
        (info.st_mode & S_IRWXU) != S_IRWXU)
    {
        return EPERM;
    }

    return 0;
}

int xipc_prepare_private_directory(const char* path, uid_t ownerUid, gid_t ownerGid)
{
    if (path == NULL || path[0] != '/')
    {
        return EINVAL;
    }

    struct stat info;
    if (lstat(path, &info) != 0)
    {
        if (errno != ENOENT)
        {
            return errno;
        }

        if (mkdir(path, S_IRWXU) != 0)
        {
            return errno;
        }

        if (geteuid() == 0 && chown(path, ownerUid, ownerGid == (gid_t)-1 ? (gid_t)-1 : ownerGid) != 0)
        {
            int error = errno;
            rmdir(path);
            return error;
        }

        if (lstat(path, &info) != 0)
        {
            return errno;
        }
    }

    return xipc_validate_private_directory(path, ownerUid, ownerGid);
}

static int xipc_copy_socket_parent(const char* path, char* parent, size_t parentSize)
{
    size_t pathLen = strlen(path);
    if (pathLen == 0 || pathLen >= sizeof(((struct sockaddr_un*)0)->sun_path))
    {
        return ENAMETOOLONG;
    }

    const char* separator = strrchr(path, '/');
    if (separator == NULL || separator == path)
    {
        return EINVAL;
    }

    size_t parentLen = (size_t)(separator - path);
    if (parentLen >= parentSize)
    {
        return ENAMETOOLONG;
    }
    memcpy(parent, path, parentLen);
    parent[parentLen] = '\0';

    return 0;
}

static int xipc_validate_socket_parent(const char* path, uid_t ownerUid, gid_t ownerGid)
{
    char parent[PATH_MAX];
    int result = xipc_copy_socket_parent(path, parent, sizeof(parent));
    return result == 0 ? xipc_validate_private_directory(parent, ownerUid, ownerGid) : result;
}

int xipc_create_server(xipc_t* ipc, const char* path, xipc_client_onconnected on_client_connected, xipc_client_ondisconnected on_client_disconnected, xipc_client_onauthorize on_client_authorize, xipc_client_onrejected on_client_rejected)
{
    if (ipc == NULL || path == NULL)
    {
        return EINVAL;
    }
        
    int validationError = xipc_validate_socket_parent(path, geteuid(), (gid_t)-1);
    if (validationError != 0)
    {
        return validationError;
    }

    struct stat oldSocket;
    if (lstat(path, &oldSocket) == 0)
    {
        if (!S_ISSOCK(oldSocket.st_mode) || oldSocket.st_uid != geteuid())
        {
            return EPERM;
        }
        if (unlink(path) != 0)
        {
            return errno;
        }
    }
    else if (errno != ENOENT)
    {
        return errno;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
    {
        return errno;
    }
    
    struct sockaddr_un addr = {0,};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - sizeof(char));
    
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
    {
        close(fd);
        
        return errno;
    }

    // Restrict socket filesystem node to the owner (mitigates local unprivileged clients).
    // Use chmod on the path: fchmod on AF_UNIX is not reliable across platforms.
    if (chmod(path, S_IRUSR | S_IWUSR) != 0)
    {
        close(fd);
        unlink(path);
        return errno;
    }
    
    if (listen(fd, 10) < 0)
    {
        close(fd);
        unlink(path);
        return errno;
    }
    
    ipc->fd = fd;
    ipc->isServer = 1;
    ipc->on_client_connected = on_client_connected;
    ipc->on_client_disconnected = on_client_disconnected;
    ipc->on_client_authorize = on_client_authorize;
    ipc->on_client_rejected = on_client_rejected;
    ipc->server_name = strdup(path);
    if (ipc->server_name == NULL) {
        ipc->isServer = 0;
        close(fd);
        ipc->fd = -1;
        unlink(path);
        return ENOMEM;
    }

    set_nonBlocking(ipc->fd);
    
    return 0;
}


int xipc_connect_server(xipc_t* ipc, const char* path)
{
    if (ipc == NULL || path == NULL)
    {
        return EINVAL;
    }
    
    if (strlen(path) >= sizeof(((struct sockaddr_un*)0)->sun_path))
    {
        return ENAMETOOLONG;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
    {
        return errno;
    }
    
    struct sockaddr_un addr = {0,};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - sizeof(char));
    
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
    {
        close(fd);
        
        return errno;
    }
    
    ipc->fd = fd;
    ipc->isServer = 0;
    ipc->server_name = strdup(path);
    if (ipc->server_name == NULL)
    {
        close(fd);
        ipc->fd = -1;
        return ENOMEM;
    }

    set_nonBlocking(ipc->fd);
    
    return 0;
}

int xipc_connect_server_verified(xipc_t* ipc, const char* path, uid_t ownerUid, gid_t ownerGid)
{
    int result = xipc_validate_socket_parent(path, ownerUid, ownerGid);
    if (result != 0)
    {
        return result;
    }

    struct stat socketInfo;
    if (lstat(path, &socketInfo) != 0)
    {
        return errno;
    }
    if (!S_ISSOCK(socketInfo.st_mode) || S_ISLNK(socketInfo.st_mode) ||
        socketInfo.st_uid != ownerUid ||
        (ownerGid != (gid_t)-1 && socketInfo.st_gid != ownerGid) ||
        (socketInfo.st_mode & (S_IRWXG | S_IRWXO)) != 0)
    {
        return EPERM;
    }

    return xipc_connect_server(ipc, path);
}

int xipc_get_peer_pid(xipc_t* client, pid_t* pid)
{
    if (client == NULL || pid == NULL || client->fd <= 0)
    {
        return EINVAL;
    }

    pid_t peerPid = 0;
    socklen_t peerPidLen = sizeof(peerPid);
    if (getsockopt(client->fd, SOL_LOCAL, LOCAL_PEERPID, &peerPid, &peerPidLen) != 0)
    {
        return errno != 0 ? errno : -1;
    }

    if (peerPidLen != sizeof(peerPid) || peerPid <= 0)
    {
        return EINVAL;
    }

    *pid = peerPid;
    return 0;
}

int xipc_get_peer_euid(xipc_t* client, uid_t* uid)
{
    if (client == NULL || uid == NULL || client->fd < 0)
    {
        return EINVAL;
    }

    gid_t gid = 0;
    if (getpeereid(client->fd, uid, &gid) != 0)
    {
        return errno != 0 ? errno : -1;
    }

    return 0;
}

static int xipc_copy_code_for_pid(pid_t pid, SecCodeRef* outCode)
{
    if (outCode == NULL || pid <= 0)
    {
        return EINVAL;
    }

    *outCode = NULL;

    CFNumberRef pidNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    if (pidNumber == NULL)
    {
        return -1;
    }

    const void* keys[] = { kSecGuestAttributePid };
    const void* values[] = { pidNumber };
    CFDictionaryRef attributes = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(pidNumber);
    if (attributes == NULL)
    {
        return -1;
    }

    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, outCode);
    CFRelease(attributes);
    return status == errSecSuccess ? 0 : -1;
}

static int xipc_get_main_executable_path(CFDictionaryRef signingInfo, char* outPath, size_t outPathSize)
{
    if (signingInfo == NULL || outPath == NULL || outPathSize == 0)
    {
        return -1;
    }

    outPath[0] = '\0';

    CFTypeRef pathValue = CFDictionaryGetValue(signingInfo, kSecCodeInfoMainExecutable);
    if (pathValue == NULL || CFGetTypeID(pathValue) != CFURLGetTypeID())
    {
        return -1;
    }

    CFURLRef pathUrl = (CFURLRef)pathValue;
    Boolean ok = CFURLGetFileSystemRepresentation(pathUrl, true, (UInt8*)outPath, (CFIndex)outPathSize);
    return ok ? 0 : -1;
}

bool xipc_path_matches_exact(const char* actualPath, const char* expectedPath)
{
    return actualPath != NULL && expectedPath != NULL && expectedPath[0] == '/' &&
           strcmp(actualPath, expectedPath) == 0;
}

bool xipc_identity_policy_allows(const char* peerTeamId,
                                 const char* selfTeamId,
                                 const char* officialTeamId,
                                 const char* peerIdentifier,
                                 const char* expectedIdentifier,
                                 const char* peerPath,
                                 const char* expectedAdhocPath)
{
    if (peerIdentifier == NULL || expectedIdentifier == NULL ||
        strcmp(peerIdentifier, expectedIdentifier) != 0)
    {
        return false;
    }

    if (peerTeamId != NULL && peerTeamId[0] != '\0')
    {
        return (officialTeamId != NULL && strcmp(peerTeamId, officialTeamId) == 0) ||
               (selfTeamId != NULL && selfTeamId[0] != '\0' && strcmp(peerTeamId, selfTeamId) == 0);
    }

    return xipc_path_matches_exact(peerPath, expectedAdhocPath);
}

bool xipc_can_accept_client_count(int currentClientCount)
{
    return currentClientCount >= 0 && currentClientCount < XIPC_MAX_CLIENTS;
}

int xipc_is_client_signed_by(xipc_t* client, const char* expectedTeamId, const char* expectedSigningIdentifier)
{
    if (client == NULL || expectedTeamId == NULL || expectedSigningIdentifier == NULL)
    {
        return EINVAL;
    }

    pid_t peerPid = 0;
    if (xipc_get_peer_pid(client, &peerPid) != 0)
    {
        return -1;
    }

    int result = -1;
    SecCodeRef peerCode = NULL;
    CFDictionaryRef signingInfo = NULL;

    if (xipc_copy_code_for_pid(peerPid, &peerCode) != 0)
    {
        goto cleanup;
    }

    if (SecCodeCheckValidity(peerCode, kSecCSDefaultFlags, NULL) != errSecSuccess)
    {
        goto cleanup;
    }

    if (SecCodeCopySigningInformation(peerCode, kSecCSSigningInformation, &signingInfo) != errSecSuccess)
    {
        goto cleanup;
    }

    CFStringRef teamId = CFDictionaryGetValue(signingInfo, kSecCodeInfoTeamIdentifier);
    CFStringRef signingIdentifier = CFDictionaryGetValue(signingInfo, kSecCodeInfoIdentifier);
    if (teamId == NULL || signingIdentifier == NULL)
    {
        goto cleanup;
    }

    if (CFGetTypeID(teamId) != CFStringGetTypeID() || CFGetTypeID(signingIdentifier) != CFStringGetTypeID())
    {
        goto cleanup;
    }

    if (cfstring_equals_cstring(teamId, expectedTeamId) == 0)
    {
        goto cleanup;
    }

    if (cfstring_equals_cstring(signingIdentifier, expectedSigningIdentifier) == 0)
    {
        goto cleanup;
    }

    result = 0;

cleanup:
    if (signingInfo != NULL)
    {
        CFRelease(signingInfo);
    }

    if (peerCode != NULL)
    {
        CFRelease(peerCode);
    }

    return result;
}

int xipc_is_trusted_peer(xipc_t* client,
                         const char* officialTeamId,
                         const char* expectedSigningIdentifier,
                         const char* expectedAdhocPath)
{
    if (client == NULL || expectedSigningIdentifier == NULL)
    {
        return EINVAL;
    }

    pid_t peerPid = 0;
    if (xipc_get_peer_pid(client, &peerPid) != 0)
    {
        return -1;
    }

    int result = -1;
    SecCodeRef peerCode = NULL;
    SecCodeRef selfCode = NULL;
    CFDictionaryRef peerInfo = NULL;
    CFDictionaryRef selfInfo = NULL;
    char peerPath[PATH_MAX] = {0};
    char peerIdentifierValue[256] = {0};
    char peerTeamValue[256] = {0};
    char selfTeamValue[256] = {0};

    if (xipc_copy_code_for_pid(peerPid, &peerCode) != 0)
    {
        goto cleanup;
    }

    if (SecCodeCheckValidity(peerCode, kSecCSDefaultFlags, NULL) != errSecSuccess)
    {
        goto cleanup;
    }

    if (SecCodeCopySigningInformation(peerCode, kSecCSSigningInformation, &peerInfo) != errSecSuccess || peerInfo == NULL)
    {
        goto cleanup;
    }

    CFStringRef peerIdentifier = CFDictionaryGetValue(peerInfo, kSecCodeInfoIdentifier);
    if (peerIdentifier == NULL || CFGetTypeID(peerIdentifier) != CFStringGetTypeID())
    {
        goto cleanup;
    }

    if (!CFStringGetCString(peerIdentifier, peerIdentifierValue, sizeof(peerIdentifierValue),
                           kCFStringEncodingUTF8))
    {
        goto cleanup;
    }

    CFStringRef peerTeamId = CFDictionaryGetValue(peerInfo, kSecCodeInfoTeamIdentifier);
    if (peerTeamId != NULL && CFGetTypeID(peerTeamId) != CFStringGetTypeID())
    {
        peerTeamId = NULL;
    }

    const char* peerTeamCString = NULL;
    if (peerTeamId != NULL)
    {
        if (!CFStringGetCString(peerTeamId, peerTeamValue, sizeof(peerTeamValue), kCFStringEncodingUTF8))
        {
            goto cleanup;
        }
        peerTeamCString = peerTeamValue;
    }

    const char* selfTeamCString = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &selfCode) == errSecSuccess && selfCode != NULL)
    {
        if (SecCodeCopySigningInformation(selfCode, kSecCSSigningInformation, &selfInfo) == errSecSuccess && selfInfo != NULL)
        {
            CFStringRef selfTeamId = CFDictionaryGetValue(selfInfo, kSecCodeInfoTeamIdentifier);
            if (selfTeamId != NULL && CFGetTypeID(selfTeamId) == CFStringGetTypeID() &&
                CFStringGetCString(selfTeamId, selfTeamValue, sizeof(selfTeamValue), kCFStringEncodingUTF8))
            {
                selfTeamCString = selfTeamValue;
            }
        }
    }

    if (peerTeamId == NULL && expectedAdhocPath != NULL)
    {
        (void)xipc_get_main_executable_path(peerInfo, peerPath, sizeof(peerPath));
    }

    if (xipc_identity_policy_allows(peerTeamCString, selfTeamCString, officialTeamId,
                                    peerIdentifierValue, expectedSigningIdentifier,
                                    peerPath[0] != '\0' ? peerPath : NULL, expectedAdhocPath))
    {
        result = 0;
    }

cleanup:
    if (selfInfo != NULL)
    {
        CFRelease(selfInfo);
    }

    if (selfCode != NULL)
    {
        CFRelease(selfCode);
    }

    if (peerInfo != NULL)
    {
        CFRelease(peerInfo);
    }

    if (peerCode != NULL)
    {
        CFRelease(peerCode);
    }

    return result;
}

int xipc_send_data(xipc_t* ipc, const void* data, int len)
{
    if (ipc == NULL || data == NULL || len <= 0)
    {
        return -1;
    }

    if (xipc_load_closed(ipc) != 0)
    {
        return -1;
    }
    
    xipc_msg_t* msg = (xipc_msg_t*)malloc(sizeof(xipc_msg_t) + len + sizeof(int));
    if (msg == NULL)
    {
        return -1;
    }
    
    msg->num_send = 0;
    msg->next = NULL;
    msg->len = len + sizeof(int);
    
    // header + body
    memcpy(msg->data, &len, sizeof(int));
    memcpy(msg->data + sizeof(int), data, len);
    
    pthread_mutex_lock(&ipc->lock);

    if (xipc_load_closed(ipc) != 0)
    {
        pthread_mutex_unlock(&ipc->lock);
        free(msg);
        return -1;
    }

    if (ipc->out_msgs == NULL)
    {
        ipc->out_msgs = msg;
        ipc->out_msgs_end = msg;
    }
    else
    {
        ipc->out_msgs_end->next = msg;
        ipc->out_msgs_end = msg;
    }
    
    pthread_mutex_unlock(&ipc->lock);
    
    // Wake the I/O thread. A full non-blocking pipe already represents a wakeup.
    xipc_wake(ipc);
    
    return len;
}

void xipc_loop(xipc_t* ipc)
{
    struct pollfd fds[MAX_POLL_FDS];
    xipc_t* ipc_map[MAX_POLL_FDS];
    
    int numFds = 0;
    int numFdsHandled = 0;
    
    while (xipc_load_closed(ipc) == 0)
    {
        numFds = 0;
        numFdsHandled = 0;
                
        // The I/O thread is the sole owner of the client list. Each queue is
        // inspected under that client's own lock in prepare_wait_poll().
        prepare_wait_poll(&numFds, fds, ipc_map, ipc);
        
        xipc_t* current = ipc->next;
        
        while (current != NULL)
        {
            prepare_wait_poll(&numFds, fds, ipc_map, current);

            current = current->next;
        }
        
        if (poll(fds, numFds, -1) < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            
            break;
        }
        
        while (numFdsHandled < numFds)
        {
            xipc_t* client = ipc_map[numFdsHandled];
            struct pollfd* fdinfo = &fds[numFdsHandled];
            
            if (client == NULL)
            {
                // wakeup pipe
                numFdsHandled++;
                
                client = ipc_map[numFdsHandled];
                fdinfo = &fds[numFdsHandled];
                
                xipc_drain_wakeup(client);
                
                fdinfo->revents |= POLLOUT;
            }
            
            if (fdinfo->revents & (POLLERR | POLLHUP | POLLNVAL))
            {
                xipc_store_closed(client, 1);
            }

            // socket
            if (fdinfo->revents & POLLIN)
            {
                if (ipc->isServer != 0 && client->fd == ipc->fd)
                {
                    // accept new client
                    accept_new_client(ipc);
                }
                else
                {
                    int needClose = 0;
                    if (recv_data_from_client(ipc, client, &needClose) != 0)
                    {
                        xipc_store_closed(client, 1);
                    }
                    
                    if (needClose != 0)
                    {
                        xipc_store_closed(client, 1);
                    }
                }
            }
            
            if (xipc_load_closed(client) == 0 && fdinfo->revents & POLLOUT)
            {
                int needClose = 0;
                send_data_to_client(client, &needClose);
                
                if (needClose != 0)
                {
                    xipc_store_closed(client, 1);
                }
            }
            
            if (xipc_load_closed(client) != 0)
            {
                if (client->isServer == 0 && ipc->on_client_disconnected)
                    ipc->on_client_disconnected(ipc, client);
                
                if (ipc->isServer == 1 && client->isServer == 0)
                {
                    remove_at_clients_list(ipc, client);
                    xipc_destroy(client);
                }
                else
                {
                    goto escapeArea;
                }
                
            }
            
            numFdsHandled++;
        }
    }
    
escapeArea:
    return;
}

void xipc_loop_once(xipc_t* ipc) {
    struct pollfd fds[MAX_POLL_FDS];
    xipc_t* ipc_map[MAX_POLL_FDS];
    
    int numFds = 0;
    int numFdsHandled = 0;
    
    // The I/O thread is the sole owner of the client list. Each queue is
    // inspected under that client's own lock in prepare_wait_poll().
    prepare_wait_poll(&numFds, fds, ipc_map, ipc);
    
    xipc_t* current = ipc->next;
    
    while (current != NULL)
    {
        prepare_wait_poll(&numFds, fds, ipc_map, current);
        
        current = current->next;
    }
    
    if (poll(fds, numFds, 0) < 0)
    {
        return;
    }
    
    while (numFdsHandled < numFds)
    {
        xipc_t* client = ipc_map[numFdsHandled];
        struct pollfd* fdinfo = &fds[numFdsHandled];
        
        if (client == NULL)
        {
            // wakeup pipe
            numFdsHandled++;
            
            client = ipc_map[numFdsHandled];
            fdinfo = &fds[numFdsHandled];
            
            xipc_drain_wakeup(client);
            
            fdinfo->revents |= POLLOUT;
        }
        
        if (fdinfo->revents & (POLLERR | POLLHUP | POLLNVAL))
        {
            xipc_store_closed(client, 1);
        }

        // socket
        if (fdinfo->revents & POLLIN)
        {
            if (ipc->isServer != 0 && client->fd == ipc->fd)
            {
                // accept new client
                accept_new_client(ipc);
            }
            else
            {
                int needClose = 0;
                if (recv_data_from_client(ipc, client, &needClose) != 0)
                {
                    xipc_store_closed(client, 1);
                }
                
                if (needClose != 0)
                {
                    xipc_store_closed(client, 1);
                }
            }
        }
        
        if (xipc_load_closed(client) == 0 && fdinfo->revents & POLLOUT)
        {
            int needClose = 0;
            send_data_to_client(client, &needClose);
            
            if (needClose != 0)
            {
                xipc_store_closed(client, 1);
            }
        }
        
        if (xipc_load_closed(client) != 0)
        {
            if (client->isServer == 0 && ipc->on_client_disconnected)
                ipc->on_client_disconnected(ipc, client);
            
            if (ipc->isServer == 1 && client->isServer == 0)
            {
                remove_at_clients_list(ipc, client);
                xipc_destroy(client);
            }
            else
            {
                goto escapeArea;
            }
            
        }
        
        numFdsHandled++;
    }
    
escapeArea:
    return;
}

void xipc_close(xipc_t* ipc) {
    if (ipc == NULL) {
        return;
    }

    xipc_store_closed(ipc, 1);

    pthread_mutex_lock(&ipc->lock);
    xipc_msg_t* messages = ipc->out_msgs;
    ipc->out_msgs = NULL;
    ipc->out_msgs_end = NULL;
    pthread_mutex_unlock(&ipc->lock);

    while (messages != NULL) {
        xipc_msg_t* next = messages->next;
        free(messages);
        messages = next;
    }

    xipc_wake(ipc);
}

int xipc_is_closed(const xipc_t* ipc) {
    return ipc == NULL ? 1 : xipc_load_closed(ipc);
}

void xipc_end_loop(xipc_t* ipc) {
    xipc_close(ipc);
}


int send_data_to_client(xipc_t* client, int* needClose)
{
    if (client == NULL)
    {
        return -1;
    }
    
    // send queued data
    pthread_mutex_lock(&client->lock);
    
    while (client->out_msgs != NULL)
    {
        int error = write_data_to_socket(client, client->out_msgs);
        if (error == 0)
        {
            if (client->out_msgs->num_send >= client->out_msgs->len)
            {
                xipc_msg_t* tmp = client->out_msgs;
                client->out_msgs = client->out_msgs->next;
                
                if (client->out_msgs == NULL)
                {
                    client->out_msgs_end = NULL;
                }
                
                free(tmp);
            }
        }
        else
        {
            if (error != EAGAIN)
            {
                *needClose = 1;
            }
            
            break;
        }
    }

    pthread_mutex_unlock(&client->lock);
    return 0;
}

int write_data_to_socket(xipc_t* client, xipc_msg_t* msg)
{
    int numWrite = (int)write(client->fd, msg->data + msg->num_send, msg->len - msg->num_send);
    if (numWrite < 0)
    {
        return errno;
    }
    
    msg->num_send += numWrite;
    return 0;
}

int recv_data_from_client(xipc_t* ipc, xipc_t* client, int* needClose)
{
    if (client == NULL)
    {
        return -1;
    }
    
    if (client->expected_len == 0)
    {
        // read header
        if (read_header_from_socket(client, needClose) != 0)
        {
            return 0;
        }
        
        if (client->in_len >= (int)sizeof(int))
        {
            int expected_len = *(int*)&client->in_buf;
            if (expected_len <= 0 || expected_len >= MAX_BUFFER)
            {
                *needClose = 1;
                return 0;
            }
            
            client->expected_len = expected_len;
            client->in_len = 0;
        }
        else
        {
            return 0;
        }
    }
    
    // read body
    while (client->in_len < client->expected_len)
    {
        if (read_data_from_socket(client, needClose) != 0)
        {
            return 0;
        }
        
        if (*needClose == 1)
        {
            return 0;
        }
    }
    
    // if receive all -> call cb
    if (ipc->on_data)
        ipc->on_data(ipc, client, client->in_buf, client->in_len);
    
    client->in_len = 0;
    client->expected_len = 0;
    
    return 0;
}

int read_header_from_socket(xipc_t* client, int* needClose)
{
    int numRead = (int)read(client->fd, client->in_buf + client->in_len, sizeof(int) - client->in_len);
    if (numRead < 0)
    {
        if (errno != EAGAIN)
        {
            *needClose = 1;
        }
        
        return errno;
    }
    else if (numRead == 0)
    {
        *needClose = 1;
        return 1;
    }
    
    client->in_len += numRead;
    
    return 0;
}

int read_data_from_socket(xipc_t* client, int* needClose)
{
    int numRead = (int)read(client->fd, client->in_buf + client->in_len, client->expected_len - client->in_len);
    if (numRead < 0)
    {
        if (errno != EAGAIN)
        {
            *needClose = 1;
        }
        
        return errno;
    }
    else if (numRead == 0)
    {
        *needClose = 1;
        return 1;
    }
    
    client->in_len += numRead;
    
    return 0;
}

void prepare_wait_poll(int* currentIndex, struct pollfd* fds, xipc_t** ipcs, xipc_t* ipc)
{
    if (*currentIndex + 1 >= MAX_POLL_FDS)
    {
        return;
    }
    
    // wakeup pipe
    fds[*currentIndex].fd = ipc->wakeup_pipe[0];
    fds[*currentIndex].events = POLLIN;
    fds[*currentIndex].revents = 0;
    ipcs[*currentIndex] = NULL;
    (*currentIndex)++;
    
    // socket
    fds[*currentIndex].fd = ipc->fd;
    fds[*currentIndex].events = POLLIN;
    pthread_mutex_lock(&ipc->lock);
    int hasMessages = ipc->out_msgs != NULL;
    pthread_mutex_unlock(&ipc->lock);
    if (hasMessages)
    {
        fds[*currentIndex].events |= POLLOUT;
    }
    fds[*currentIndex].revents = 0;
    ipcs[*currentIndex] = ipc;
    (*currentIndex)++;
}

int accept_new_client(xipc_t* ipc)
{
    int clientFd = accept(ipc->fd, NULL, NULL);
    if (clientFd >= 0)
    {
        int clientCount = 0;
        for (xipc_t* current = ipc->next; current != NULL; current = current->next)
        {
            clientCount++;
        }
        if (!xipc_can_accept_client_count(clientCount))
        {
            close(clientFd);
            return EMFILE;
        }

        // add client
        xipc_t* client = xipc_ctx_create(ipc->on_data, NULL);
        if (client != NULL)
        {
            client->fd = clientFd;
            set_nonBlocking(client->fd);

            if (ipc->on_client_authorize != NULL && ipc->on_client_authorize(ipc, client) != 0)
            {
                if (ipc->on_client_rejected != NULL)
                {
                    ipc->on_client_rejected(ipc, client);
                }

                xipc_destroy(client);
                return 0;
            }
            
            if (ipc->next == NULL)
            {
                ipc->next = client;
            }
            else
            {
                xipc_t* tmp = ipc->next;
                
                while (tmp->next != NULL)
                {
                    tmp = tmp->next;
                }
                
                tmp->next = client;
            }
            
            if (ipc->on_client_connected)
                ipc->on_client_connected(ipc, client);
        }
        else
        {
            close(clientFd);
        }
    }
    
    return 0;
}
