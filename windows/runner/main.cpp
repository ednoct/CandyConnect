#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

/// تنظیم دایرکتوری کاری پروسه به پوشه فایل اجرایی.
/// این کار در زمان ارتقای دسترسی UAC (runas) که ویندوز دایرکتوری کاری را به System32 تغییر می‌دهد،
/// برای پیدا شدن پوشه data و فایل‌های libXray.dll / wintun.dll / WinDivert.dll حیاتی است.
void PinWorkingDirectoryToExecutableDir() {
  wchar_t exe_path[MAX_PATH] = {0};
  DWORD len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return;
  }

  std::wstring path_str(exe_path, len);
  size_t last_slash = path_str.find_last_of(L"\\/");
  if (last_slash != std::wstring::npos) {
    std::wstring exe_dir = path_str.substr(0, last_slash);
    ::SetCurrentDirectoryW(exe_dir.c_str());
    ::SetDllDirectoryW(exe_dir.c_str());
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance,
                      _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line,
                      _In_ int show_command) {
  (void)instance;
  (void)prev;
  (void)command_line;
  (void)show_command;

  PinWorkingDirectoryToExecutableDir();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // ابعاد دقیق 400x800 هماهنگ با DesktopManager جهت جلوگیری از پرش ابعاد پنجره در استارت‌آپ
  Win32Window::Point origin(100, 100);
  Win32Window::Size size(400, 800);
  if (!window.Create(L"CandyConnect", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}