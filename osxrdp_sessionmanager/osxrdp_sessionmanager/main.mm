//
//  main.m
//  osxrdp_sessionmanager
//
//  Created by byungho on 1/24/26.
//

#include "pch.h"
#include "utils.h"
#include "duprun.h"
#include <sys/stat.h>
#include <signal.h>
#include <pthread.h>

#import "sessionmanager/sessionmanagerserver.h"

#define _LOG_CONFIG_PATH "/etc/osxrdp/log_sessionmanager.conf"

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;

    sigset_t shutdownSignals;
    sigemptyset(&shutdownSignals);
    sigaddset(&shutdownSignals, SIGTERM);
    sigaddset(&shutdownSignals, SIGINT);
    if (pthread_sigmask(SIG_BLOCK, &shutdownSignals, NULL) != 0) {
        return EXIT_FAILURE;
    }
    
    // All files under /Library/Logs disappear on OS update.... what?
    mkdir("/Library/Logs/osxrdp", 0755);
    
    // initialize log (non-fatal: still run so IPC stays available if log path is broken)
    int re = dzlog_init(_LOG_CONFIG_PATH, "osxrdp_sessionmanager");
    if (re != 0) {
        NSLog(@"[osxrdp_sessionmanager] could not initialize log. %s (continuing without file log)", _LOG_CONFIG_PATH);
    }
    
    // check is root process
    if (is_root_process() == 0) {
        NSLog(@"[osxrdp_sessionmanager] osxrdp sessionmanager must run as root.");
        dzlog_error("[osxrdp_sessionmanager] osxrdp sessionmanager must run as root.");
        
        if (re == 0) {
            zlog_fini();
        }
        return EXIT_FAILURE;
    }
    
    // Check for duplicate execution
    duprun* dup = duprun_initialize("com.byungho.osxrdp.sessionmanager");
    if (dup == NULL) {
        NSLog(@"[osxrdp_sessionmanager] program already running.");
        dzlog_error("[osxrdp_sessionmanager] program already running.");
        
        if (re == 0) {
            zlog_fini();
        }
        return EXIT_FAILURE;
    }
    
    dzlog_info("[osxrdp_sessionmanager] --- osxrdp sessionmanager started! ---");
    dzlog_info("[osxrdp_sessionmanager] created by kyle - https://github.com/kyle-kw/osxrdp");
    
    SessionManagerServer server;
    
    if (!server.Start()) {
        duprun_release(dup);
        if (re == 0) {
            zlog_fini();
        }
        return EXIT_FAILURE;
    }

    int receivedSignal = 0;
    int exitStatus = EXIT_SUCCESS;
    if (sigwait(&shutdownSignals, &receivedSignal) != 0) {
        dzlog_error("[osxrdp_sessionmanager] sigwait failed");
        exitStatus = EXIT_FAILURE;
    }
    
    server.Stop();
    
    duprun_release(dup);
    dup = NULL;
    
    dzlog_info("[osxrdp_sessionmanager] --- osxrdp sessionmanager ended ---");
    if (re == 0) {
        zlog_fini();
    }
    
    return exitStatus;
}
