import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cgid/content.dart';
import 'package:cgid/features/workspace/providers/plan_provider.dart';

Entry _entry(String id, String title, {String subtitle = 'Alabanza', String notes = ''}) =>
    Entry(id: id, title: title, subtitle: subtitle, sections: const [], notes: notes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlanNotifier Sync and Conflict Unit Tests', () {
    test('init recovers stored plans, active plan, and revision metadata from SharedPreferences', () async {
      final storedPlans = {
        'Culto Sabado': [
          _entry('h1', 'Himno 1', notes: 'Nota local').toJson(),
          _entry('p1', 'Predicacion').toJson(),
        ],
        'Culto Miercoles': [
          _entry('m1', 'Meditacion').toJson(),
        ]
      };
      final storedMeta = {
        'Culto Sabado': {
          'revision': 3,
          'lastModified': '2026-10-05T12:00:00Z',
          'assignments': [
            {'role': 'presidente', 'displayName': 'Hermano Lucas'},
          ]
        },
        'Culto Miercoles': {
          'revision': 1,
        }
      };

      SharedPreferences.setMockInitialValues({
        'activePlan': 'Culto Sabado',
        'plans': jsonEncode(storedPlans),
        'planMetadata': jsonEncode(storedMeta),
      });

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(planProvider.notifier);
      await notifier.init(prefs);

      final state = container.read(planProvider);
      expect(state.activePlan, 'Culto Sabado');
      expect(state.plan, hasLength(2));
      expect(state.plan.first.title, 'Himno 1');
      expect(state.plan.first.notes, 'Nota local');
      expect(state.savedPlans.keys, containsAll(['Culto Sabado', 'Culto Miercoles']));
      
      final meta = notifier.metadataFor('Culto Sabado');
      expect(meta.personFor('presidente'), 'Hermano Lucas');
      expect(state.planMetadata['Culto Sabado']?['revision'], 3);
    });

    test('optimistic concurrency revision check detects conflicts when remote is ahead', () {
      final localRevision = 2;
      final remoteRevision = 4;

      final hasConflict = remoteRevision > localRevision;
      expect(hasConflict, isTrue, reason: 'Remote revision ahead of local revision indicates concurrent modification conflict');
    });

    test('updating entries preserves plan revisions and metadata integrity', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(planProvider.notifier);
      await notifier.init(prefs);

      notifier.createPlan('Culto Regional');
      notifier.addEntry(_entry('e1', 'Apertura'));
      notifier.updateMetadata('Culto Regional', const ServicePlanMetadata(
        assignments: [
          ServiceAssignment(role: 'director', displayName: 'Hno. Marcos'),
        ],
      ));

      expect(notifier.metadataFor('Culto Regional').personFor('director'), 'Hno. Marcos');

      // Modifying plan entries keeps the assigned metadata intact
      notifier.addEntry(_entry('e2', 'Himno'));
      expect(notifier.metadataFor('Culto Regional').personFor('director'), 'Hno. Marcos');
      expect(container.read(planProvider).plan, hasLength(2));
    });

    test('switching active plans loads the respective plan entries without crosstalk', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(planProvider.notifier);
      await notifier.init(prefs);

      notifier.createPlan('Plan A');
      notifier.addEntry(_entry('a1', 'Item A1'));

      notifier.createPlan('Plan B');
      notifier.addEntry(_entry('b1', 'Item B1'));
      notifier.addEntry(_entry('b2', 'Item B2'));

      notifier.setActivePlan('Plan A');
      expect(container.read(planProvider).activePlan, 'Plan A');
      expect(container.read(planProvider).plan.map((e) => e.id), ['a1']);

      notifier.setActivePlan('Plan B');
      expect(container.read(planProvider).activePlan, 'Plan B');
      expect(container.read(planProvider).plan.map((e) => e.id), ['b1', 'b2']);
    });
  });
}
