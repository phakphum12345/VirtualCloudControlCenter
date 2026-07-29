#include "linux_assistant.h"

#include <sys/statvfs.h>

#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

FlValue* result_map(bool success, const gchar* message) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "success", fl_value_new_bool(success));
  fl_value_set_string_take(value, "message", fl_value_new_string(message));
  return value;
}

uint64_t memory_kilobytes(const std::string& key) {
  std::ifstream stream("/proc/meminfo");
  std::string name;
  uint64_t value = 0;
  std::string unit;
  while (stream >> name >> value >> unit) {
    if (name == key + ":") return value;
  }
  return 0;
}

FlValue* system_status() {
  FlValue* value =
      result_map(true, "Linux system status read successfully.");
  const uint64_t total_memory = memory_kilobytes("MemTotal") * 1024;
  const uint64_t available_memory = memory_kilobytes("MemAvailable") * 1024;
  fl_value_set_string_take(
      value, "memoryTotalBytes",
      fl_value_new_int(static_cast<int64_t>(total_memory)));
  fl_value_set_string_take(
      value, "memoryAvailableBytes",
      fl_value_new_int(static_cast<int64_t>(available_memory)));
  fl_value_set_string_take(value, "logicalProcessors",
                           fl_value_new_int(g_get_num_processors()));

  struct statvfs disk {};
  if (statvfs("/", &disk) == 0) {
    fl_value_set_string_take(
        value, "diskTotalBytes",
        fl_value_new_int(static_cast<int64_t>(disk.f_blocks) * disk.f_frsize));
    fl_value_set_string_take(
        value, "diskFreeBytes",
        fl_value_new_int(static_cast<int64_t>(disk.f_bavail) * disk.f_frsize));
  }
  return value;
}

std::string string_argument(FlValue* arguments, const gchar* key) {
  if (!arguments || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) return {};
  FlValue* value = fl_value_lookup_string(arguments, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return {};
  return fl_value_get_string(value);
}

FlValue* open_settings(FlValue* arguments) {
  const std::string page = string_argument(arguments, "page");
  static const std::map<std::string, std::string> allowed_panels = {
      {"wifi", "wifi"},           {"bluetooth", "bluetooth"},
      {"display", "display"},     {"sound", "sound"},
      {"notifications", "notifications"},
      {"battery", "power"},
  };
  const auto panel = allowed_panels.find(page);
  if (panel == allowed_panels.end()) {
    return result_map(false,
                      "The requested Linux settings page is not allowlisted.");
  }
  gchar* arguments_list[] = {
      const_cast<gchar*>("gnome-control-center"),
      const_cast<gchar*>(panel->second.c_str()),
      nullptr,
  };
  g_autoptr(GError) error = nullptr;
  if (!g_spawn_async(nullptr, arguments_list, nullptr, G_SPAWN_SEARCH_PATH,
                     nullptr, nullptr, nullptr, &error)) {
    return result_map(
        false,
        "The current Linux desktop could not open this settings panel.");
  }
  return result_map(true, "Linux settings opened.");
}

void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                    gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "getSystemStatus") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(system_status()));
  } else if (strcmp(method, "openSettings") == 0) {
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(open_settings(arguments)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

void register_linux_assistant(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine),
      "com.phakphum.aiassistant/linux", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}
