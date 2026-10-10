import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content.dart';
import '../admin/models/user_profile_model.dart';
import '../admin/providers/user_profile_provider.dart';
import '../tenant/models/church_model.dart';

class ReadingTarget {
  const ReadingTarget(this.type, this.id, this.label);
  final String type, id, label;
  String get key => '${type}_${sha256.convert(utf8.encode(id))}';
  static ReadingTarget? forEntry(Entry entry) {
    if (entry.id.startsWith('f')) {
      return ReadingTarget('faith', entry.id, entry.title);
    }
    if (entry.id.startsWith('b')) {
      return ReadingTarget('bible', entry.id, entry.title);
    }
    return null;
  }
}

bool canWriteReadingComments(UserProfile? profile) =>
    profile != null && (profile.isAdmin || profile.isPastor);
bool canManageReadingComment(UserProfile? profile, ReadingComment comment) =>
    profile != null &&
    (profile.isAdmin ||
        (profile.isPastor &&
            comment.authorId == profile.uid &&
            comment.churchId == profile.churchId));

class ReadingComment {
  ReadingComment(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get body => data['body'] as String;
  String get authorId => data['authorId'] as String;
  String get authorRole => data['authorRole'] as String;
  String get churchId => data['churchId'] as String;
  bool get visible => data['visible'] == true;
  DateTime? get createdAt => (data['createdAt'] as Timestamp?)?.toDate();
}

final commentChurchesProvider = FutureProvider<List<ChurchModel>>((ref) async {
  final raw = jsonDecode(
    await rootBundle.loadString('assets/data/regions_and_churches.json'),
  ) as Map<String, dynamic>;
  return (raw['churches'] as List)
      .map((e) => ChurchModel.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

/// One public query per opened panel; collapsed buttons do not subscribe.
final readingCommentsProvider = StreamProvider.autoDispose
    .family<List<ReadingComment>, String>((ref, key) {
      if (Firebase.apps.isEmpty) return Stream.value([]);
      return FirebaseFirestore.instance
          .collection('reading_comments')
          .doc(key)
          .collection('comments')
          .where('visible', isEqualTo: true)
          .snapshots()
          .map(
            (s) => s.docs.map((d) => ReadingComment(d.id, d.data())).toList(),
          );
    });
final managedReadingCommentsProvider = StreamProvider.autoDispose
    .family<List<ReadingComment>, String>((ref, key) {
      final profile = ref.watch(userProfileProvider).value;
      if (Firebase.apps.isEmpty || !canWriteReadingComments(profile)) {
        return Stream.value([]);
      }
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('reading_comments')
          .doc(key)
          .collection('comments');
      if (!profile!.isAdmin) {
        query = query
            .where('authorId', isEqualTo: profile.uid)
            .where('churchId', isEqualTo: profile.churchId ?? '');
      }
      return query.snapshots().map(
        (s) => s.docs.map((d) => ReadingComment(d.id, d.data())).toList(),
      );
    });

List<ReadingComment> filterReadingComments(
  Iterable<ReadingComment> comments,
  List<ChurchModel> churches, {
  String church = '',
  String region = '',
  String state = '',
  String city = '',
}) {
  final directory = {for (final c in churches) c.id: c};
  return comments.where((comment) {
    final c = directory[comment.churchId];
    return (church.isEmpty || comment.churchId == church) &&
        (region.isEmpty || c?.regionId == region) &&
        (state.isEmpty || c?.state == state) &&
        (city.isEmpty || c?.city == city);
  }).toList()..sort(
    (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
      a.createdAt ?? DateTime(1970),
    ),
  );
}

class ReadingCommentsButton extends StatelessWidget {
  const ReadingCommentsButton({
    super.key,
    required this.target,
    this.compact = false,
  });
  final ReadingTarget target;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    void open() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: ReadingCommentsPanel(target: target),
        ),
      ),
    );
    return compact
        ? IconButton(
            tooltip: 'Comentarios pastorales',
            onPressed: open,
            icon: const Icon(Icons.mode_comment_outlined, size: 20),
          )
        : TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.mode_comment_outlined, size: 18),
            label: const Text('Comentarios pastorales'),
          );
  }
}

class ReadingCommentsPanel extends ConsumerStatefulWidget {
  const ReadingCommentsPanel({super.key, required this.target});
  final ReadingTarget target;
  @override
  ConsumerState<ReadingCommentsPanel> createState() =>
      _ReadingCommentsPanelState();
}

class _ReadingCommentsPanelState extends ConsumerState<ReadingCommentsPanel> {
  String _church = '', _region = '', _state = '', _city = '';
  bool _manage = false, _busy = false;
  String? _error;
  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore
      .instance
      .collection('reading_comments')
      .doc(widget.target.key)
      .collection('comments');

  Future<void> _change(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action().timeout(const Duration(seconds: 20));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se confirmó el cambio. Comprueba tu conexión y tus permisos; revisa la lista antes de reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    UserProfile profile,
    List<ChurchModel> churches, [
    ReadingComment? existing,
  ]) async {
    final text = TextEditingController(text: existing?.body ?? '');
    String churchId = existing?.churchId ?? profile.churchId ?? '';
    if (!churches.any((c) => c.id == churchId)) {
      churchId = profile.isAdmin ? '' : (profile.churchId ?? '');
    }
    bool visible = existing?.visible ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Comentario pastoral' : 'Editar comentario',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.target.label),
                  const SizedBox(height: 12),
                  TextField(
                    controller: text,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      labelText: 'Comentario',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (profile.isAdmin && existing == null)
                    DropdownButtonFormField<String>(
                      initialValue: churchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Procedencia',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Conferencia / Nacional'),
                        ),
                        ...churches.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          update(() => churchId = value ?? ''),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Visible para todos'),
                    subtitle: const Text(
                      'Puedes guardarlo oculto y publicarlo después.',
                    ),
                    value: visible,
                    onChanged: (value) => update(() => visible = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isNotEmpty &&
                    text.text.trim().length <= 3000) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final body = text.text.trim();
    text.dispose();
    if (saved != true || !mounted) return;
    await _change(() async {
      final current = await ref.read(userProfileProvider.future);
      final authenticated = await ref.read(
        authenticatedUserProfileProvider.future,
      );
      if (!canWriteReadingComments(current) ||
          !canWriteReadingComments(authenticated)) {
        throw StateError('Sin permisos');
      }
      if (existing != null && !canManageReadingComment(current, existing)) {
        throw StateError('Sin permisos');
      }
      if (!current!.isAdmin &&
          (churchId.isEmpty || churchId != current.churchId)) {
        throw StateError('Iglesia no asignada');
      }
      if (existing != null) {
        await _collection.doc(existing.id).update({
          'body': body,
          'visible': visible,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _collection.add({
          'body': body,
          'visible': visible,
          'churchId': churchId,
          'authorId': authenticated!.uid,
          'authorRole': authenticated.role,
          'targetType': widget.target.type,
          'targetLabel': widget.target.label,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Widget _filter(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) changed,
  ) => SizedBox(
    width: 210,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: options.containsKey(value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        ...options.entries
            .where((e) => e.key.isNotEmpty)
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            ),
      ],
      onChanged: (value) => setState(() => changed(value ?? '')),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final canWrite = canWriteReadingComments(profile);
    final directory = ref.watch(commentChurchesProvider);
    final churches = directory.value ?? <ChurchModel>[];
    final comments = ref.watch(
      _manage && canWrite
          ? managedReadingCommentsProvider(widget.target.key)
          : readingCommentsProvider(widget.target.key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Comentarios pastorales',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Ocultar comentarios',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.target.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ExpansionTile(
          title: const Text('Filtrar por ubicación'),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _filter('Iglesia', _church, {
                        for (final c in churches) c.id: c.name,
                      }, (v) => _church = v),
                      _filter('Región', _region, {
                        for (final c in churches)
                          c.regionId: c.regionId.replaceFirst(
                            'region-',
                            'Región ',
                          ),
                      }, (v) => _region = v),
                      _filter('Estado', _state, {
                        for (final c in churches) c.state: c.state,
                      }, (v) => _state = v),
                      _filter('Ciudad', _city, {
                        for (final c in churches) c.city: c.city,
                      }, (v) => _city = v),
                      if ([
                        _church,
                        _region,
                        _state,
                        _city,
                      ].any((v) => v.isNotEmpty))
                        TextButton(
                          onPressed: () => setState(() {
                            _church = _region = _state = _city = '';
                          }),
                          child: const Text('Limpiar filtros'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (canWrite)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text(
                    profile!.isAdmin
                        ? 'Moderación (incluye ocultos)'
                        : 'Mis comentarios (incluye ocultos)',
                  ),
                  selected: _manage,
                  onSelected: (v) => setState(() => _manage = v),
                ),
                TextButton.icon(
                  onPressed:
                      _busy ||
                          directory.isLoading ||
                          (!profile.isAdmin &&
                              (profile.churchId?.isEmpty ?? true))
                      ? null
                      : () => _edit(profile, churches),
                  icon: const Icon(Icons.add),
                  label: const Text('Comentar'),
                ),
              ],
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (directory.hasError)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No se pudo cargar el directorio para filtrar por ubicación.',
            ),
          ),
        Expanded(
          child: comments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No se pudieron cargar los comentarios.'),
                  TextButton(
                    onPressed: () {
                      ref.invalidate(
                        readingCommentsProvider(widget.target.key),
                      );
                      ref.invalidate(
                        managedReadingCommentsProvider(widget.target.key),
                      );
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
            data: (items) {
              final filtered = filterReadingComments(
                items,
                churches,
                church: _church,
                region: _region,
                state: _state,
                city: _city,
              );
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No hay comentarios para esta selección.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final comment = filtered[index];
                  final church = churches
                      .where((c) => c.id == comment.churchId)
                      .firstOrNull;
                  final date = comment.createdAt;
                  return Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${comment.authorRole == 'admin' ? 'Administración' : 'Pastor'} · ${church?.name ?? (comment.churchId.isEmpty ? 'Conferencia / Nacional' : comment.churchId)}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (date != null)
                            Text(
                              '${date.day}/${date.month}/${date.year}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          const SizedBox(height: 8),
                          Text(comment.body),
                          if (!comment.visible)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text('Oculto al público'),
                            ),
                          if (canManageReadingComment(profile, comment))
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            _edit(profile!, churches, comment),
                                  child: const Text('Editar'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _change(() async {
                                          final current = await ref.read(
                                            userProfileProvider.future,
                                          );
                                          if (!canManageReadingComment(
                                            current,
                                            comment,
                                          )) {
                                            throw StateError('Sin permisos');
                                          }
                                          await _collection
                                              .doc(comment.id)
                                              .update({
                                                'visible': !comment.visible,
                                                'updatedAt':
                                                    FieldValue.serverTimestamp(),
                                              });
                                        }),
                                  child: Text(
                                    comment.visible
                                        ? 'Ocultar al público'
                                        : 'Publicar',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
