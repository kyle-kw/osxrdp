
#ifndef MultipleConnectionManager_h
#define MultipleConnectionManager_h

#include "../osxup.h"
#include <pthread.h>

class MultipleConnectionManager {
    
public:
    MultipleConnectionManager();
    ~MultipleConnectionManager();
    
    void AddConnection(struct mod* mod);
    // Only clears the slot when the exiting mod still owns it.
    void RemoveConnection(struct mod* mod);
    
private:
    struct mod* _CurrentConnected;
    
    pthread_mutex_t _lock;
};

#endif /* MultipleConnectionManager_h */
