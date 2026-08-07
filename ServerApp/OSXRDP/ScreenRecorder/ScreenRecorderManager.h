
#ifndef ScreenRecorder_hpp
#define ScreenRecorder_hpp

#include "ipc.h"
#include "xstream.h"
#include "xshm.h"
#include "osxrdp/screenrecordshm.h"
#include "InputHandler.h"
#include "CursorHandler.h"
#include "../VirtualMon/VirtualMonitor.h"

class ScreenRecorderManager {
    
public:
    ScreenRecorderManager(bool useLegacyRecorder);
    ~ScreenRecorderManager();
        
    void HandleCommand(xipc_t* client, xstream_t* cmd);
    void Stop();
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
    
    bool _useLegacyRecorder;
    
    // shared memory where recording data is stored
    xshm_t* _recordShm[16];
    int _recordShmCnt;
    
    // shared memory where cursor image is stored
    xshm_t* _cursorShm;
    
    // pipe to send commands to osxup
    xipc_t* _client;
    
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

    screenrecord_frame_t _pendingDirty[16];
    bool _pendingDirtyFull[16];

    bool CreateRecordShm(int recordIdx);
    void DestroyRecordShm();
    
    bool CreateCursorShm();
    void DestroyCursorShm();
    
    bool StartRecord(xstream_t* cmd);
    
    bool ParseStartRecordParams(xstream_t* cmd, RecordStartParams* params);
    bool PrepareRecordResources();
    
    // recorder configuration
    bool ResolveDisplayForRecorder();
    int GetMonitorRecordWidth(int recordIdx);
    int GetMonitorRecordHeight(int recordIdx);

    // recording data handlers
    static void HandleBGRA32RecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static void HandleBGRA32DirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data);
    
    static void HandleNV12PackedRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static void HandleNV12PackedDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data);
    
    static void HandleNV12AlignedRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    static void HandleNV12AlignedDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data);
    
    static void HandleRFXRecordData(void* pixelBuffer, const CGRect* dirtyRects, int dirtyRectsCnt, void* userData, int displayIdx);
    bool HandleRFXDirtyArea(void* pixelBuffer, screenrecord_frame* current_frame, const CGRect* dirtyRects, int dirtyRectsCnt, char* screenrecord_data, int displayIdx);
    
    // find a slot to write data
    bool AcquireFrameSlot(screenrecord_shm_t** recordInfoOut, screenrecord_frame** frameOut, char** dataOut, unsigned int* writePosOut, int displayIdx);
    
    // set frame slot commit flag
    void CommitFrameSlot(screenrecord_shm_t* recordInfo, unsigned int writePos, int displayIdx);

    // notify osxup that paint data is available (NEEDPAINT)
    void SendNeedPaintMsg(int displayIdx);

    // write NV12Packed data to memory
    static bool CopyNV12PackedFrame(void* imageBuffer, char* screenrecord_data, int* widthOut, int* heightOut);
    
    // write NV12Aligned data to memory
    static bool CopyNV12AlignedFrame(void* imageBuffer, char* screenrecord_data, int* widthOut, int* heightOut);
    
    // write BGRA32 data to memory
    static bool CopyBGRA32Frame(void* imageBuffer, char* screenrecord_data, int* widthOut, int* heightOut);

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
