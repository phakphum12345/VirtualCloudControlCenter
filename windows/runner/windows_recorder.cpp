#include "windows_recorder.h"

#include <windows.h>

#include <knownfolders.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size, nullptr,
                      nullptr);
  return result;
}

std::filesystem::path VideoFolder() {
  PWSTR raw_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Videos, KF_FLAG_DEFAULT, nullptr,
                                  &raw_path))) {
    return {};
  }
  std::filesystem::path path(raw_path);
  CoTaskMemFree(raw_path);
  path /= L"Phakphum AI";
  std::error_code error;
  std::filesystem::create_directories(path, error);
  return error ? std::filesystem::path() : path;
}

std::wstring NewOutputPath() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t time = std::chrono::system_clock::to_time_t(now);
  std::tm local_time{};
  localtime_s(&local_time, &time);
  std::wostringstream name;
  name << L"recording_" << std::put_time(&local_time, L"%Y%m%d_%H%M%S")
       << L".mp4";
  return (VideoFolder() / name.str()).wstring();
}

uint32_t BitrateFor(const std::string& quality, int width, int height,
                    int frames_per_second) {
  if (quality == "720p") return 5'000'000;
  if (quality == "1440p") return 16'000'000;
  const uint64_t pixels_per_second =
      static_cast<uint64_t>(width) * height * frames_per_second;
  return static_cast<uint32_t>(
      std::clamp<uint64_t>(pixels_per_second / 6, 6'000'000, 20'000'000));
}

}  // namespace

WindowsRecorder::WindowsRecorder() = default;

WindowsRecorder::~WindowsRecorder() {
  Stop();
}

RecorderResult WindowsRecorder::Start(int frames_per_second,
                                      const std::string& quality) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (running_ || capture_thread_.joinable()) {
    return {false, "A screen recording is already active.",
            WideToUtf8(output_file_)};
  }
  if (frames_per_second != 24 && frames_per_second != 30 &&
      frames_per_second != 60) {
    return {false, "Frame rate must be 24, 30, or 60.", ""};
  }

  const int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (width <= 0 || height <= 0) {
    return {false, "Windows did not report a capturable display.", ""};
  }

  output_file_ = NewOutputPath();
  if (output_file_.empty()) {
    return {false, "Windows could not create the recording folder.", ""};
  }
  if (!InitializeWriter(width, height, frames_per_second, quality,
                        output_file_)) {
    ReleaseWriter();
    return {false, last_error_, ""};
  }

  capture_failed_ = false;
  paused_ = false;
  running_ = true;
  capture_thread_ = std::thread(&WindowsRecorder::RecordLoop, this, left, top,
                                width, height, frames_per_second);
  return {true, "Screen recording started.", WideToUtf8(output_file_)};
}

RecorderResult WindowsRecorder::Pause() {
  if (!running_) {
    return {false, "No active screen recording to pause.",
            WideToUtf8(output_file_)};
  }
  paused_ = true;
  return {true, "Screen recording paused.", WideToUtf8(output_file_)};
}

RecorderResult WindowsRecorder::Resume() {
  if (!running_) {
    return {false, "No active screen recording to resume.",
            WideToUtf8(output_file_)};
  }
  paused_ = false;
  return {true, "Screen recording resumed.", WideToUtf8(output_file_)};
}

RecorderResult WindowsRecorder::Stop() {
  std::unique_lock<std::mutex> lock(mutex_);
  if (!capture_thread_.joinable()) {
    return {false, "No active screen recording to stop.",
            WideToUtf8(output_file_)};
  }
  running_ = false;
  paused_ = false;
  lock.unlock();
  capture_thread_.join();
  lock.lock();

  bool finalized = false;
  if (writer_) {
    finalized = SUCCEEDED(writer_->Finalize());
  }
  const bool failed = capture_failed_ || !finalized;
  const std::string output = WideToUtf8(output_file_);
  ReleaseWriter();
  return failed ? RecorderResult{false,
                                 last_error_.empty()
                                     ? "Windows could not finalize recording."
                                     : last_error_,
                                 output}
                : RecorderResult{true, "Screen recording saved.", output};
}

RecorderResult WindowsRecorder::Status() const {
  if (!running_) {
    return {true, "Screen recorder is idle.", WideToUtf8(output_file_)};
  }
  return {true, paused_ ? "Screen recording is paused."
                        : "Screen recording is active.",
          WideToUtf8(output_file_)};
}

bool WindowsRecorder::InitializeWriter(int width, int height,
                                       int frames_per_second,
                                       const std::string& quality,
                                       const std::wstring& output_file) {
  HRESULT result = MFStartup(MF_VERSION);
  if (FAILED(result)) {
    last_error_ = "Windows Media Foundation could not start.";
    return false;
  }

  ComPtr<IMFAttributes> attributes;
  result = MFCreateAttributes(&attributes, 1);
  if (SUCCEEDED(result)) {
    result = attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
  }
  if (SUCCEEDED(result)) {
    result = MFCreateSinkWriterFromURL(output_file.c_str(), nullptr,
                                       attributes.Get(), &writer_);
  }

  ComPtr<IMFMediaType> output_type;
  if (SUCCEEDED(result)) result = MFCreateMediaType(&output_type);
  if (SUCCEEDED(result))
    result = output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(result))
    result = output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  if (SUCCEEDED(result))
    result = output_type->SetUINT32(
        MF_MT_AVG_BITRATE,
        BitrateFor(quality, width, height, frames_per_second));
  if (SUCCEEDED(result))
    result = output_type->SetUINT32(MF_MT_INTERLACE_MODE,
                                    MFVideoInterlace_Progressive);
  if (SUCCEEDED(result))
    result = MFSetAttributeSize(output_type.Get(), MF_MT_FRAME_SIZE, width,
                                height);
  if (SUCCEEDED(result))
    result = MFSetAttributeRatio(output_type.Get(), MF_MT_FRAME_RATE,
                                 frames_per_second, 1);
  if (SUCCEEDED(result))
    result = MFSetAttributeRatio(output_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1,
                                 1);
  DWORD stream_index = 0;
  if (SUCCEEDED(result))
    result = writer_->AddStream(output_type.Get(), &stream_index);
  stream_index_ = static_cast<int>(stream_index);

  ComPtr<IMFMediaType> input_type;
  if (SUCCEEDED(result)) result = MFCreateMediaType(&input_type);
  if (SUCCEEDED(result))
    result = input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(result))
    result = input_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  if (SUCCEEDED(result))
    result = input_type->SetUINT32(MF_MT_INTERLACE_MODE,
                                   MFVideoInterlace_Progressive);
  if (SUCCEEDED(result))
    result = input_type->SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4);
  if (SUCCEEDED(result))
    result =
        MFSetAttributeSize(input_type.Get(), MF_MT_FRAME_SIZE, width, height);
  if (SUCCEEDED(result))
    result = MFSetAttributeRatio(input_type.Get(), MF_MT_FRAME_RATE,
                                 frames_per_second, 1);
  if (SUCCEEDED(result))
    result =
        MFSetAttributeRatio(input_type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  if (SUCCEEDED(result))
    result = writer_->SetInputMediaType(stream_index_, input_type.Get(), nullptr);
  if (SUCCEEDED(result)) result = writer_->BeginWriting();

  if (FAILED(result)) {
    last_error_ =
        "Windows could not initialize the H.264 MP4 recording pipeline.";
    return false;
  }
  return true;
}

void WindowsRecorder::RecordLoop(int left, int top, int width, int height,
                                 int frames_per_second) {
  const LONGLONG frame_duration = 10'000'000LL / frames_per_second;
  const DWORD image_size =
      static_cast<DWORD>(static_cast<uint64_t>(width) * height * 4);
  std::vector<BYTE> pixels(image_size);

  HDC screen = GetDC(nullptr);
  HDC memory = screen ? CreateCompatibleDC(screen) : nullptr;
  HBITMAP bitmap =
      memory ? CreateCompatibleBitmap(screen, width, height) : nullptr;
  HGDIOBJ old_object = bitmap ? SelectObject(memory, bitmap) : nullptr;
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  if (!screen || !memory || !bitmap) {
    last_error_ = "Windows could not allocate desktop capture resources.";
    capture_failed_ = true;
    running_ = false;
  }

  LONGLONG frame_index = 0;
  const auto frame_period =
      std::chrono::microseconds(1'000'000 / frames_per_second);
  auto next_frame = std::chrono::steady_clock::now();

  while (running_) {
    if (paused_) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
      next_frame = std::chrono::steady_clock::now();
      continue;
    }
    next_frame += frame_period;
    const bool copied =
        BitBlt(memory, 0, 0, width, height, screen, left, top,
               SRCCOPY | CAPTUREBLT) != FALSE;
    const bool read =
        copied && GetDIBits(memory, bitmap, 0, static_cast<UINT>(height),
                            pixels.data(), &info, DIB_RGB_COLORS) != 0;
    if (!read) {
      last_error_ = "Windows desktop capture failed.";
      capture_failed_ = true;
      running_ = false;
      break;
    }

    ComPtr<IMFMediaBuffer> buffer;
    ComPtr<IMFSample> sample;
    HRESULT result = MFCreateMemoryBuffer(image_size, &buffer);
    BYTE* destination = nullptr;
    if (SUCCEEDED(result)) result = buffer->Lock(&destination, nullptr, nullptr);
    if (SUCCEEDED(result)) {
      std::copy(pixels.begin(), pixels.end(), destination);
      buffer->Unlock();
      result = buffer->SetCurrentLength(image_size);
    }
    if (SUCCEEDED(result)) result = MFCreateSample(&sample);
    if (SUCCEEDED(result)) result = sample->AddBuffer(buffer.Get());
    if (SUCCEEDED(result))
      result = sample->SetSampleTime(frame_index * frame_duration);
    if (SUCCEEDED(result)) result = sample->SetSampleDuration(frame_duration);
    if (SUCCEEDED(result)) result = writer_->WriteSample(stream_index_, sample.Get());
    if (FAILED(result)) {
      last_error_ = "Windows H.264 encoder rejected a captured frame.";
      capture_failed_ = true;
      running_ = false;
      break;
    }
    ++frame_index;
    std::this_thread::sleep_until(next_frame);
  }

  if (old_object) SelectObject(memory, old_object);
  if (bitmap) DeleteObject(bitmap);
  if (memory) DeleteDC(memory);
  if (screen) ReleaseDC(nullptr, screen);
}

void WindowsRecorder::ReleaseWriter() {
  if (writer_) {
    writer_->Release();
    writer_ = nullptr;
  }
  MFShutdown();
}
