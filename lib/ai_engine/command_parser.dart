class ParsedCommand {
  const ParsedCommand(this.action, [this.parameters = const {}]);

  final String action;
  final Map<String, Object?> parameters;
}

abstract interface class CommandParser {
  ParsedCommand parse(String input);
}

class RuleBasedCommandParser implements CommandParser {
  const RuleBasedCommandParser();

  @override
  ParsedCommand parse(String input) {
    final text = input.trim().toLowerCase();
    if (_contains(text, [
      'ปิดแอนติไวรัส',
      'disable antivirus',
      'bypass permission',
    ])) {
      return const ParsedCommand('restricted.security_bypass');
    }
    if (_contains(text, ['เริ่มบันทึก', 'เริ่มอัด', 'start recording'])) {
      return ParsedCommand('screen_recording.start', {
        'microphone': _contains(text, ['ไมโครโฟน', 'microphone', 'mic']),
      });
    }
    if (_contains(text, ['หยุดบันทึก', 'หยุดอัด', 'stop recording'])) {
      return const ParsedCommand('screen_recording.stop');
    }
    if (_contains(text, ['จับภาพ', 'screenshot'])) {
      return const ParsedCommand('screenshot.take');
    }
    if (_contains(text, [
      'ใช้ ram',
      'ใช้แรม',
      'using ram',
      'memory use',
      'processes',
    ])) {
      return const ParsedCommand('application.list');
    }
    if (_contains(text, ['เปิด bluetooth', 'open bluetooth'])) {
      return const ParsedCommand('settings.open', {'page': 'bluetooth'});
    }
    if (_contains(text, ['ลดเสียง', 'ตั้งเสียง', 'volume'])) {
      final percent = RegExp(r'\d+').firstMatch(text)?.group(0);
      return ParsedCommand('settings.volume', {
        'percent': int.tryParse(percent ?? '') ?? 30,
      });
    }
    if (_contains(text, ['ไฟล์ขนาดใหญ่', 'large files'])) {
      return const ParsedCommand('file.search_large');
    }
    if (_contains(text, ['สถานะระบบ', 'system status', 'diagnostics'])) {
      return const ParsedCommand('diagnostics.status');
    }
    if (_contains(text, ['เปิด', 'open'])) {
      return ParsedCommand('application.open', {'query': input.trim()});
    }
    return ParsedCommand('unknown', {'input': input.trim()});
  }

  bool _contains(String input, List<String> terms) => terms.any(input.contains);
}
