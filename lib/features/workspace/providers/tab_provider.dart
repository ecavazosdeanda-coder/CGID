import 'package:flutter_riverpod/flutter_riverpod.dart';

final tabProvider = NotifierProvider<TabNotifier, int>(() => TabNotifier());

class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) {
    state = index;
  }
}
