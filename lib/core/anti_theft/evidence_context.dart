import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class EvidenceContext {
  EvidenceContext({Connectivity? connectivity, DeviceInfoPlugin? deviceInfo})
    : _connectivity = connectivity ?? Connectivity(),
      _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final Connectivity _connectivity;
  final DeviceInfoPlugin _deviceInfo;

  Stream<List<ConnectivityResult>> get networkChanges =>
      _connectivity.onConnectivityChanged;

  Future<String> networkType() async {
    final values = await _connectivity.checkConnectivity();
    if (values.isEmpty || values.contains(ConnectivityResult.none)) {
      return 'offline';
    }
    return values.map((value) => value.name).join(',');
  }

  Future<String> deviceSummary() async {
    if (Platform.isAndroid) {
      final value = await _deviceInfo.androidInfo;
      return '${value.manufacturer} ${value.model}; Android ${value.version.release}';
    }
    if (Platform.isIOS) {
      final value = await _deviceInfo.iosInfo;
      return '${value.name} ${value.model}; iOS ${value.systemVersion}';
    }
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }
}
