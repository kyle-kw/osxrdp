
#include "MultipleConnectionManager.h"

MultipleConnectionManager::MultipleConnectionManager() :
    _CurrentConnected(NULL)
{
    pthread_mutex_init(&_lock, NULL);
}

MultipleConnectionManager::~MultipleConnectionManager() {
    pthread_mutex_destroy(&_lock);
}

bool MultipleConnectionManager::AddConnection(struct mod* mod) {
    if (mod == NULL) {
        return false;
    }

    pthread_mutex_lock(&_lock);

    if (_CurrentConnected == mod) {
        pthread_mutex_unlock(&_lock);
        return true;
    }

    if (_CurrentConnected == NULL) {
        _CurrentConnected = mod;
        pthread_mutex_unlock(&_lock);
        return true;
    }
    else {
        _CurrentConnected->connectionManager->Terminate();
    }

    pthread_mutex_unlock(&_lock);

    // Wait for the previous owner to exit (RemoveConnection clears the slot).
    for (int i = 0; i < 10; i++) {
        pthread_mutex_lock(&_lock);
        if (_CurrentConnected == NULL) {
            _CurrentConnected = mod;
            pthread_mutex_unlock(&_lock);
            return true;
        }
        pthread_mutex_unlock(&_lock);
        sleep(1);
    }

    return false;
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
