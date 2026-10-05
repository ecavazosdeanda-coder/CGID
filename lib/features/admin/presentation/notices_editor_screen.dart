import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../tenant/providers/tenant_provider.dart';

class NoticesEditorScreen extends ConsumerStatefulWidget {
  const NoticesEditorScreen({super.key});

  @override
  ConsumerState<NoticesEditorScreen> createState() => _NoticesEditorScreenState();
}

class _NoticesEditorScreenState extends ConsumerState<NoticesEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  List<DocumentSnapshot> _noticeDocs = [];
  String _selectedPriority = 'General';

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
    final church = await ref.read(tenantProvider.future);
    if (church == null) return;
    
    FirebaseFirestore.instance
        .collection('churches')
        .doc(church.id)
        .collection('notices')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _noticeDocs = snap.docs;
      });
    });
  }

  Future<void> _addNotice() async {
    if (_controller.text.trim().isEmpty) return;
    
    final church = await ref.read(tenantProvider.future);
    if (church == null) return;

    final title = '[$_selectedPriority] ${_controller.text.trim()}';

    await FirebaseFirestore.instance
        .collection('churches')
        .doc(church.id)
        .collection('notices')
        .add({
      'title': title,
      'body': '',
      'startsAt': Timestamp.now(),
      'endsAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      'createdAt': FieldValue.serverTimestamp(),
    });

    _controller.clear();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aviso guardado en la nube.')),
      );
    }
  }
  
  Future<void> _deleteNotice(String id) async {
    final church = await ref.read(tenantProvider.future);
    if (church == null) return;

    await FirebaseFirestore.instance
        .collection('churches')
        .doc(church.id)
        .collection('notices')
        .doc(id)
        .delete();
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
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPriority = val);
                      },
                      items: _priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Escribe el nuevo aviso (Ej: "Ensayo general el sábado a las 5 PM")',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addNotice(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: _addNotice,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _noticeDocs.isEmpty
                  ? const Center(child: Text('No hay avisos guardados en la nube.'))
                  : ListView.builder(
                      itemCount: _noticeDocs.length,
                      itemBuilder: (context, index) {
                        final doc = _noticeDocs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final noticeText = data['title'] as String? ?? '';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getColorForPriority(noticeText).withValues(alpha: 0.2),
                              child: Icon(
                                _getIconForPriority(noticeText),
                                color: _getColorForPriority(noticeText),
                              ),
                            ),
                            title: Text(
                              _cleanNoticeText(noticeText),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteNotice(doc.id),
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
