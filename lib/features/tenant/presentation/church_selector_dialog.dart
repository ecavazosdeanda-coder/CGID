import 'package:flutter/material.dart';

import '../models/church_model.dart';

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class ChurchSelectorDialog extends StatefulWidget {
  const ChurchSelectorDialog({super.key});

  static Future<ChurchModel?> show(BuildContext context) {
    return showDialog<ChurchModel>(
      context: context,
      builder: (context) => const ChurchSelectorDialog(),
    );
  }

  @override
  State<ChurchSelectorDialog> createState() => _ChurchSelectorDialogState();
}

class _ChurchSelectorDialogState extends State<ChurchSelectorDialog> {
  List<ChurchModel> _churches = [];
  List<RegionModel> _regions = [];
  bool _loading = true;
  String _query = '';
  String? _regionId;
  String? _state;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/regions_and_churches.json',
      );
      final data = jsonDecode(jsonString);
      final List<dynamic> churchesJson = data['churches'];
      final List<dynamic> regionsJson = data['regions'] ?? const [];
      if (mounted) {
        setState(() {
          _churches = churchesJson.map((e) => ChurchModel.fromJson(e)).toList();
          _regions = regionsJson.map((e) => RegionModel.fromJson(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = _churches.map((church) => church.state).toSet().toList()
      ..sort();
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = _churches.where((church) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          '${church.name} ${church.city} ${church.state} '
                  '${church.address} ${church.contactPhone}'
              .toLowerCase()
              .contains(normalizedQuery);
      return matchesQuery &&
          (_regionId == null || church.regionId == _regionId) &&
          (_state == null || church.state == _state);
    }).toList();

    return AlertDialog(
      title: const Text('Selecciona tu Iglesia Local'),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por iglesia, estado o ciudad',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _regionId,
                          decoration: const InputDecoration(
                            labelText: 'Región',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todas'),
                            ),
                            for (final region in _regions)
                              DropdownMenuItem<String?>(
                                value: region.id,
                                child: Text(region.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _regionId = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _state,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            for (final state in states)
                              DropdownMenuItem<String?>(
                                value: state,
                                child: Text(state),
                              ),
                          ],
                          onChanged: (value) => setState(() => _state = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No se encontraron iglesias.'),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final church = filtered[index];
                              return ListTile(
                                leading: const Icon(Icons.church),
                                title: Text(church.name),
                                subtitle: Text(
                                  '${church.city}, ${church.state}'
                                  '${church.verificationStatus == 'verified' ? '' : ' · Información por verificar'}',
                                ),
                                onTap: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setString(
                                    'selected_church_id',
                                    church.id,
                                  );
                                  await prefs.setString(
                                    'tenant_church_name',
                                    church.name,
                                  );
                                  if (context.mounted) {
                                    Navigator.of(context).pop(church);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
