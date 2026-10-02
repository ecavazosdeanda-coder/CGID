import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cgid/content.dart';
import 'package:cgid/features/workspace/providers/plan_provider.dart';

Entry _entry(String id, String title, {String subtitle = 'Alabanza'}) =>
    Entry(id: id, title: title, subtitle: subtitle, sections: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom service items always produce a projectable title slide', () {
    final slides = makeSlides(
      _entry(
        'custom-1',
        'Bienvenida por la familia López',
        subtitle: 'Bienvenida',
      ),
    );

    expect(slides, hasLength(1));
    expect(slides.single.text, 'Bienvenida por la familia López');
    expect(slides.single.label, 'Bienvenida');
  });

  test(
    'service order edits and reorder operations persist atomically',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(planProvider.notifier)..init(prefs);

      notifier.createPlan('Culto de prueba');
      notifier.addEntry(_entry('a', 'Bienvenida'));
      notifier.addEntry(_entry('b', 'Himno de apertura', subtitle: 'Himno'));
      notifier.moveEntry(0, 1);
      notifier.replaceEntry(
        1,
        _entry('a', 'Bienvenida y saludo').copyWith(notes: 'Dirige Ana'),
      );
      final removed = container.read(planProvider).plan.first;
      notifier.removeEntry(0);
      notifier.insertEntry(0, removed);

      final state = container.read(planProvider);
      expect(state.activePlan, 'Culto de prueba');
      expect(state.plan.map((entry) => entry.id), ['b', 'a']);
      expect(state.plan.last.notes, 'Dirige Ana');

      final persisted =
          jsonDecode(prefs.getString('plans')!) as Map<String, dynamic>;
      final storedPlan = persisted['Culto de prueba'] as List<dynamic>;
      expect(storedPlan.map((entry) => entry['id']), ['b', 'a']);
      expect(storedPlan.last['notes'], 'Dirige Ana');
    },
  );

  test('creating a plan with an existing name never erases it', () async {
    final existing = [_entry('h1', 'Himno inicial').toJson()];
    SharedPreferences.setMockInitialValues({
      'plans': jsonEncode({'Culto existente': existing}),
      'activePlan': 'Culto existente',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(planProvider.notifier)..init(prefs);

    notifier.createPlan('Culto existente');

    expect(container.read(planProvider).plan, hasLength(1));
    expect(container.read(planProvider).plan.single.title, 'Himno inicial');
  });
}
