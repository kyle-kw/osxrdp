
#ifndef ScreenRecorder_hpp
#define ScreenRecorder_hpp

#include "ipc.h"
#include "xstream.h"
#include "xshm.h"
#include "InputHandler.h"
#include "CursorHandler.h"
#include "../VirtualMon/VirtualMonitor.h"
#include "osxrdp/screenrecordshm.h"
#include "osxrdp/stream_policy.h"
#include <atomic>
#include "H264VideoToolboxEncoder.h"

class ScreenRecorderManager {
    
public:
    ScreenRecorderManager(bool useLegacyRecorder);
    ~ScreenRecorderManager();
        
    void HandleCommand(xipc_t* client, xstream_t* cmd);
    void Stop();
    void DetachClient(xipc_t* client);
    void SendDisconnectMsgToClient();

private:
    // recording request parameters
    struct RecordStartParams {
        int monitorIndex;
        int width;
        int height;
        int framerate;
        int recordFormat;
        int useVirtualMon;
        int monitorCount;
        int policyVersion;
        int preset;
        osxrdp_stream_policy_t policy;
        
        struct MONITOR_INFO {
            int left;
            int top;
            int right;
            int bottom;
            int is_primary;
            int displayId;
            int outputIndex;
        } monitorInfo[16];
    };
    
    struct RecordStartParams _recordParams;

    void* _recorder[16];
    int _recorderCnt;
    // Per-recording callback context. It is detached before SHM teardown so
    // callbacks arriving after stop cannot dereference this manager.
    void* _callbackContext;
    
    bool _useLegacyRecorder;
    
    // shared memory where recording data is stored
    xshm_t* _recordShm[16];
    int _recordShmCnt;
    
    // shared memory where cursor image is stored
    xshm_t* _cursorShm;
    
    // pipe to send commands to osxup
    std::atomic<xipc_t*> _client;
    
    // Input handler (mouse, keyboard)
    InputHandler _inputHandler;
    
    // Mouse cursor handler
    CursorHandler _cursorHandler;
    
    VirtualMonitor _virtualMonitor;

    // RFX YUV444 canonical buffer - accumulates only converted dirty tiles, then packs only those tiles into SHM slot
    // (indices + tileData) for output.
    uint8_t* _rfxCanonical;
    size_t   _rfxCanonicalSize;
    int      _rfxCanonicalWidth;
    int      _rfxCanonicalHeight;
    size_t   _rfxTileCols;
    size_t   _rfxTileRows;
    
    // flag indicating whether next frame should be full redraw.
    bool     _rfxFullRedrawRequired;
    dispatch_queue_t _rfxConvertQueue;

    screenrecord_frame_t _pendingDirty[16];
    bool _pendingDirtyFull[16];
    int _lastScreenError;
    bool _forceFullFrame[16];
    H264VideoToolboxEncoder* _h264Encoder[16];
    int _h264EncoderFailures[16];
    bool _runtimeFailureNotified;
    bool _preserveMetricsOnNextStop;

    bool CreateRecordShm(int recordIdx);
    void DestroyRecordShm();
    
    bool CreateCursorShm();
    void DestroyCursorShm();
    
    bool StartRecord(xstream_t* cmd);
    bool StartRecordWithParams();
    // Dynamic resize. After any path that destroys+recreates SHM, returns true with
    // the dimensions actually running so osxup reopens SHM (re=1 wire contract).
    bool HandleScreenResize(xipc_t* client, xstream_t* cmd);
    
    bool ParseStartRecordParams(xstream_t* cmd, RecordStartParams* params);
    bool PrepareRecordResources();
    
    // recorder configuration
    bool ResolveDisplayForRecorder();
    int GetMonitorRecordWidth(int recordIdx);
    int GetMonitorRecordHeight(int recordIdx);

    // recording data handlers
    static void HandleBGRA32RecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static bool HandleBGRA32DirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data, size_t slotCapacity);
    
    static void HandleNV12PackedRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static bool HandleNV12PackedDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data, size_t slotCapacity);
    
    static void HandleNV12AlignedRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static bool HandleNV12AlignedDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data, size_t slotCapacity);

    static void HandleH264AnnexBRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    bool RecreateH264Encoder(int displayIdx);
    void SendEncoderRuntimeFailure();
    
    static void HandleRFXRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    bool HandleRFXDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data, size_t slotCapacity, int displayIdx);
    
    // find a slot to write data
    bool AcquireFrameSlot(screenrecord_shm_t** recordInfoOut, screenrecord_frame** frameOut, char** dataOut, unsigned int* writePosOut, int displayIdx);
    
    // set frame slot commit flag
    void CommitFrameSlot(screenrecord_shm_t* recordInfo, unsigned int writePos, int displayIdx);

    // notify osxup that paint data is available (NEEDPAINT)
    void SendNeedPaintMsg(int displayIdx);

    // write NV12Packed data to memory
    static bool CopyNV12PackedFrame(void* imageBuffer, char* screenrecord_data, size_t slotCapacity, int* widthOut, int* heightOut);
    
    // write NV12Aligned data to memory
    static bool CopyNV12AlignedFrame(void* imageBuffer, char* screenrecord_data, size_t slotCapacity, int* widthOut, int* heightOut);
    
    // write BGRA32 data to memory
    static bool CopyBGRA32Frame(void* imageBuffer, char* screenrecord_data, size_t slotCapacity, int* widthOut, int* heightOut);

    // RFX canonical buffer management and BGRA -> YUV444 tile conversion (dirty areas only)
    bool EnsureRFXCanonical(int width, int height);
    // set flag to force full redraw on next frame
    void InvalidateRFXCanonical();
    void ReleaseRFXCanonical();
    bool ConvertRFXTile(const uint8_t* bgraBase, size_t bgraStride, int width, int height, int tileCol, int tileRow, uint8_t* tileBase);
    
    // dirty area (changed region) processing
    inline static void ProcessDirtyArea(const CGRect* rect, int limitX, int limitY, struct RECT* dst);
    
    void ResetPendingDirty();
    void ResetPendingDirty(int displayIdx);
    void AddPendingDirty(int displayIdx, const CGRect* dirtyRects, int dirtyRectsCnt, int width, int height);
    void AddPendingDirtyFromPixelBuffer(int displayIdx, void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt);
    void ApplyPendingDirty(int displayIdx, screenrecord_frame* current_frame);
    
    static void PopulateDirtyRectsFromSampleBuffer(void* sampleBuffer, int width, int height, screenrecord_frame* current_frame);
    static void PopulateDirtyRectsFromArray(const CGRect* dirtyRects, int dirtyRectsCnt, int width, int height, screenrecord_frame* current_frame);
    
    static void HandleRecordCommand(int cmd, void* userData);
};

#endif /* ScreenRecorder_hpp */
