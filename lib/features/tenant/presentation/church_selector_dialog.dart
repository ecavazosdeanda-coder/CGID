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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/regions_and_churches.json');
      final data = jsonDecode(jsonString);
      final List<dynamic> churchesJson = data['churches'];
      if (mounted) {
        setState(() {
          _churches = churchesJson.map((e) => ChurchModel.fromJson(e)).toList();
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
    return AlertDialog(
      title: const Text('Selecciona tu Iglesia Local'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _churches.length,
                itemBuilder: (context, index) {
                  final church = _churches[index];
                  return ListTile(
                    leading: const Icon(Icons.church),
                    title: Text(church.name),
                    subtitle: Text('${church.city}, ${church.state}'),
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('selected_church_id', church.id);
                      if (context.mounted) {
                        Navigator.of(context).pop(church);
                      }
                    },
                  );
                },
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
