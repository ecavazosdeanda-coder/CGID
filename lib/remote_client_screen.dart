import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'features/remote/services/cloud_remote_bridge.dart';
import 'glass.dart';

Uri? normalizeRemoteAddress(String rawAddress) {
  var value = rawAddress.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'http://$value';
  final parsed = Uri.tryParse(value);
  if (parsed == null ||
      parsed.host.isEmpty ||
      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    return null;
  }
  return Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : 8765,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  RemoteClientScreen
// ─────────────────────────────────────────────────────────────────────────────
class RemoteClientScreen extends StatefulWidget {
  final String? initialSessionId;
  const RemoteClientScreen({super.key, this.initialSessionId});
  @override
  State<RemoteClientScreen> createState() => _RemoteClientScreenState();
}

class _RemoteClientScreenState extends State<RemoteClientScreen>
    with SingleTickerProviderStateMixin {
  String? url;
  String? cloudSessionId;
  StreamSubscription? _cloudSubscription;
  bool _connected = false;
  bool get connected => _connected;
  set connected(bool value) {
    if (_connected != value) {
      _connected = value;
      unawaited(WakelockPlus.toggle(enable: value).catchError((_) {}));
    }
  }

  Timer? _pingTimer;
  Timer? _clockTimer;
  String? myIp;
  late final TabController _tabController;
  final _ipController = TextEditingController();
  final _cloudCodeController = TextEditingController();
  List<String> _recentIps = [];

  bool blackout = false;
  int slideIndex = 0, totalSlides = 0;
  String currentTitle = '', currentLabel = '', currentText = '';
  String nextTitle = '', nextLabel = '', nextText = '';
  int planIndex = -1, planCount = 0;
  List<Map<String, dynamic>> planItems = [];
  String currentNotes = '';
  int? countdownEndsAt;
  String _clockDisplay = '';

  // ── Bible search ────────────────────────────────────────────────────────────
  final List<String> _bibleBooks = const [
    'Génesis',
    'Éxodo',
    'Levítico',
    'Números',
    'Deuteronomio',
    'Josué',
    'Jueces',
    'Rut',
    '1 Samuel',
    '2 Samuel',
    '1 Reyes',
    '2 Reyes',
    '1 Crónicas',
    '2 Crónicas',
    'Esdras',
    'Nehemías',
    'Ester',
    'Job',
    'Salmos',
    'Proverbios',
    'Eclesiastés',
    'Cantares',
    'Isaías',
    'Jeremías',
    'Lamentaciones',
    'Ezequiel',
    'Daniel',
    'Oseas',
    'Joel',
    'Amós',
    'Abdías',
    'Jonás',
    'Miqueas',
    'Nahúm',
    'Habacuc',
    'Sofonías',
    'Hageo',
    'Zacarías',
    'Malaquías',
    'Mateo',
    'Marcos',
    'Lucas',
    'Juan',
    'Hechos',
    'Romanos',
    '1 Corintios',
    '2 Corintios',
    'Gálatas',
    'Efesios',
    'Filipenses',
    'Colosenses',
    '1 Tesalonicenses',
    '2 Tesalonicenses',
    '1 Timoteo',
    '2 Timoteo',
    'Tito',
    'Filemón',
    'Hebreos',
    'Santiago',
    '1 Pedro',
    '2 Pedro',
    '1 Juan',
    '2 Juan',
    '3 Juan',
    'Judas',
    'Apocalipsis',
  ];
  int _bibleBook = 0,
      _bibleChapter = 1,
      _bibleVerseStart = 1,
      _bibleVerseEnd = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadWifiIp();
    _loadRecentIps();
    _clockDisplay = _formatClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (url != null || cloudSessionId != null)) {
        setState(() => _clockDisplay = _formatClock());
      }
    });

    if (widget.initialSessionId != null && widget.initialSessionId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectToCloud(widget.initialSessionId!);
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clockTimer = null;
    _disconnect();
    _tabController.dispose();
    _ipController.dispose();
    _cloudCodeController.dispose();
    super.dispose();
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _cloudSubscription?.cancel();
    _cloudSubscription = null;
    if (mounted) {
      setState(() {
        url = null;
        cloudSessionId = null;
        connected = false;
      });
    }
    unawaited(WakelockPlus.disable().catchError((_) {}));
  }

  Future<void> _loadWifiIp() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (mounted) setState(() => myIp = ip);
    } catch (_) {
      // The manual address and QR paths remain available without Wi-Fi info.
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _formatClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatCountdown() {
    if (countdownEndsAt == null) return '';
    final remaining = countdownEndsAt! - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return '00:00';
    final total = (remaining / 1000).round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _loadRecentIps() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentIps = prefs.getStringList('remote_recent_ips') ?? [];
    });
  }

  Future<void> _saveRecentIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('remote_recent_ips') ?? [];
    list.remove(ip);
    list.insert(0, ip);
    if (list.length > 5) list.removeLast();
    await prefs.setStringList('remote_recent_ips', list);
    if (mounted) setState(() => _recentIps = list);
  }

  // ── Connection ───────────────────────────────────────────────────────────────
  void _connectTo(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (trimmed.startsWith('CLOUD:') || (!trimmed.contains('.') && !trimmed.contains(':') && trimmed.length >= 4 && trimmed.length <= 10)) {
      final code = trimmed.startsWith('CLOUD:') ? trimmed.substring(6) : trimmed;
      _connectToCloud(code);
      return;
    }

    final normalized = normalizeRemoteAddress(rawUrl);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe una dirección IP o código de sesión válido.')),
      );
      return;
    }
    _disconnect();
    final address = normalized.toString();
    setState(() => url = address);
    unawaited(_saveRecentIp(address));
    _startPing();
  }

  void _connectToCloud(String code) {
    _disconnect();
    final sessionId = code.trim().toUpperCase();
    setState(() {
      cloudSessionId = sessionId;
      connected = true;
    });
    unawaited(_saveRecentIp('CLOUD:$sessionId'));

    _cloudSubscription = CloudRemoteBridge.listenState(sessionId).listen((data) {
      if (!mounted) return;
      _updateStateFromJson(data);
    }, onError: (_) {
      if (mounted) setState(() => connected = false);
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _doPing());
    _doPing();
  }

  void _updateStateFromJson(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      connected = data['connected'] as bool? ?? true;
      blackout = data['blackout'] as bool? ?? false;
      slideIndex = data['slideIndex'] as int? ?? 0;
      totalSlides = data['totalSlides'] as int? ?? 0;
      currentTitle = data['currentTitle'] as String? ?? '';
      currentLabel = data['currentLabel'] as String? ?? '';
      currentText = data['currentText'] as String? ?? '';
      nextTitle = data['nextTitle'] as String? ?? '';
      nextLabel = data['nextLabel'] as String? ?? '';
      nextText = data['nextText'] as String? ?? '';
      planIndex = data['planIndex'] as int? ?? -1;
      planCount = data['planCount'] as int? ?? 0;
      final rawPlan = data['planItems'];
      if (rawPlan is List) {
        planItems = rawPlan
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      countdownEndsAt = data['countdownEndsAt'] as int?;
      currentNotes = data['currentNotes'] as String? ?? '';
    });
  }

  Future<void> _doPing() async {
    if (url == null) return;
    try {
      final res = await http
          .get(Uri.parse('$url/ping'))
          .timeout(const Duration(milliseconds: 3000));
      if (res.statusCode == 200) {
        try {
          _updateStateFromJson(jsonDecode(res.body) as Map<String, dynamic>);
        } catch (_) {
          if (!connected && mounted) setState(() => connected = true);
        }
      } else {
        if (connected && mounted) setState(() => connected = false);
      }
    } catch (_) {
      if (connected && mounted) setState(() => connected = false);
    }
  }

  Future<void> _send(String path) async {
    if (cloudSessionId != null) {
      final action = path.replaceFirst('/', '');
      if (action.startsWith('jump/')) {
        final idx = int.tryParse(action.substring(5)) ?? 0;
        await CloudRemoteBridge.sendCommand(cloudSessionId!, 'jump', payload: {'index': idx});
      } else {
        await CloudRemoteBridge.sendCommand(cloudSessionId!, action);
      }
      return;
    }

    if (url == null) return;
    try {
      final res = await http
          .post(Uri.parse('$url$path'))
          .timeout(const Duration(milliseconds: 3000));
      if (res.statusCode == 200) {
        try {
          _updateStateFromJson(jsonDecode(res.body) as Map<String, dynamic>);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _sendProjectVerse() async {
    final payload = {
      'b': _bibleBook,
      'c': _bibleChapter - 1,
      'vStart': _bibleVerseStart,
      'vEnd': _bibleVerseEnd,
    };

    if (cloudSessionId != null) {
      await CloudRemoteBridge.sendCommand(cloudSessionId!, 'project_verse', payload: payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proyectando ${_bibleBooks[_bibleBook]} $_bibleChapter:$_bibleVerseStart vía Puente Nube',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        _tabController.animateTo(0);
      }
      return;
    }

    if (url == null) return;
    try {
      await http
          .post(
            Uri.parse('$url/project_verse'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(milliseconds: 3000));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proyectando ${_bibleBooks[_bibleBook]} $_bibleChapter:$_bibleVerseStart',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        _tabController.animateTo(0); // switch to teleprompter tab
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // ── QR / Connection screen ─────────────────────────────────────────────
    if (url == null && cloudSessionId == null) {
      return _buildConnectionScreen();
    }

    // ── Connected screen ───────────────────────────────────────────────────
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
            _send('/next');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp ||
              event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
            _send('/prev');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
            _send('/black');
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xff091116),
        appBar: AppBar(
          backgroundColor: const Color(0xff0d161d),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    cloudSessionId != null ? 'Remoto Nube ($cloudSessionId)' : 'Control Remoto',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    connected ? (cloudSessionId != null ? Icons.cloud_done : Icons.wifi) : Icons.wifi_off,
                    color: connected ? Colors.greenAccent : Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    connected ? 'Conectado' : 'Sin señal',
                    style: TextStyle(
                      color: connected ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _clockDisplay,
                    style: const TextStyle(
                      color: Color(0xff64748b),
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xff0284c7),
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xff64748b),
            tabs: const [
              Tab(icon: Icon(Icons.slideshow, size: 18), text: 'PANTALLA'),
              Tab(icon: Icon(Icons.list, size: 18), text: 'PLAN'),
              Tab(icon: Icon(Icons.menu_book, size: 18), text: 'BIBLIA'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Desconectar',
              icon: const Icon(Icons.link_off, size: 20),
              onPressed: _disconnect,
            ),
          ],
        ),
        body: OperationalBackground(
          child: Column(
            children: [
              // ── Countdown banner ──────────────────────────────────────────────
              if (countdownEndsAt != null) _buildCountdownBanner(),

              // ── Blackout banner ───────────────────────────────────────────────
              if (blackout)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Text(
                    '⬛ PANTALLA NEGRA ACTIVA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

              // ── Tab views ─────────────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTeleprompterTab(),
                    _buildPlanTab(),
                    _buildBibleTab(),
                  ],
                ),
              ),

              // ── Control bar (always visible) ──────────────────────────────────
              _buildControlBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Countdown banner ────────────────────────────────────────────────────────
  Widget _buildCountdownBanner() {
    final display = _formatCountdown();
    final remaining = countdownEndsAt! - DateTime.now().millisecondsSinceEpoch;
    final isUrgent = remaining < 60000;
    return Container(
      width: double.infinity,
      color: isUrgent ? Colors.red.shade900 : const Color(0xff1c3547),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.timer,
            color: isUrgent ? Colors.redAccent : Colors.blueAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Cuenta regresiva: $display',
            style: TextStyle(
              color: isUrgent ? Colors.redAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Teleprompter tab ─────────────────────────────────────────────────────────
  Widget _buildTeleprompterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress row
          if (planCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff152030),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list, color: Color(0xff64748b), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        planIndex >= 0
                            ? 'Sección ${planIndex + 1} de $planCount · ${planItems.isNotEmpty && planIndex < planItems.length ? planItems[planIndex]['title'] : currentTitle}'
                            : 'Sin sección activa',
                        style: const TextStyle(
                          color: Color(0xff94a3b8),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Private preacher notes banner
          if (currentNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xff2d2305),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff78590e)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.note_alt,
                          size: 15,
                          color: Color(0xfff59e0b),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'NOTAS PRIVADAS DEL GUÍA / PREDICADOR',
                          style: TextStyle(
                            color: Color(0xfff59e0b),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currentNotes,
                      style: const TextStyle(
                        color: Color(0xfffef3c7),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Current slide
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xff182229),
              borderRadius: BorderRadius.circular(14),
              border: const Border(
                left: BorderSide(color: Color(0xff10b981), width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      currentLabel.isNotEmpty
                          ? currentLabel.toUpperCase()
                          : 'EN PANTALLA',
                      style: const TextStyle(
                        color: Color(0xff10b981),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$slideIndex / $totalSlides',
                      style: const TextStyle(
                        color: Color(0xff64748b),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (currentTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      currentTitle,
                      style: const TextStyle(
                        color: Color(0xff94a3b8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  currentText.isNotEmpty ? currentText : '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Next slide
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xff131e26),
              borderRadius: BorderRadius.circular(14),
              border: const Border(
                left: BorderSide(color: Color(0xff334155), width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nextLabel.isNotEmpty
                      ? 'A CONTINUACIÓN · ${nextLabel.toUpperCase()}'
                      : 'A CONTINUACIÓN',
                  style: const TextStyle(
                    color: Color(0xff94a3b8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  nextText.isNotEmpty
                      ? nextText
                      : 'Fin de la presentación / Sin más diapositivas',
                  style: const TextStyle(
                    color: Color(0xffcbd5e1),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Plan tab ─────────────────────────────────────────────────────────────────
  Widget _buildPlanTab() {
    if (planItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_remove, color: Color(0xff334155), size: 48),
            SizedBox(height: 12),
            Text(
              'El Orden de Culto está vacío\no no hay conexión activa',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff64748b)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: planItems.length,
      itemBuilder: (context, i) {
        final item = planItems[i];
        final isActive = i == planIndex;
        final notes = item['notes'] as String? ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xff0c2d4a) : const Color(0xff182229),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: isActive
                    ? const Color(0xff0284c7)
                    : const Color(0xff233138),
                width: isActive ? 4 : 1,
              ),
            ),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: isActive
                  ? const Color(0xff0284c7)
                  : const Color(0xff1e3547),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : const Color(0xff94a3b8),
                ),
              ),
            ),
            title: Text(
              item['title'] as String? ?? '',
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xffcbd5e1),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            subtitle: notes.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.note_alt,
                          size: 12,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            notes,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: isActive
                ? const Icon(Icons.arrow_right, color: Color(0xff0284c7))
                : null,
            onTap: () => _send('/jump/$i'),
          ),
        );
      },
    );
  }

  // ── Bible tab ─────────────────────────────────────────────────────────────────
  Widget _buildBibleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Proyectar versículo',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecciona libro, capítulo y versículo. Al presionar "Proyectar", el versículo aparecerá en la pantalla principal.',
            style: TextStyle(color: Color(0xff64748b), fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Book selector
          const Text(
            'Libro',
            style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xff182229),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xff233138)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _bibleBook,
                dropdownColor: const Color(0xff182229),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                items: [
                  for (int i = 0; i < _bibleBooks.length; i++)
                    DropdownMenuItem(value: i, child: Text(_bibleBooks[i])),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _bibleBook = v;
                      _bibleChapter = 1;
                      _bibleVerseStart = 1;
                      _bibleVerseEnd = 1;
                    });
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Chapter, verse start, verse end in a row
          Row(
            children: [
              // Chapter
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Capítulo',
                      style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _numberField(
                      value: _bibleChapter,
                      min: 1,
                      onChanged: (v) => setState(() {
                        _bibleChapter = v;
                        _bibleVerseStart = 1;
                        _bibleVerseEnd = 1;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Verse start
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Versículo',
                      style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _numberField(
                      value: _bibleVerseStart,
                      min: 1,
                      onChanged: (v) => setState(() {
                        _bibleVerseStart = v;
                        if (_bibleVerseEnd < v) _bibleVerseEnd = v;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Verse end
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hasta',
                      style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _numberField(
                      value: _bibleVerseEnd,
                      min: _bibleVerseStart,
                      onChanged: (v) => setState(() => _bibleVerseEnd = v),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Preview label
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff152030),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.preview, color: Color(0xff64748b), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_bibleBooks[_bibleBook]} $_bibleChapter:$_bibleVerseStart${_bibleVerseEnd > _bibleVerseStart ? "-$_bibleVerseEnd" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Project button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.cast),
              label: const Text(
                'PROYECTAR ESTE VERSÍCULO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: connected ? _sendProjectVerse : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required int value,
    required int min,
    required void Function(int) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff182229),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff233138)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16, color: Color(0xff64748b)),
            onPressed: value > min ? () => onChanged(value - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: Color(0xff64748b)),
            onPressed: () => onChanged(value + 1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
          ),
        ],
      ),
    );
  }

  // ── Control bar (always visible at bottom) ────────────────────────────────
  Widget _buildControlBar() {
    return OperationalSurface(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section nav
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _send('/prev_section'),
                  icon: const Icon(Icons.skip_previous, size: 15),
                  label: const Text(
                    'Sec. Anterior',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Color(0xff1a2730)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _send('/next_section'),
                  icon: const Icon(Icons.skip_next, size: 15),
                  label: const Text(
                    'Sig. Sección',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Color(0xff1a2730)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Main nav
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff1c2b35),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => _send('/prev'),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 17),
                    label: const Text(
                      'ANT',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0284c7),
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => _send('/next'),
                    icon: const Icon(Icons.arrow_forward_ios, size: 19),
                    label: const Text(
                      'SIGUIENTE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blackout
                          ? Colors.red.shade700
                          : const Color(0xff3f1b24),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => _send('/black'),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          blackout ? Icons.visibility : Icons.visibility_off,
                          size: 19,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          blackout ? 'VER' : 'NEGRO',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Connection / QR screen ───────────────────────────────────────────────────
  Widget _buildConnectionScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar al Control Remoto')),
      backgroundColor: const Color(0xff081116),
      body: OperationalBackground(
        child: Column(
          children: [
            if (myIp != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.blue.shade900,
                width: double.infinity,
                child: Text(
                  'IP de este celular: $myIp',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Cloud Session or Manual IP input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OperationalSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.cloud_sync, color: Color(0xff38bdf8), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Puente Nube (Web y Cualquier Red)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cloudCodeController,
                            style: const TextStyle(
                              color: Colors.white,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'CÓDIGO (Ej. 7K9X2B)',
                              hintStyle: const TextStyle(color: Color(0xff64748b), letterSpacing: 1),
                              filled: true,
                              fillColor: const Color(0xff182229),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (code) {
                              if (code.trim().isNotEmpty) {
                                _connectToCloud(code);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff0284c7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () {
                            if (_cloudCodeController.text.trim().isNotEmpty) {
                              _connectToCloud(_cloudCodeController.text);
                            }
                          },
                          icon: const Icon(Icons.flash_on, size: 18),
                          label: const Text('Enlazar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xff233138)),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.wifi, color: Color(0xff10b981), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'O Conexión Wi-Fi Local (IP directa)',
                          style: TextStyle(
                            color: Color(0xff94a3b8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final field = TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _connectTo,
                          decoration: InputDecoration(
                            hintText: '192.168.1.5:8765',
                            hintStyle: const TextStyle(color: Color(0xff64748b)),
                            filled: true,
                            fillColor: const Color(0xff182229),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        );
                        final connect = OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xff334155)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () => _connectTo(_ipController.text),
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Conectar IP'),
                        );
                        return Row(
                          children: [
                            Expanded(child: field),
                            const SizedBox(width: 8),
                            connect,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Recent IPs
            if (_recentIps.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recientes',
                    style: TextStyle(
                      color: Color(0xff64748b),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _recentIps.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final ip = _recentIps[index];
                    return ActionChip(
                      avatar: const Icon(Icons.history, size: 17),
                      label: Text(ip),
                      backgroundColor: const Color(0xff182b35),
                      side: const BorderSide(color: Color(0xff35505d)),
                      labelStyle: const TextStyle(color: Color(0xffcbd5e1)),
                      onPressed: () => _connectTo(ip),
                    );
                  },
                ),
              ),
            ],

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'O escanea el código QR de la PC',
                style: TextStyle(color: Color(0xff64748b), fontSize: 13),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: MobileScanner(
                    tapToFocus: true,
                    placeholderBuilder: (context) => const ColoredBox(
                      color: Color(0xff101c23),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorBuilder: (context, error) => const ColoredBox(
                      color: Color(0xff101c23),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.no_photography_outlined,
                                color: Color(0xfffca5a5),
                                size: 42,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No se pudo abrir la cámara. Conecta escribiendo la dirección de la computadora.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    overlayBuilder: (context, constraints) => Center(
                      child: IgnorePointer(
                        child: Container(
                          width: constraints.maxWidth * .68,
                          height: constraints.maxWidth * .68,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xff5eead4),
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ),
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty &&
                          barcodes.first.rawValue != null) {
                        final detected = barcodes.first.rawValue!.trim();
                        if (detected.startsWith('CLOUD:') ||
                            (detected.length >= 4 && detected.length <= 10 && !detected.contains('.') && !detected.contains(':')) ||
                            normalizeRemoteAddress(detected) != null) {
                          _connectTo(detected);
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
