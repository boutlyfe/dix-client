#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include "resource.h"
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  core_job_ = CreateJobObjectW(nullptr, nullptr);
  if (core_job_) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(core_job_, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
      CloseHandle(core_job_);
      core_job_ = nullptr;
    }
  }
  system_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.dix/windows",
      &flutter::StandardMethodCodec::GetInstance());
  system_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "windowState") {
      RECT window_rect{};
      POINT client_origin{0, 0};
      GetWindowRect(GetHandle(), &window_rect);
      ClientToScreen(GetHandle(), &client_origin);
      const LONG inset = client_origin.y - window_rect.top;
      const LONG border = GetSystemMetrics(SM_CYSIZEFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER) + 2;
      flutter::EncodableMap state{
        {flutter::EncodableValue("nativeCaptionHidden"), flutter::EncodableValue(inset <= border)},
        {flutter::EncodableValue("trayEnabled"), flutter::EncodableValue(tray_enabled_)},
        {flutter::EncodableValue("visible"), flutter::EncodableValue(IsWindowVisible(GetHandle()) != FALSE)},
        {flutter::EncodableValue("clientTopInset"), flutter::EncodableValue(static_cast<int32_t>(inset))}
      };
      result->Success(flutter::EncodableValue(state)); return;
    }
    if (call.method_name() == "showWindow") {
      // Consume STARTUPINFO's initial SW_HIDE as well as normal tray restore.
      const int state = IsIconic(GetHandle()) ? SW_RESTORE : SW_SHOW;
      ::ShowWindow(GetHandle(), state);
      ::ShowWindow(GetHandle(), state);
      ::SetWindowPos(GetHandle(), HWND_TOP, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
      SetForegroundWindow(GetHandle());
      result->Success(flutter::EncodableValue(IsWindowVisible(GetHandle()) != FALSE)); return;
    }
    if (call.method_name() == "setTrayEnabled") {
      const auto* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      result->Success(flutter::EncodableValue(SetTrayEnabled(value && *value))); return;
    }
    if (call.method_name() == "openReleaseUrl") {
      const auto* value = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!value || value->rfind("https://github.com/", 0) != 0) {
        result->Error("invalid_url", "Expected GitHub HTTPS release URL"); return;
      }
      const std::wstring url(value->begin(), value->end());
      const auto launched = reinterpret_cast<INT_PTR>(ShellExecuteW(GetHandle(), L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      result->Success(flutter::EncodableValue(launched > 32)); return;
    }
    if (call.method_name() != "attachCore") { result->NotImplemented(); return; }
    const auto* arg = call.arguments();
    int64_t pid = 0;
    if (arg) {
      if (const auto* value = std::get_if<int32_t>(arg)) pid = *value;
      if (const auto* value = std::get_if<int64_t>(arg)) pid = *value;
    }
    if (!core_job_ || pid <= 0 || pid == GetCurrentProcessId()) {
      result->Error("invalid_core", "Cannot supervise core process"); return;
    }
    HANDLE process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, static_cast<DWORD>(pid));
    const bool assigned = process && AssignProcessToJobObject(core_job_, process);
    if (process) CloseHandle(process);
    if (!assigned) { result->Error("core_job", "Cannot assign core process to Windows job"); return; }
    result->Success(flutter::EncodableValue(true));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Dart owns initial visibility so hidden startup never flashes a window.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  SetTrayEnabled(false);
  system_channel_.reset();
  if (core_job_) { CloseHandle(core_job_); core_job_ = nullptr; }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  static const UINT taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  if (message == taskbar_created && tray_enabled_) {
    tray_enabled_ = false; SetTrayEnabled(true); return 0;
  }
  if (message == WM_APP + 0xD17) {
    const UINT action = LOWORD(lparam);
    if (action == WM_LBUTTONUP || action == NIN_SELECT || action == NIN_KEYSELECT) {
      TrayAction("open");
    } else if (action == WM_CONTEXTMENU || action == WM_RBUTTONUP) {
      POINT position{}; GetCursorPos(&position);
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, 1, L"Открыть Dix");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, 2, L"Выйти из Dix");
      SetForegroundWindow(hwnd);
      const UINT selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
          position.x, position.y, 0, hwnd, nullptr);
      DestroyMenu(menu); PostMessageW(hwnd, WM_NULL, 0, 0);
      if (selected == 1) TrayAction("open");
      if (selected == 2) TrayAction("quit");
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::SetTrayEnabled(bool enabled) {
  if (enabled == tray_enabled_) return true;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon); icon.hWnd = tray_window_ ? tray_window_ : GetHandle(); icon.uID = 1;
  if (!enabled) {
    Shell_NotifyIconW(NIM_DELETE, &icon); tray_enabled_ = false; return true;
  }
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon.uCallbackMessage = WM_APP + 0xD17;
  icon.hIcon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(icon.szTip, L"Dix");
  if (!Shell_NotifyIconW(NIM_ADD, &icon)) return false;
  icon.uVersion = NOTIFYICON_VERSION_4; Shell_NotifyIconW(NIM_SETVERSION, &icon);
  tray_window_ = GetHandle(); tray_enabled_ = true; return true;
}

void FlutterWindow::TrayAction(const char* action) {
  if (system_channel_) system_channel_->InvokeMethod("trayAction",
      std::make_unique<flutter::EncodableValue>(std::string(action)));
}
