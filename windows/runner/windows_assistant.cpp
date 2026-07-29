#include "windows_assistant.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <endpointvolume.h>
#include <knownfolders.h>
#include <mmdeviceapi.h>
#include <psapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

constexpr char kChannelName[] = "com.phakphum.aiassistant/windows";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return {};
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) {
    return {};
  }
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size, nullptr,
                      nullptr);
  return result;
}

const EncodableMap* Arguments(const MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

const EncodableValue* FindValue(const EncodableMap* arguments,
                                const char* key) {
  if (!arguments) {
    return nullptr;
  }
  const auto iterator = arguments->find(EncodableValue(key));
  return iterator == arguments->end() ? nullptr : &iterator->second;
}

std::string StringArgument(const EncodableMap* arguments, const char* key) {
  const auto* value = FindValue(arguments, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

int IntArgument(const EncodableMap* arguments, const char* key, int fallback) {
  const auto* value = FindValue(arguments, key);
  if (!value) {
    return fallback;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<int>(*number);
  }
  return fallback;
}

EncodableMap SuccessMap(const std::string& message) {
  return {
      {EncodableValue("success"), EncodableValue(true)},
      {EncodableValue("message"), EncodableValue(message)},
  };
}

EncodableMap FailureMap(const std::string& message) {
  return {
      {EncodableValue("success"), EncodableValue(false)},
      {EncodableValue("message"), EncodableValue(message)},
  };
}

bool ShellOpen(const std::wstring& target) {
  const auto result = reinterpret_cast<INT_PTR>(
      ShellExecute(nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  return result > 32;
}

EncodableValue GetCapabilities() {
  return EncodableMap{
      {EncodableValue("systemStatus"), EncodableValue(true)},
      {EncodableValue("fileSearch"), EncodableValue(true)},
      {EncodableValue("screenRecording"), EncodableValue(false)},
      {EncodableValue("screenshot"), EncodableValue(true)},
      {EncodableValue("appLaunch"), EncodableValue(true)},
      {EncodableValue("appControl"), EncodableValue(true)},
      {EncodableValue("settingsLaunch"), EncodableValue(true)},
      {EncodableValue("volumeControl"), EncodableValue(true)},
      {EncodableValue("contentFiltering"), EncodableValue(false)},
  };
}

EncodableValue GetSystemStatus() {
  MEMORYSTATUSEX memory{};
  memory.dwLength = sizeof(memory);
  const bool memory_ok = GlobalMemoryStatusEx(&memory) != FALSE;

  ULARGE_INTEGER free_bytes{};
  ULARGE_INTEGER total_bytes{};
  const bool disk_ok =
      GetDiskFreeSpaceEx(nullptr, &free_bytes, &total_bytes, nullptr) != FALSE;

  SYSTEM_INFO system_info{};
  GetNativeSystemInfo(&system_info);

  EncodableMap result = SuccessMap("Windows system status read successfully.");
  result[EncodableValue("logicalProcessors")] =
      EncodableValue(static_cast<int32_t>(system_info.dwNumberOfProcessors));
  if (memory_ok) {
    result[EncodableValue("memoryTotalBytes")] =
        EncodableValue(static_cast<int64_t>(memory.ullTotalPhys));
    result[EncodableValue("memoryAvailableBytes")] =
        EncodableValue(static_cast<int64_t>(memory.ullAvailPhys));
    result[EncodableValue("memoryLoadPercent")] =
        EncodableValue(static_cast<int32_t>(memory.dwMemoryLoad));
  }
  if (disk_ok) {
    result[EncodableValue("diskTotalBytes")] =
        EncodableValue(static_cast<int64_t>(total_bytes.QuadPart));
    result[EncodableValue("diskFreeBytes")] =
        EncodableValue(static_cast<int64_t>(free_bytes.QuadPart));
  }
  return result;
}

EncodableValue OpenSettings(const EncodableMap* arguments) {
  const std::string page = StringArgument(arguments, "page");
  static const std::map<std::string, std::wstring> kAllowedPages = {
      {"bluetooth", L"ms-settings:bluetooth"},
      {"wifi", L"ms-settings:network-wifi"},
      {"microphone", L"ms-settings:privacy-microphone"},
      {"camera", L"ms-settings:privacy-webcam"},
      {"display", L"ms-settings:display"},
      {"storage", L"ms-settings:storagesense"},
      {"battery", L"ms-settings:batterysaver"},
      {"notifications", L"ms-settings:notifications"},
      {"sound", L"ms-settings:sound"},
  };
  const auto target = kAllowedPages.find(page);
  if (target == kAllowedPages.end()) {
    return FailureMap("The requested settings page is not allowlisted.");
  }
  return ShellOpen(target->second)
             ? EncodableValue(SuccessMap("Windows settings opened."))
             : EncodableValue(FailureMap("Windows could not open settings."));
}

std::wstring Lowercase(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), ::towlower);
  return value;
}

EncodableValue OpenApplication(const EncodableMap* arguments) {
  const std::wstring query =
      Lowercase(Utf8ToWide(StringArgument(arguments, "query")));
  static const std::vector<std::pair<std::wstring, std::wstring>> kAllowedApps = {
      {L"visual studio code", L"code"},
      {L"vscode", L"code"},
      {L"notepad", L"notepad.exe"},
      {L"โน้ตแพด", L"notepad.exe"},
      {L"file explorer", L"explorer.exe"},
      {L"explorer", L"explorer.exe"},
      {L"calculator", L"calc.exe"},
      {L"เครื่องคิดเลข", L"calc.exe"},
  };
  for (const auto& app : kAllowedApps) {
    if (query.find(app.first) != std::wstring::npos) {
      return ShellOpen(app.second)
                 ? EncodableValue(SuccessMap("Application opened."))
                 : EncodableValue(
                       FailureMap("Windows could not open the application."));
    }
  }
  return FailureMap("Application is not in the Windows allowlist.");
}

EncodableValue ListProcesses() {
  EncodableList processes;
  const HANDLE snapshot =
      CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, static_cast<DWORD>(0));
  if (snapshot == INVALID_HANDLE_VALUE) {
    return FailureMap("Windows could not read the process list.");
  }

  PROCESSENTRY32 entry{};
  entry.dwSize = sizeof(entry);
  if (Process32First(snapshot, &entry)) {
    do {
      uint64_t working_set = 0;
      const HANDLE process =
          OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE,
                      entry.th32ProcessID);
      if (process) {
        PROCESS_MEMORY_COUNTERS counters{};
        if (GetProcessMemoryInfo(process, &counters, sizeof(counters))) {
          working_set = counters.WorkingSetSize;
        }
        CloseHandle(process);
      }
      processes.push_back(EncodableMap{
          {EncodableValue("pid"),
           EncodableValue(static_cast<int64_t>(entry.th32ProcessID))},
          {EncodableValue("name"),
           EncodableValue(WideToUtf8(entry.szExeFile))},
          {EncodableValue("memoryBytes"),
           EncodableValue(static_cast<int64_t>(working_set))},
      });
    } while (Process32Next(snapshot, &entry) && processes.size() < 300);
  }
  CloseHandle(snapshot);

  std::sort(processes.begin(), processes.end(),
            [](const EncodableValue& left, const EncodableValue& right) {
              const auto& left_map = std::get<EncodableMap>(left);
              const auto& right_map = std::get<EncodableMap>(right);
              return std::get<int64_t>(
                         left_map.at(EncodableValue("memoryBytes"))) >
                     std::get<int64_t>(
                         right_map.at(EncodableValue("memoryBytes")));
            });
  return processes;
}

EncodableValue CloseApplication(const EncodableMap* arguments) {
  const int pid = IntArgument(arguments, "pid", 0);
  if (pid <= 4 || pid == static_cast<int>(GetCurrentProcessId())) {
    return FailureMap("This process cannot be closed by the assistant.");
  }
  const HANDLE process =
      OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                  static_cast<DWORD>(pid));
  if (!process) {
    return FailureMap("Windows denied access to the process.");
  }
  const bool terminated = TerminateProcess(process, 1) != FALSE;
  CloseHandle(process);
  return terminated
             ? EncodableValue(SuccessMap("Application process closed."))
             : EncodableValue(FailureMap("Windows could not close the process."));
}

EncodableValue SetVolume(const EncodableMap* arguments) {
  const int percent = IntArgument(arguments, "percent", -1);
  if (percent < 0 || percent > 100) {
    return FailureMap("Volume must be between 0 and 100.");
  }

  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioEndpointVolume* endpoint = nullptr;
  HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                    CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (SUCCEEDED(result)) {
    result = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  }
  if (SUCCEEDED(result)) {
    result = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(&endpoint));
  }
  if (SUCCEEDED(result)) {
    result = endpoint->SetMasterVolumeLevelScalar(percent / 100.0f, nullptr);
  }
  if (endpoint) endpoint->Release();
  if (device) device->Release();
  if (enumerator) enumerator->Release();
  if (SUCCEEDED(initialized)) CoUninitialize();
  return SUCCEEDED(result)
             ? EncodableValue(SuccessMap("Windows volume changed."))
             : EncodableValue(FailureMap("Windows could not change volume."));
}

std::filesystem::path KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR raw_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw_path))) {
    return {};
  }
  const std::filesystem::path path(raw_path);
  CoTaskMemFree(raw_path);
  return path;
}

EncodableValue FindLargeFiles(const EncodableMap* arguments) {
  std::filesystem::path root = KnownFolder(FOLDERID_Downloads);
  const std::string requested = StringArgument(arguments, "path");
  if (!requested.empty()) {
    root = Utf8ToWide(requested);
  }
  std::error_code error;
  if (root.empty() || !std::filesystem::exists(root, error)) {
    return FailureMap("The search folder does not exist.");
  }

  struct FileItem {
    std::filesystem::path path;
    uintmax_t size;
  };
  std::vector<FileItem> files;
  const auto options = std::filesystem::directory_options::skip_permission_denied;
  for (std::filesystem::recursive_directory_iterator iterator(root, options, error),
       end;
       iterator != end; iterator.increment(error)) {
    if (error) {
      error.clear();
      continue;
    }
    if (!iterator->is_regular_file(error)) {
      continue;
    }
    const uintmax_t size = iterator->file_size(error);
    if (!error && size >= 10 * 1024 * 1024) {
      files.push_back({iterator->path(), size});
    }
  }
  std::sort(files.begin(), files.end(),
            [](const FileItem& left, const FileItem& right) {
              return left.size > right.size;
            });
  EncodableList output;
  const size_t limit = std::min<size_t>(files.size(), 100);
  for (size_t index = 0; index < limit; ++index) {
    output.push_back(EncodableMap{
        {EncodableValue("path"),
         EncodableValue(WideToUtf8(files[index].path.wstring()))},
        {EncodableValue("sizeBytes"),
         EncodableValue(static_cast<int64_t>(files[index].size))},
    });
  }
  return output;
}

std::filesystem::path ScreenshotPath() {
  auto folder = KnownFolder(FOLDERID_Pictures) / L"Phakphum AI";
  std::error_code error;
  std::filesystem::create_directories(folder, error);
  const auto timestamp =
      std::chrono::system_clock::now().time_since_epoch().count();
  return folder / (L"screenshot_" + std::to_wstring(timestamp) + L".bmp");
}

EncodableValue TakeScreenshot() {
  const int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width <= 0 || height <= 0) {
    return FailureMap("Windows did not report a capturable display.");
  }

  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
  HGDIOBJ old_object = SelectObject(memory, bitmap);
  const bool copied =
      BitBlt(memory, 0, 0, width, height, screen, left, top, SRCCOPY | CAPTUREBLT);

  BITMAPINFOHEADER header{};
  header.biSize = sizeof(header);
  header.biWidth = width;
  header.biHeight = height;
  header.biPlanes = 1;
  header.biBitCount = 32;
  header.biCompression = BI_RGB;
  const DWORD pixel_size = static_cast<DWORD>(width * height * 4);
  std::vector<unsigned char> pixels(pixel_size);
  const bool read = copied &&
                    GetDIBits(memory, bitmap, 0, static_cast<UINT>(height),
                              pixels.data(),
                              reinterpret_cast<BITMAPINFO*>(&header),
                              DIB_RGB_COLORS) != 0;

  SelectObject(memory, old_object);
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  if (!read) {
    return FailureMap("Windows could not capture the display.");
  }

  const auto path = ScreenshotPath();
  BITMAPFILEHEADER file_header{};
  file_header.bfType = 0x4D42;
  file_header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  file_header.bfSize = file_header.bfOffBits + pixel_size;
  std::ofstream file(path, std::ios::binary);
  if (!file) {
    return FailureMap("Windows could not create the screenshot file.");
  }
  file.write(reinterpret_cast<const char*>(&file_header), sizeof(file_header));
  file.write(reinterpret_cast<const char*>(&header), sizeof(header));
  file.write(reinterpret_cast<const char*>(pixels.data()), pixel_size);
  file.close();

  EncodableMap result = SuccessMap("Screenshot saved.");
  result[EncodableValue("outputFile")] =
      EncodableValue(WideToUtf8(path.wstring()));
  return result;
}

void HandleMethodCall(const MethodCall<EncodableValue>& call,
                      std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* arguments = Arguments(call);
  if (call.method_name() == "getCapabilities") {
    result->Success(GetCapabilities());
  } else if (call.method_name() == "getSystemStatus") {
    result->Success(GetSystemStatus());
  } else if (call.method_name() == "openSettings") {
    result->Success(OpenSettings(arguments));
  } else if (call.method_name() == "openApplication") {
    result->Success(OpenApplication(arguments));
  } else if (call.method_name() == "listProcesses") {
    result->Success(ListProcesses());
  } else if (call.method_name() == "closeApplication") {
    result->Success(CloseApplication(arguments));
  } else if (call.method_name() == "setVolume") {
    result->Success(SetVolume(arguments));
  } else if (call.method_name() == "findLargeFiles") {
    result->Success(FindLargeFiles(arguments));
  } else if (call.method_name() == "takeScreenshot") {
    result->Success(TakeScreenshot());
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterWindowsAssistant(flutter::FlutterEngine* engine) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleMethodCall);
}
