
#ifndef utils_h
#define utils_h

#include <sys/types.h>

#ifndef LOWORD
#define LOWORD(l) ((unsigned short)((l) & 0xffff))
#endif

#ifndef HIWORD
#define HIWORD(l) ((unsigned short)(((l) >> 16) & 0xffff))
#endif

#ifdef __cplusplus
extern "C" {
#endif

//int get_object_name_by_username(const char* prefix, char* buffer, int cchMax);

//int get_object_name(const char* username, const char* prefix, char* buffer, int cchMax);
int get_object_name_by_sessionid(const char* prefix, char* buffer, int cchMax, int isLockscreen);
int get_current_session_id(void);

int get_object_name(int sessionid, const char* prefix, char* buffer, int cchMax, int isLockscreen);

int osxrdp_get_sessionmanager_socket_path(char* buffer, int cchMax);
int osxrdp_get_agent_socket_directory(uid_t uid, char* buffer, int cchMax);
int osxrdp_get_agent_socket_path(uid_t uid, int sessionid, char* buffer, int cchMax, int isLockscreen);
int osxrdp_validate_utf8_username(const char* username, int usernameLen);

int is_root_process(void);

#ifdef __cplusplus
}
#endif

#endif /* utils_h */
