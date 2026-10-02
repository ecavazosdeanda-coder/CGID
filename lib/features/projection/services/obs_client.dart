import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'obs_client_native.dart'
    if (dart.library.js_interop) 'obs_client_web.dart';

export 'obs_client_native.dart'
    if (dart.library.js_interop) 'obs_client_web.dart';
export 'obs_models.dart';

final obsClientProvider = Provider<ObsClient>((ref) {
  final client = ObsClient();
  ref.onDispose(() => client.disconnect());
  return client;
});
