#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// Clipboard channel headers
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <vector>

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

  // --- CLIPBOARD IMAGE NATIVE CHANNEL ---
  auto& codec = flutter::StandardMethodCodec::GetInstance();
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.example.app/clipboard",
          &codec);

  clipboard_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        
        if (call.method_name() == "getClipboardImage") {
          std::vector<uint8_t> imageBytes;
          
          if (OpenClipboard(nullptr)) {
            // Try CF_DIB first (screenshots, Snipping Tool, etc.)
            if (IsClipboardFormatAvailable(CF_DIB)) {
              HANDLE hClipboard = GetClipboardData(CF_DIB);
              if (hClipboard) {
                BITMAPINFO* bmi = (BITMAPINFO*)GlobalLock(hClipboard);
                if (bmi) {
                  // Calculate sizes
                  DWORD headerSize = sizeof(BITMAPINFOHEADER);
                  if (bmi->bmiHeader.biBitCount <= 8) {
                    headerSize += (1ULL << bmi->bmiHeader.biBitCount) * sizeof(RGBQUAD);
                  }
                  
                  DWORD imageSize = bmi->bmiHeader.biSizeImage;
                  if (imageSize == 0) {
                    imageSize = ((bmi->bmiHeader.biWidth * bmi->bmiHeader.biBitCount + 31) / 32) * 4 * abs(bmi->bmiHeader.biHeight);
                  }

                  DWORD totalSize = sizeof(BITMAPFILEHEADER) + headerSize + imageSize;
                  imageBytes.resize(totalSize);

                  // Construct valid BMP file bytes
                  BITMAPFILEHEADER* bfh = (BITMAPFILEHEADER*)imageBytes.data();
                  bfh->bfType = 0x4D42; // 'BM'
                  bfh->bfSize = totalSize;
                  bfh->bfReserved1 = 0;
                  bfh->bfReserved2 = 0;
                  bfh->bfOffBits = sizeof(BITMAPFILEHEADER) + headerSize;

                  memcpy(imageBytes.data() + sizeof(BITMAPFILEHEADER), bmi, headerSize + imageSize);
                  
                  GlobalUnlock(hClipboard);
                }
              }
            }
            
            // If no DIB, try CF_HDROP (files copied from Explorer)
            if (imageBytes.empty() && IsClipboardFormatAvailable(CF_HDROP)) {
              HANDLE hDrop = GetClipboardData(CF_HDROP);
              if (hDrop) {
                HDROP hdDrop = static_cast<HDROP>(hDrop);
                UINT fileCount = DragQueryFile(hdDrop, 0xFFFFFFFF, nullptr, 0);
                if (fileCount > 0) {
                  wchar_t filePath[MAX_PATH];
                  if (DragQueryFile(hdDrop, 0, filePath, MAX_PATH) > 0) {
                    // Check if it's an image file by extension
                    std::wstring wsPath(filePath);
                    std::wstring ext = wsPath.substr(wsPath.find_last_of(L'.') + 1);
                    // Convert to lowercase for comparison
                    for (size_t i = 0; i < ext.size(); i++) {
                      ext[i] = static_cast<wchar_t>(towlower(ext[i]));
                    }
                    
                    if (ext == L"png" || ext == L"jpg" || ext == L"jpeg" || 
                        ext == L"gif" || ext == L"bmp" || ext == L"webp") {
                      // Read the file from disk
                      HANDLE hFile = CreateFileW(filePath, GENERIC_READ, FILE_SHARE_READ,
                                                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
                      if (hFile != INVALID_HANDLE_VALUE) {
                        DWORD fileSize = GetFileSize(hFile, nullptr);
                        if (fileSize > 0) {
                          imageBytes.resize(fileSize);
                          DWORD bytesRead;
                          ReadFile(hFile, imageBytes.data(), fileSize, &bytesRead, nullptr);
                        }
                        CloseHandle(hFile);
                      }
                    }
                  }
                }
              }
            }
            
            CloseClipboard();
          }

          if (!imageBytes.empty()) {
            result->Success(flutter::EncodableValue(imageBytes));
          } else {
            result->Success(flutter::EncodableValue()); // Return null if no image
          }
        } else {
          result->NotImplemented();
        }
      });
  // --------------------------------------

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}