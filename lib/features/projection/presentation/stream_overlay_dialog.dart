import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../projection_native.dart'
    if (dart.library.js_interop) '../../../projection_web.dart'
    as projection;
import '../services/obs_client.dart';
import 'stream_overlay_screen.dart';
import 'obs_dock_screen.dart';

class StreamOverlayDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> outputState;

  const StreamOverlayDialog({super.key, required this.outputState});

  static Future<void> show(
    BuildContext context,
    Map<String, dynamic> outputState,
  ) {
    return showDialog(
      context: context,
      builder: (context) => StreamOverlayDialog(outputState: outputState),
    );
  }

  @override
  ConsumerState<StreamOverlayDialog> createState() => _StreamOverlayDialogState();
}

class _StreamOverlayDialogState extends ConsumerState<StreamOverlayDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 1: Browser Source settings
  OverlayMode _mode = OverlayMode.lowerthird;
  OverlayPosition _position = OverlayPosition.bottom;
  OverlayBackground _bg = OverlayBackground.transparent;
  OverlayTextSize _size = OverlayTextSize.normal;
  bool _liveBadge = false;
  bool _copiedOverlay = false;

  // Tab 2: Dock settings
  bool _copiedDock = false;

  // Tab 3: OBS WebSocket settings
  final TextEditingController _hostController =
      TextEditingController(text: '127.0.0.1');
  final TextEditingController _portController =
      TextEditingController(text: '4455');
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _generatedOverlayUrl {
    final base = Uri.base;
    final query = <String, String>{
      'overlay': '1',
      if (_bg != OverlayBackground.transparent) 'bg': _bg.name,
      if (_mode != OverlayMode.lowerthird) 'mode': _mode.name,
      if (_position != OverlayPosition.bottom) 'pos': _position.name,
      if (_size != OverlayTextSize.normal) 'size': _size.name,
      if (_liveBadge) 'live': '1',
    };
    return base.replace(queryParameters: query, fragment: '').toString();
  }

  String get _generatedDockUrl {
    final base = Uri.base;
    return base.replace(
      queryParameters: {'dock': '1'},
      fragment: '/obs-dock',
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final obsClient = ref.watch(obsClientProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 16, top: 20, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.sensors,
                      color: Color(0xFF6366F1),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Integración con OBS Studio y Transmisión',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Letras en vivo, panel acoplable dentro de OBS y control remoto WebSocket',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              indicatorColor: const Color(0xFF6366F1),
              tabs: const [
                Tab(
                  icon: Icon(Icons.layers_outlined, size: 18),
                  text: 'Fuente de Letras (Browser)',
                ),
                Tab(
                  icon: Icon(Icons.dashboard_customize_outlined, size: 18),
                  text: 'Panel dentro de OBS (Dock)',
                ),
                Tab(
                  icon: Icon(Icons.cable_outlined, size: 18),
                  text: 'OBS WebSocket (v5)',
                ),
              ],
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverlayTab(theme),
                  _buildDockTab(theme),
                  _buildWebSocketTab(theme, obsClient),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 1: Browser Source Overlay
  // ----------------------------------------------------
  Widget _buildOverlayTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Config card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                // Formato
                Row(
                  children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Formato:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Expanded(
                      child: SegmentedButton<OverlayMode>(
                        segments: const [
                          ButtonSegment(
                            value: OverlayMode.lowerthird,
                            label: Text('Tercio Inf.'),
                          ),
                          ButtonSegment(
                            value: OverlayMode.strip,
                            label: Text('Cintillo'),
                          ),
                          ButtonSegment(
                            value: OverlayMode.clean,
                            label: Text('Texto Limpio'),
                          ),
                          ButtonSegment(
                            value: OverlayMode.fullscreen,
                            label: Text('Centrado'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (set) => setState(() => _mode = set.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Posición
                Row(
                  children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Posición:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Expanded(
                      child: SegmentedButton<OverlayPosition>(
                        segments: const [
                          ButtonSegment(
                            value: OverlayPosition.bottom,
                            label: Text('Parte Inferior (Abajo)'),
                            icon: Icon(Icons.vertical_align_bottom, size: 16),
                          ),
                          ButtonSegment(
                            value: OverlayPosition.top,
                            label: Text('Parte Superior (Arriba)'),
                            icon: Icon(Icons.vertical_align_top, size: 16),
                          ),
                        ],
                        selected: {_position},
                        onSelectionChanged: (set) => setState(() => _position = set.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Fondo
                Row(
                  children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Fondo:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Expanded(
                      child: SegmentedButton<OverlayBackground>(
                        segments: const [
                          ButtonSegment(
                            value: OverlayBackground.transparent,
                            label: Text('Transparente (OBS)'),
                          ),
                          ButtonSegment(
                            value: OverlayBackground.green,
                            label: Text('Chroma Verde'),
                            icon: Icon(Icons.circle, color: Color(0xFF00FF00), size: 12),
                          ),
                          ButtonSegment(
                            value: OverlayBackground.blue,
                            label: Text('Chroma Azul'),
                            icon: Icon(Icons.circle, color: Color(0xFF0000FF), size: 12),
                          ),
                          ButtonSegment(
                            value: OverlayBackground.dark,
                            label: Text('Oscuro'),
                          ),
                        ],
                        selected: {_bg},
                        onSelectionChanged: (set) => setState(() => _bg = set.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Tamaño y Badge
                Row(
                  children: [
                    const SizedBox(
                      width: 90,
                      child: Text('Tamaño:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    Expanded(
                      child: SegmentedButton<OverlayTextSize>(
                        segments: const [
                          ButtonSegment(value: OverlayTextSize.compact, label: Text('Compacto')),
                          ButtonSegment(value: OverlayTextSize.normal, label: Text('Normal (28pt)')),
                          ButtonSegment(value: OverlayTextSize.large, label: Text('Grande (34pt)')),
                        ],
                        selected: {_size},
                        onSelectionChanged: (set) => setState(() => _size = set.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar distintivo "🔴 EN VIVO · CGDI" en la esquina superior', style: TextStyle(fontSize: 12)),
                  value: _liveBadge,
                  onChanged: (val) => setState(() => _liveBadge = val ?? false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // URL box
          const Text('Enlace para Fuente de Navegador en OBS:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _copiedOverlay ? const Color(0xFF10B981) : Colors.white12,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _generatedOverlayUrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF93C5FD)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _copiedOverlay ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: Icon(_copiedOverlay ? Icons.check : Icons.copy, size: 15),
                  label: Text(_copiedOverlay ? '¡Copiado!' : 'Copiar Enlace'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generatedOverlayUrl));
                    setState(() => _copiedOverlay = true);
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _copiedOverlay = false);
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Steps
          _buildInfoBox(
            title: 'Configuración en OBS Studio (Browser Source):',
            steps: const [
              '1. En tu escena de OBS, haz clic en Fuentes (+) -> Navegador (Browser).',
              '2. En el campo "URL", pega el enlace copiado arriba.',
              '3. Configura el Ancho en 1920 y el Alto en 1080 (o la resolución de tu lienzo).',
              '4. ¡Listo! Al cambiar los himnos o versículos en la cabina, las letras aparecerán en tiempo real.',
            ],
          ),
          const SizedBox(height: 16),

          // Test button
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Probar en Nueva Ventana'),
              onPressed: () {
                projection.openOverlay(
                  widget.outputState,
                  bg: _bg.name,
                  mode: _mode.name,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 2: Custom Browser Dock
  // ----------------------------------------------------
  Widget _buildDockTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dashboard_customize, color: Color(0xFF38BDF8), size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Controla el sistema sin salir de OBS Studio',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Agrega el panel interactivo de CGDI dentro de la interfaz de OBS Studio (junto al mezclador de audio o escenas). Podrás ver la letra en vivo, avanzar estrofas y ocultar letras con 1 clic.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const Text('URL del Panel Acoplable (OBS Custom Browser Dock):', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _copiedDock ? const Color(0xFF10B981) : Colors.white12,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _generatedDockUrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF93C5FD)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _copiedDock ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: Icon(_copiedDock ? Icons.check : Icons.copy, size: 15),
                  label: Text(_copiedDock ? '¡Copiado!' : 'Copiar URL del Dock'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generatedDockUrl));
                    setState(() => _copiedDock = true);
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _copiedDock = false);
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _buildInfoBox(
            title: '¿Cómo agregar el Panel dentro de OBS Studio en 4 pasos?',
            steps: const [
              '1. En OBS Studio, ve al menú superior: Paneles (Docks) -> Paneles de navegador personalizados (Custom Browser Docks).',
              '2. En el campo "Nombre del panel" escribe: CGDI Letras y Alabanza.',
              '3. En el campo "URL", pega el enlace copiado arriba.',
              '4. Haz clic en "Aplicar". Se abrirá una ventana que puedes arrastrar y acoplar en cualquier lugar dentro de OBS.',
            ],
          ),
          const SizedBox(height: 16),

          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir Vista Previa del Panel'),
              onPressed: () {
                // Open dock in new tab / window
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ObsDockScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 3: Direct OBS WebSocket (v5)
  // ----------------------------------------------------
  Widget _buildWebSocketTab(ThemeData theme, ObsClient obsClient) {
    return ValueListenableBuilder<ObsState>(
      valueListenable: obsClient.stateNotifier,
      builder: (context, obsState, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection status header card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: obsState.isConnected
                      ? const Color(0xFF065F46).withValues(alpha: 0.2)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: obsState.isConnected
                        ? const Color(0xFF10B981)
                        : theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      obsState.isConnected ? Icons.check_circle : Icons.portable_wifi_off,
                      color: obsState.isConnected ? const Color(0xFF10B981) : Colors.grey,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            obsState.isConnected
                                ? 'Conectado a OBS Studio v5'
                                : 'Desconectado de OBS WebSocket',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            obsState.isConnected
                                ? 'Comunicación bidireccional activa (ws://${_hostController.text}:${_portController.text})'
                                : 'Permite iniciar grabación del culto, monitorear streaming y cambiar escenas desde CGDI.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (obsState.isConnected)
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                        ),
                        onPressed: () => obsClient.disconnect(),
                        child: const Text('Desconectar'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (!obsState.isConnected) ...[
                // Connection inputs
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Host / IP de OBS',
                          hintText: '127.0.0.1',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Puerto',
                          hintText: '4455',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña de WebSocket (Opcional)',
                    hintText: 'Dejar en blanco si no tiene clave',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (obsState.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    obsState.errorMessage!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: obsState.isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cable, size: 18),
                    label: Text(obsState.isConnecting ? 'Conectando...' : 'Conectar con OBS Studio'),
                    onPressed: obsState.isConnecting
                        ? null
                        : () {
                            final port = int.tryParse(_portController.text.trim()) ?? 4455;
                            obsClient.connect(
                              host: _hostController.text.trim().isEmpty ? '127.0.0.1' : _hostController.text.trim(),
                              port: port,
                              password: _passwordController.text.isEmpty ? null : _passwordController.text,
                            );
                          },
                  ),
                ),
                const SizedBox(height: 18),
                _buildInfoBox(
                  title: '¿Dónde activar WebSocket en OBS Studio?',
                  steps: const [
                    '1. Abre OBS Studio (versión 28 o superior).',
                    '2. Ve al menú superior: Herramientas -> Configuración del servidor WebSocket.',
                    '3. Marca la casilla "Habilitar servidor WebSocket" (puerto por defecto: 4455).',
                    '4. (Opcional) Si configuras una contraseña, escríbela en el campo de arriba y pulsa Conectar.',
                  ],
                ),
              ] else ...[
                // Connected controls
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Acciones de Transmisión y Grabación:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                foregroundColor: obsState.isRecording ? const Color(0xFFEF4444) : null,
                                side: BorderSide(
                                  color: obsState.isRecording ? const Color(0xFFEF4444) : theme.dividerColor,
                                ),
                              ),
                              icon: Icon(
                                obsState.isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                                color: const Color(0xFFEF4444),
                              ),
                              label: Text(
                                obsState.isRecording
                                    ? 'Detener Grabación (${obsState.recordTimecode})'
                                    : 'Grabar Culto en OBS',
                              ),
                              onPressed: () => obsClient.toggleRecord(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: obsState.isStreaming ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.sensors),
                              label: Text(
                                obsState.isStreaming
                                    ? 'Detener Transmisión (${obsState.streamTimecode})'
                                    : 'Iniciar Transmisión en OBS',
                              ),
                              onPressed: () => obsClient.toggleStream(),
                            ),
                          ),
                        ],
                      ),
                      if (obsState.scenes.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Cambio de Escena en OBS:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: obsState.scenes.map((scene) {
                            final isCurrent = scene == obsState.currentScene;
                            return ChoiceChip(
                              label: Text(scene),
                              selected: isCurrent,
                              onSelected: (_) => obsClient.setCurrentScene(scene),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoBox({required String title, required List<String> steps}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                step,
                style: const TextStyle(fontSize: 11, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}
