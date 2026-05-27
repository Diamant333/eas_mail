import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // enough_mail prints low-level diagnostics via dart:core print() when it
  // encounters malformed MIME encoded-words (e.g. Windows-1251 with invalid
  // Base64 padding).  These are handled gracefully by our own _formatAddress /
  // _safeSubject / _safeFileName helpers, so the raw print noise is useless in
  // production.  We intercept it at the zone level and drop known patterns.
  runZoned(
    () => runApp(const EasMailApp()),
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        // Suppress enough_mail address-parsing warnings.
        if (line.startsWith('Warning: invalid mail address')) return;
        parent.print(zone, line);
      },
    ),
  );
}
