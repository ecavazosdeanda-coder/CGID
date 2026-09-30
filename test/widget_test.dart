import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/appearance.dart';

void main() {
  test('Identidad del sábado según la fecha local', () {
    expect(isSabbathBranding(DateTime(2026, 10, 2, 23, 59)), isFalse);
    expect(isSabbathBranding(DateTime(2026, 10, 3)), isTrue);
    expect(isSabbathBranding(DateTime(2026, 10, 3, 23, 59)), isTrue);
    expect(isSabbathBranding(DateTime(2026, 10, 4)), isFalse);
    expect(
      churchLogoAsset(DateTime(2026, 10, 3)),
      globalChurchSabbathLogoAsset,
    );
    expect(churchLogoAsset(DateTime(2026, 10, 4)), globalChurchLogoAsset);
  });
}
