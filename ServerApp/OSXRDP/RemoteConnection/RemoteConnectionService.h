#ifndef RemoteConnectionService_h
#define RemoteConnectionService_h

bool StartRemoteConnectionServerService(void);
void StopRemoteConnectionServerService(void);
bool IsRemoteConnectionServerServiceRunning(void);
bool IsRemoteRdpClientConnected(void);
bool HasRemoteClipboardFiles(void);
int GetRemoteClipboardFileCount(void);
void StartRemoteClipboardFileCopy(void);
void StartRemoteClipboardFileCopyToDownloads(void);

#endif
