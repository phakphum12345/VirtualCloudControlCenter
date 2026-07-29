#ifndef RUNNER_WINDOWS_RECORDER_H_
#define RUNNER_WINDOWS_RECORDER_H_

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

struct RecorderResult {
  bool success;
  std::string message;
  std::string output_file;
};

class WindowsRecorder {
 public:
  WindowsRecorder();
  ~WindowsRecorder();

  WindowsRecorder(const WindowsRecorder&) = delete;
  WindowsRecorder& operator=(const WindowsRecorder&) = delete;

  RecorderResult Start(int frames_per_second, const std::string& quality);
  RecorderResult Pause();
  RecorderResult Resume();
  RecorderResult Stop();
  RecorderResult Status() const;

 private:
  bool InitializeWriter(int width, int height, int frames_per_second,
                        const std::string& quality,
                        const std::wstring& output_file);
  void RecordLoop(int left, int top, int width, int height,
                  int frames_per_second);
  void ReleaseWriter();

  mutable std::mutex mutex_;
  std::atomic<bool> running_{false};
  std::atomic<bool> paused_{false};
  std::atomic<bool> capture_failed_{false};
  std::thread capture_thread_;
  std::wstring output_file_;
  std::string last_error_;
  int stream_index_ = 0;
  struct IMFSinkWriter* writer_ = nullptr;
};

#endif  // RUNNER_WINDOWS_RECORDER_H_
