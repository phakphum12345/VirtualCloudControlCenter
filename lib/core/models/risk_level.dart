enum RiskLevel {
  safe,
  confirmationRequired,
  restricted;

  String get wireName => switch (this) {
    safe => 'safe',
    confirmationRequired => 'confirmation_required',
    restricted => 'restricted',
  };
}
