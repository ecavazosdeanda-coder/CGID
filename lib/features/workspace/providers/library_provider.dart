import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content.dart';

final libraryProvider = FutureProvider<Library>((ref) async {
  return await Library.load();
});
