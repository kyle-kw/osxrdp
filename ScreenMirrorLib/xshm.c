
#include "xshm.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

xshm_t* xshm_create(const char* name, size_t size) {
    if (name == NULL || strlen(name) == 0 || size == 0) {
        return NULL;
    }
    if (strlen(name) >= sizeof(((xshm_t*)0)->name)) {
        return NULL;
    }
    
    // create shared memory
    shm_unlink(name);
    int fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) {
        return NULL;
    }
    
    // set size
    if (ftruncate(fd, (off_t)size) != 0) {
        
        close(fd);
        shm_unlink(name);
        
        return NULL;
    }
    
    // get shm address
    void* addr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) {
        
        close(fd);
        shm_unlink(name);
        
        return NULL;
    }
    
    xshm_t* shm = (xshm_t*)malloc(sizeof(xshm_t));
    if (shm == NULL) {
        munmap(addr, size);
        close(fd);
        shm_unlink(name);
        
        return NULL;
    }
    
    shm->fd = fd;
    shm->size = size;
    shm->owner = 1;
    shm->mem = addr;
    snprintf(shm->name, sizeof(shm->name), "%s", name);
    
    return shm;
}

xshm_t* xshm_open(const char* name) {
    if (name == NULL || strlen(name) == 0) {
        return NULL;
    }
    if (strlen(name) >= sizeof(((xshm_t*)0)->name)) {
        return NULL;
    }
    
    int fd = shm_open(name, O_RDWR, 0600);
    if (fd < 0) {
        return NULL;
    }
    
    struct stat st = {0,};
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        
        close(fd);
        
        return NULL;
    }
    
    void* addr = mmap(NULL, (size_t)st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (addr == MAP_FAILED) {
        close(fd);
        
        return NULL;
    }
    
    xshm_t* shm = (xshm_t*)malloc(sizeof(xshm_t));
    if (shm == NULL) {
        
        munmap(addr, (size_t)st.st_size);
        close(fd);
        
        return NULL;
    }
    
    shm->fd = fd;
    shm->size = (size_t)st.st_size;
    shm->owner = 0;
    shm->mem = addr;
    snprintf(shm->name, sizeof(shm->name), "%s", name);
    
    return shm;
}

int xshm_write(xshm_t* shm, const void* data, int len) {
    if (shm == NULL || data == NULL || len <= 0) return 1;
    if ((size_t)len > shm->size) return 1;
    
    memcpy(shm->mem, data, (size_t)len);
    
    return 0;
}

int xshm_read(xshm_t* shm, void* buffer, int len) {
    if (shm == NULL || buffer == NULL || len <= 0) return 1;
    if ((size_t)len > shm->size) return 1;

    memcpy(buffer, shm->mem, (size_t)len);
    
    return 0;
}

void xshm_close(xshm_t* shm) {
    if (shm == NULL) return;
    
    if (shm->mem) {
        munmap(shm->mem, shm->size);
    }
    
    if (shm->fd >= 0) {
        close(shm->fd);
    }
    
    shm->mem = 0;
    shm->fd = 0;
    shm->size = 0;
}

void xshm_destroy(xshm_t* shm) {
    
    if (shm == NULL) return;
    
    if (shm->owner) {
        shm_unlink(shm->name);
    }
    
    free(shm);
}
