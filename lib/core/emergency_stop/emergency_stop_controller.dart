import 'package:flutter/foundation.dart';

class EmergencyStopController extends ChangeNotifier {
  bool _stopped = false;
  int _generation = 0;

  bool get isStopped => _stopped;
  int get generation => _generation;

  void stop() {
    _stopped = true;
    _generation++;
    notifyListeners();
  }

  void reset() {
    _stopped = false;
    notifyListeners();
  }

  bool wasCancelled(int operationGeneration) =>
      _stopped || operationGeneration != _generation;
}
