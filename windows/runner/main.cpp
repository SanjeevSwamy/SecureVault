#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include "flutter_window.h"
#include "utils.h"

// Function to register URL scheme
void RegisterUrlScheme() {
    HKEY hKey;
    const wchar_t* keyPath = L"SOFTWARE\\Classes\\securevault";
    
    // Create main key
    if (RegCreateKeyEx(HKEY_CURRENT_USER, keyPath, 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        RegSetValueEx(hKey, NULL, 0, REG_SZ, (BYTE*)L"URL:SecureVault Protocol", sizeof(L"URL:SecureVault Protocol"));
        RegSetValueEx(hKey, L"URL Protocol", 0, REG_SZ, (BYTE*)L"", sizeof(L""));
        RegCloseKey(hKey);
    }
    
    // Create shell/open/command key
    const wchar_t* commandKeyPath = L"SOFTWARE\\Classes\\securevault\\shell\\open\\command";
    if (RegCreateKeyEx(HKEY_CURRENT_USER, commandKeyPath, 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        wchar_t exePath[MAX_PATH];
        GetModuleFileName(NULL, exePath, MAX_PATH);
        
        wchar_t command[MAX_PATH + 20];
        swprintf(command, MAX_PATH + 20, L"\"%s\" \"%%1\"", exePath);
        
        RegSetValueEx(hKey, NULL, 0, REG_SZ, (BYTE*)command, (wcslen(command) + 1) * sizeof(wchar_t));
        RegCloseKey(hKey);
    }
}

// Function to handle command line arguments for deep links
std::vector<std::string> ProcessCommandLineForDeepLinks(const std::vector<std::string>& args) {
    std::vector<std::string> processed_args;
    
    for (const auto& arg : args) {
        if (arg.find("securevault://") == 0) {
            // This is a deep link, pass it to Flutter
            processed_args.push_back("--deep-link");
            processed_args.push_back(arg);
        } else {
            processed_args.push_back(arg);
        }
    }
    
    return processed_args;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register URL scheme for deep links
  RegisterUrlScheme();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  
  // Process command line for deep links
  command_line_arguments = ProcessCommandLineForDeepLinks(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SecureVault", origin, size)) {  // Updated window title
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
