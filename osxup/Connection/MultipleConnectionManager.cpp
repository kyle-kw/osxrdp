
#include "MultipleConnectionManager.h"

MultipleConnectionManager::MultipleConnectionManager() :
    _CurrentConnected(NULL)
{
    pthread_mutex_init(&_lock, NULL);
}

MultipleConnectionManager::~MultipleConnectionManager() {
    pthread_mutex_destroy(&_lock);
}

void MultipleConnectionManager::AddConnection(struct mod* mod) {
    if (mod == NULL) {
        return;
    }

    pthread_mutex_lock(&_lock);

    if (_CurrentConnected == mod) {
        pthread_mutex_unlock(&_lock);
        return;
    }

    if (_CurrentConnected != NULL) {
        _CurrentConnected->connectionManager->Terminate();
    }

    pthread_mutex_unlock(&_lock);

    // Wait for the previous owner to exit (RemoveConnection clears the slot).
    for (int i = 0; i < 10; i++) {
        pthread_mutex_lock(&_lock);
        if (_CurrentConnected == NULL) {
            _CurrentConnected = mod;
            pthread_mutex_unlock(&_lock);
            return;
        }
        pthread_mutex_unlock(&_lock);
        sleep(1);
    }

    // Timed out: take ownership anyway. RemoveConnection(mod) only clears when
    // the exiting session still owns the slot, so a late previous exit is safe.
    pthread_mutex_lock(&_lock);
    if (_CurrentConnected != NULL && _CurrentConnected != mod) {
        _CurrentConnected->connectionManager->Terminate();
    }
    _CurrentConnected = mod;
    pthread_mutex_unlock(&_lock);
}

void MultipleConnectionManager::RemoveConnection(struct mod* mod) {
    if (mod == NULL) {
        return;
    }

    pthread_mutex_lock(&_lock);
    if (_CurrentConnected == mod) {
        _CurrentConnected = NULL;
    }
    pthread_mutex_unlock(&_lock);
}
