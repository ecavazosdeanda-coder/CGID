import 'package:flutter_test/flutter_test.dart';

import 'package:cgid/features/remote/services/cloud_remote_bridge.dart';

void main() {
  test('cloud remote pairing codes are high-entropy and human readable', () {
    final codes = List.generate(
      200,
      (_) => CloudRemoteBridge.generateSessionCode(),
    );

    expect(codes.toSet(), hasLength(codes.length));
    for (final code in codes) {
      expect(code, hasLength(10));
      expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{10}$')));
    }
  });
}
