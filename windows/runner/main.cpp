#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // A separate Flutter mutex prevents competing local cores/proxy leases.
  HANDLE instance_mutex = nullptr;
  const std::wstring args(command_line);
  const bool isolated_check = args.find(L"--self-test-core") != std::wstring::npos ||
      args.find(L"--self-test-startup") != std::wstring::npos ||
      args.find(L"--self-test-delay") != std::wstring::npos ||
      args.find(L"--self-test-lifecycle") != std::wstring::npos;
  if (!isolated_check) {
    instance_mutex = CreateMutexW(nullptr, TRUE, L"Local\\DixFlutterWindowsClient");
    const bool existing = GetLastError() == ERROR_ALREADY_EXISTS;
    if (!instance_mutex) return EXIT_FAILURE;
    if (existing) {
      const bool restarting = std::wstring(command_line).find(L"--restarted-elevated") != std::wstring::npos;
      const DWORD acquired = restarting ? WaitForSingleObject(instance_mutex, 10000) : WAIT_TIMEOUT;
      if (acquired != WAIT_OBJECT_0 && acquired != WAIT_ABANDONED) {
        CloseHandle(instance_mutex);
        HWND existing_window = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Dix");
        if (existing_window) {
          ShowWindow(existing_window, SW_RESTORE);
          SetForegroundWindow(existing_window);
        }
        return EXIT_SUCCESS;
      }
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Dix", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) { ReleaseMutex(instance_mutex); CloseHandle(instance_mutex); }
  return EXIT_SUCCESS;
}
