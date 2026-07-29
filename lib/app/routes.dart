enum AppSection {
  home('หน้าหลัก'),
  assistant('AI Assistant'),
  recorder('บันทึกหน้าจอ'),
  applications('แอปพลิเคชัน'),
  files('ไฟล์'),
  settings('การตั้งค่าระบบ'),
  diagnostics('การวินิจฉัย'),
  permissions('สิทธิ์และความปลอดภัย'),
  privacy('Privacy & Ad Blocking');

  const AppSection(this.label);
  final String label;
}
