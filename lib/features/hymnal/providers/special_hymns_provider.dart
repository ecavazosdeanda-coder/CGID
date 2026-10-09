import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tenant/providers/tenant_provider.dart';
import '../models/special_hymn_model.dart';
import '../services/special_hymn_service.dart';

final specialHymnServiceProvider = Provider<SpecialHymnService>((ref) {
  return SpecialHymnService();
});

final specialHymnsStreamProvider = StreamProvider<List<SpecialHymn>>((ref) async* {
  final service = ref.watch(specialHymnServiceProvider);
  final church = await ref.watch(tenantProvider.future);

  if (church == null) {
    yield [];
    return;
  }

  yield* service.streamHymnsByChurch(church.id);
});
