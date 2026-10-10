import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoticesEditorScreen extends StatefulWidget {
  const NoticesEditorScreen({
    super.key,
    this.churchId,
    this.migrateLegacyNotices = true,
  });
  final String? churchId;
  final bool migrateLegacyNotices;

  @override
  State<NoticesEditorScreen> createState() => _NoticesEditorScreenState();
}

class _NoticesEditorScreenState extends State<NoticesEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  List<String> _notices = [];
  String _selectedPriority = 'General';
  String _storageKey = 'local_notices_unassigned';

  final List<String> _priorities = [
    'General',
    'Importante',
    'Reunión',
    'Urgente',
  ];

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    final prefs = await SharedPreferences.getInstance();
    final churchId =
        widget.churchId ??
        prefs.getString('selected_church_id') ??
        'unassigned';
    _storageKey = 'local_notices_$churchId';
    final scoped = prefs.getStringList(_storageKey);
    final legacy = widget.migrateLegacyNotices
        ? prefs.getStringList('local_notices')
        : null;
    if (scoped == null && legacy != null) {
      await prefs.setStringList(_storageKey, legacy);
    }
    if (!mounted) return;
    setState(() {
      _notices = scoped ?? legacy ?? [];
    });
  }

  Future<void> _saveNotices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _notices);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avisos guardados en este dispositivo.')),
      );
    }
  }

  void _addNotice() {
    if (_controller.text.trim().isNotEmpty) {
      setState(() {
        _notices.add('[$_selectedPriority] ${_controller.text.trim()}');
        _controller.clear();
      });
      _saveNotices();
    }
  }

  Color _getColorForPriority(String notice) {
    if (notice.startsWith('[Urgente]')) return Colors.redAccent;
    if (notice.startsWith('[Importante]')) return Colors.orange;
    if (notice.startsWith('[Reunión]')) return Colors.blueAccent;
    return Colors.teal;
  }

  IconData _getIconForPriority(String notice) {
    if (notice.startsWith('[Urgente]')) return Icons.warning;
    if (notice.startsWith('[Importante]')) return Icons.priority_high;
    if (notice.startsWith('[Reunión]')) return Icons.groups;
    return Icons.campaign;
  }

  String _cleanNoticeText(String notice) {
    return notice.replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editor de Avisos Semanales')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: _selectedPriority,
                      items: _priorities.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedPriority = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText:
                              'Ej. Reunión de jóvenes este domingo a las 10am',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onSubmitted: (_) => _addNotice(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Publicar Aviso'),
                      onPressed: _addNotice,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _notices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.speaker_notes_off,
                            size: 64,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No hay avisos registrados para esta semana.',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: _notices.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = _notices.removeAt(oldIndex);
                          _notices.insert(newIndex, item);
                        });
                        _saveNotices();
                      },
                      itemBuilder: (context, index) {
                        final notice = _notices[index];
                        return Card(
                          key: ValueKey('$index-$notice'),
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getColorForPriority(notice)
                                  .withValues(alpha: 0.1),
                              child: Icon(
                                _getIconForPriority(notice),
                                color: _getColorForPriority(notice),
                              ),
                            ),
                            title: Text(
                              _cleanNoticeText(notice),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.drag_handle,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _notices.removeAt(index);
                                    });
                                    _saveNotices();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
