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

  test(
    'service functions belong to each plan, not to the user account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(planProvider.notifier)..init(prefs);

      notifier.createPlan('Culto matutino');
      notifier.updateMetadata(
        'Culto matutino',
        const ServicePlanMetadata(
          assignments: [
            ServiceAssignment(role: 'presidente', displayName: 'Hermano Juan'),
            ServiceAssignment(role: 'predicador', displayName: 'Hermano Pedro'),
          ],
        ),
      );
      notifier.createPlan('Culto vespertino');
      notifier.updateMetadata(
        'Culto vespertino',
        const ServicePlanMetadata(
          assignments: [
            ServiceAssignment(role: 'presidente', displayName: 'Hermano Pedro'),
            ServiceAssignment(role: 'predicador', displayName: 'Hermano Juan'),
          ],
        ),
      );

      expect(
        notifier.metadataFor('Culto matutino').personFor('presidente'),
        'Hermano Juan',
      );
      expect(
        notifier.metadataFor('Culto vespertino').personFor('predicador'),
        'Hermano Juan',
      );
    },
  );

  test('entry assignments survive local persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(planProvider.notifier)..init(prefs);

    notifier.createPlan('Culto asignado');
    notifier.addEntry(
      const Entry(
        id: 'sermon',
        title: 'Mensaje',
        subtitle: 'Predicación',
        sections: [],
        assignments: [
          ServiceAssignment(role: 'predicador', displayName: 'Hermana Ana'),
        ],
      ),
    );

    final persisted =
        jsonDecode(prefs.getString('plans')!) as Map<String, dynamic>;
    final entry = (persisted['Culto asignado'] as List).single as Map;
    expect((entry['assignments'] as List).single['role'], 'predicador');
    expect((entry['assignments'] as List).single['displayName'], 'Hermana Ana');
  });

  test('cloud public plan excludes private notes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(planProvider.notifier)..init(prefs);
    final plans = {
      'Culto': [
        _entry(
          'private',
          'Predicación',
        ).copyWith(notes: 'Nota exclusiva del equipo ministerial').toJson(),
      ],
    };

    final publicPlans = notifier.publicPlansForCloud(plans);
    final privateNotes = notifier.privateNotesForCloud(plans);

    expect((publicPlans['Culto'] as List).single['notes'], isEmpty);
    expect(
      (privateNotes['Culto'] as List).single,
      'Nota exclusiva del equipo ministerial',
    );
  });
}
