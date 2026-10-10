import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile_model.dart';
import '../providers/user_profile_provider.dart';
import '../../tenant/models/church_model.dart';
import '../../tenant/presentation/church_selector_dialog.dart';

class RoleSimulationPanel extends ConsumerStatefulWidget {
  const RoleSimulationPanel({super.key});

  @override
  ConsumerState<RoleSimulationPanel> createState() =>
      _RoleSimulationPanelState();
}

class _RoleSimulationPanelState extends ConsumerState<RoleSimulationPanel> {
  String _role = 'pastor';
  ChurchModel? _church;

  @override
  void initState() {
    super.initState();
    final active = ref.read(activeRoleSimulationProvider);
    _role = active?.role ?? 'pastor';
    _church = active?.church;
  }

  @override
  Widget build(BuildContext context) {
    final actual = ref.watch(authenticatedUserProfileProvider).value;
    if (actual?.isAdmin != true) return const SizedBox.shrink();
    final active = ref.watch(activeRoleSimulationProvider);
    final church = _church ?? active?.church;
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pruebas con tu cuenta de administrador',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Elige un rol y una iglesia en cada dispositivo. La simulación dura esta sesión y no cambia tu cuenta ni requiere otros correos.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Rol a simular',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final role in RoleSimulation.roles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(
                      UserProfile(
                        uid: '',
                        email: '',
                        role: role,
                      ).roleDisplayName,
                    ),
                  ),
              ],
              onChanged: (role) {
                if (role != null) setState(() => _role = role);
              },
            ),
            const SizedBox(height: 8),
            Text(church?.name ?? 'Selecciona una iglesia para las pruebas'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final selected = await ChurchSelectorDialog.show(
                      context,
                      persistSelection: false,
                    );
                    if (mounted && selected != null) {
                      setState(() => _church = selected);
                    }
                  },
                  icon: const Icon(Icons.church_outlined),
                  label: const Text('Elegir iglesia'),
                ),
                FilledButton.icon(
                  onPressed: church == null
                      ? null
                      : () {
                          ref
                              .read(roleSimulationProvider.notifier)
                              .start(_role, church);
                        },
                  icon: const Icon(Icons.science_outlined),
                  label: Text(
                    active == null
                        ? 'Iniciar simulación'
                        : 'Aplicar simulación',
                  ),
                ),
                if (active != null)
                  TextButton(
                    onPressed: () =>
                        ref.read(roleSimulationProvider.notifier).stop(),
                    child: const Text('Volver a administrador'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Atención: guardar o sincronizar afecta a la iglesia elegida. Usa una iglesia de pruebas. Firebase conserva tus permisos reales de administrador; este modo no prueba las reglas de seguridad de otros roles.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso persistente en todas las pestañas, con salida siempre accesible.
class RoleSimulationBanner extends ConsumerWidget {
  const RoleSimulationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeRoleSimulationProvider);
    if (active == null) return const SizedBox.shrink();
    final role = UserProfile(
      uid: '',
      email: '',
      role: active.role,
    ).roleDisplayName;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.science_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('SIMULACIÓN · $role · ${active.church.name}')),
            TextButton(
              onPressed: () => ref.read(roleSimulationProvider.notifier).stop(),
              child: const Text('Salir'),
            ),
          ],
        ),
      ),
    );
  }
}
