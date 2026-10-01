import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../../tenant/presentation/church_selector_dialog.dart';
import '../../../cult_picker_native.dart' if (dart.library.js_interop) '../../../cult_picker_web.dart' as cult_picker;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _savedPlansCount = 0;
  String _currentChurch = 'No configurada';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final plansJson = prefs.getString('plans') ?? '{}';
    final plansMap = jsonDecode(plansJson) as Map<String, dynamic>;
    
    final churchName = prefs.getString('tenant_church_name') ?? 'No configurada';

    if (mounted) {
      setState(() {
        _savedPlansCount = plansMap.length;
        _currentChurch = churchName;
      });
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final db = <String, dynamic>{};
      for (final key in keys) {
        db[key] = prefs.get(key);
      }
      
      final jsonBytes = utf8.encode(jsonEncode(db));
      final date = DateTime.now().toIso8601String().split('T').first;
      
      final saved = await cult_picker.saveCultFile(
        'cgdi_backup_$date.json',
        jsonBytes,
        'application/json',
      );
      
      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Base de datos exportada correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<void> _importDatabase() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (file != null) {
        final bytes = await file.readAsBytes();
        final jsonString = utf8.decode(bytes);
        final db = jsonDecode(jsonString) as Map<String, dynamic>;
        
        final prefs = await SharedPreferences.getInstance();
        for (final entry in db.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is String) await prefs.setString(key, value);
          else if (value is int) await prefs.setInt(key, value);
          else if (value is double) await prefs.setDouble(key, value);
          else if (value is bool) await prefs.setBool(key, value);
          else if (value is List) {
             await prefs.setStringList(key, value.map((e) => e.toString()).toList());
          }
        }
        
        await _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Base de datos importada exitosamente. Reinicia la aplicación.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar base de datos'),
        content: const Text('¿Estás seguro de que deseas borrar todas las preferencias y cultos guardados? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Borrar Todo', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Base de datos reiniciada a fábrica.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Administración del Sistema',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        
        // Tenant Section
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.church, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text('Congregación Local', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Configuración actual: $_currentChurch', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Configurar Distrito e Iglesia'),
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (ctx) => const ChurchSelectorDialog(),
                    );
                    _loadStats(); // Reload after configuring
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Database Section
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storage, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Base de Datos Local', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Cultos guardados: $_savedPlansCount', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Crear Respaldo'),
                      onPressed: _exportDatabase,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload),
                      label: const Text('Restaurar Respaldo'),
                      onPressed: _importDatabase,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('Borrar Todos los Datos', style: TextStyle(color: Colors.red)),
                      onPressed: _clearDatabase,
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Cloud Sync Section (Mock for now)
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_sync, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('Sincronización en la Nube', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Esta función permite mantener tus planes de culto y base de datos centralizada.', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('Conectar a la Nube (Próximamente)'),
                  onPressed: null, // Disabled for now
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
