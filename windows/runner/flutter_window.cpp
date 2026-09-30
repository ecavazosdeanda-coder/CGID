#include "flutter_window.h"

#include <optional>
#include "resource.h"

namespace {
void UpdateBranding(HWND window) {
  if (wcsstr(GetCommandLineW(), L"--projection") || wcsstr(GetCommandLineW(), L"--stage")) return;
  SYSTEMTIME now;
  GetLocalTime(&now);
  const auto icon = LoadIcon(GetModuleHandle(nullptr),
      MAKEINTRESOURCE(now.wDayOfWeek == 6 ? IDI_GOLD_ICON : IDI_APP_ICON));
  SendMessage(window, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon));
  SendMessage(window, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon));
}
}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  UpdateBranding(GetHandle());
  SetTimer(GetHandle(), 1001, 60000, nullptr);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), 1001);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_TIMER:
      if (wparam == 1001) UpdateBranding(hwnd);
      break;
    case WM_TIMECHANGE:
      UpdateBranding(hwnd);
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
