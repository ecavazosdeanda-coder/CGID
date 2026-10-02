import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tenant/models/church_model.dart';
import '../../tenant/providers/tenant_provider.dart';

class ChurchEventsScreen extends ConsumerStatefulWidget {
  const ChurchEventsScreen({super.key});

  @override
  ConsumerState<ChurchEventsScreen> createState() => _ChurchEventsScreenState();
}

class _ChurchEventsScreenState extends ConsumerState<ChurchEventsScreen> {
  EventScope? _selectedScope; // null = Todos

  Color _getScopeColor(EventScope scope) {
    switch (scope) {
      case EventScope.nacional:
        return const Color(0xFFD97706); // Ámbar dorado
      case EventScope.regional:
        return const Color(0xFF2563EB); // Azul real
      case EventScope.local:
        return const Color(0xFF059669); // Verde esmeralda
    }
  }

  String _getScopeLabel(EventScope scope) {
    switch (scope) {
      case EventScope.nacional:
        return 'Nacional';
      case EventScope.regional:
        return 'Regional';
      case EventScope.local:
        return 'Local';
    }
  }

  IconData _getScopeIcon(EventScope scope) {
    switch (scope) {
      case EventScope.nacional:
        return Icons.public;
      case EventScope.regional:
        return Icons.map_outlined;
      case EventScope.local:
        return Icons.church;
    }
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year · $hour:$minute hrs';
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(churchEventsProvider);
    final church = ref.watch(tenantProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos y Convocatorias'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(churchEventsProvider),
          ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error al cargar eventos: $err')),
        data: (events) {
          final filtered = _selectedScope == null
              ? events
              : events.where((e) => e.scope == _selectedScope).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header contextual banner
              Container(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Color(0xFF102E48), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Calendario Oficial de Convocatorias',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            church != null
                                ? 'Filtrado para: ${church.name} (${church.state})'
                                : 'Mostrando convocatorias nacionales (Selecciona una iglesia para ver eventos locales)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected: _selectedScope == null,
                      label: const Text('Todos'),
                      onSelected: (_) => setState(() => _selectedScope = null),
                    ),
                    FilterChip(
                      selected: _selectedScope == EventScope.nacional,
                      avatar: const Icon(Icons.public, size: 16),
                      label: const Text('Nacional'),
                      onSelected: (_) => setState(() => _selectedScope = EventScope.nacional),
                    ),
                    FilterChip(
                      selected: _selectedScope == EventScope.regional,
                      avatar: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Regional'),
                      onSelected: (_) => setState(() => _selectedScope = EventScope.regional),
                    ),
                    FilterChip(
                      selected: _selectedScope == EventScope.local,
                      avatar: const Icon(Icons.church, size: 16),
                      label: const Text('Local'),
                      onSelected: (_) => setState(() => _selectedScope = EventScope.local),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Event List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay eventos programados en esta categoría.',
                              style: TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final event = filtered[index];
                          final scopeColor = _getScopeColor(event.scope);
                          final scopeLabel = _getScopeLabel(event.scope);
                          final scopeIcon = _getScopeIcon(event.scope);

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: scopeColor.withAlpha(80), width: 1.2),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: scopeColor.withAlpha(30),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(scopeIcon, color: scopeColor, size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: scopeColor.withAlpha(40),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    scopeLabel.toUpperCase(),
                                                    style: TextStyle(
                                                      color: scopeColor,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              event.title,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    event.description,
                                    style: const TextStyle(fontSize: 14, height: 1.4),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time, size: 16, color: Colors.blueGrey),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Inicio: ${_formatDate(event.startDateTime)}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.event_available, size: 16, color: Colors.blueGrey),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Conclusión: ${_formatDate(event.endDateTime)}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        if (event.locationName != null && event.locationName!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.place, size: 16, color: Colors.blueGrey),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Lugar: ${event.locationName}',
                                                  style: const TextStyle(fontSize: 12),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      if (event.googleMapsUrl != null && event.googleMapsUrl!.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            final uri = Uri.tryParse(event.googleMapsUrl!);
                                            if (uri != null && await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          icon: const Icon(Icons.directions, size: 16),
                                          label: const Text('Cómo llegar'),
                                        ),
                                      if (event.streamUrl != null && event.streamUrl!.isNotEmpty)
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF102E48)),
                                          onPressed: () async {
                                            final uri = Uri.tryParse(event.streamUrl!);
                                            if (uri != null && await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          icon: const Icon(Icons.videocam, size: 16),
                                          label: const Text('Unirse a Transmisión'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
