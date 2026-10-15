#include <windows.h>
#include <string>
#include <cstdlib>

void RunHeadlessCommand(const char* cmd) {
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    ZeroMemory(&pi, sizeof(pi));

    // CreateProcess needs a modifiable string for the command line
    char cmdBuffer[256];
    strncpy_s(cmdBuffer, cmd, sizeof(cmdBuffer));

    if (CreateProcessA(NULL, cmdBuffer, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd) {
    if (lpCmdLine == nullptr || lpCmdLine[0] == '\0') {
        return 1;
    }

    DWORD parentPid = 0;
    try {
        parentPid = std::stoul(lpCmdLine);
    } catch (...) {
        return 1;
    }

    // 1. Process Monitoring
    HANDLE hProcess = OpenProcess(SYNCHRONIZE, FALSE, parentPid);
    if (hProcess == NULL) {
        return 1;
    }

    // Wait for the parent process to terminate
    WaitForSingleObject(hProcess, INFINITE);
    CloseHandle(hProcess);

    // 2. Clean vs. Violent Exit Detection
    // Check if the mutex exists
    HANDLE hMutex = OpenMutexA(MUTEX_ALL_ACCESS, FALSE, "Global\\CandyConnectCleanExit");
    if (hMutex != NULL) {
        // Mutex exists, so it was a clean exit.
        CloseHandle(hMutex);
        return 0; // Exit silently
    }

    // 3. The Rescue Routine (Violent Kill)
    
    // 3a. Delete routes (run headlessly to avoid console flashes)
    RunHeadlessCommand("route.exe delete 0.0.0.0 mask 128.0.0.0");
    RunHeadlessCommand("route.exe delete 128.0.0.0 mask 128.0.0.0");

    // 3b. WinDivert Cleanup
    SC_HANDLE hSCManager = OpenSCManager(NULL, NULL, SC_MANAGER_ALL_ACCESS);
    if (hSCManager != NULL) {
        SC_HANDLE hService = OpenServiceA(hSCManager, "WinDivert", SERVICE_STOP | DELETE);
        if (hService != NULL) {
            SERVICE_STATUS status;
            // Best effort stop
            ControlService(hService, SERVICE_CONTROL_STOP, &status);
            // Delete service to ensure kernel unloads driver
            DeleteService(hService);
            CloseServiceHandle(hService);
        }
        CloseServiceHandle(hSCManager);
    }

    return 0;
}
