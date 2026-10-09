import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gemini_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  ChatMessage(this.text, this.isUser, {this.isError = false});
}

class DoctrinalAiDialog extends ConsumerStatefulWidget {
  const DoctrinalAiDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DoctrinalAiDialog(),
    );
  }

  @override
  ConsumerState<DoctrinalAiDialog> createState() => _DoctrinalAiDialogState();
}

class _DoctrinalAiDialogState extends ConsumerState<DoctrinalAiDialog> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _lastFailedMessage;

  @override
  void initState() {
    super.initState();
    _checkInit();
  }

  Future<void> _checkInit() async {
    final gemini = ref.read(geminiServiceProvider);
    if (gemini.isInitialized) {
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _messages.add(
          ChatMessage(
            '¡Paz a vosotros! Consulto los 40 Puntos de Fe oficiales y la '
            'Biblia Reina-Valera 1909. Cada respuesta doctrinal incluirá '
            'las fuentes recuperadas.',
            false,
          ),
        );
      });
    }
  }

  Future<void> _initKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    final gemini = ref.read(geminiServiceProvider);
    try {
      await gemini.initialize(key);
      _apiKeyController.clear();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _lastFailedMessage = null;
        _messages.add(
          ChatMessage(
            '¡Paz a vosotros! Consulto los 40 Puntos de Fe oficiales y la '
            'Biblia Reina-Valera 1909. Cada respuesta doctrinal incluirá '
            'las fuentes recuperadas.',
            false,
          ),
        );
      });
    } on GeminiServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _sendMessage({String? retryText}) async {
    if (_isLoading) return;
    final text = retryText ?? _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      if (retryText == null) _messages.add(ChatMessage(text, true));
      _isLoading = true;
      _lastFailedMessage = null;
    });
    if (retryText == null) _textController.clear();
    _scrollToBottom();

    try {
      final gemini = ref.read(geminiServiceProvider);
      final response = await gemini.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(response.displayText, false));
      });
    } on GeminiServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(error.message, false, isError: true));
        if (error.canRetry) _lastFailedMessage = text;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            'No fue posible comunicarse con Gemini. Revisa la conexión e inténtalo nuevamente.',
            false,
            isError: true,
          ),
        );
        _lastFailedMessage = text;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.blueAccent),
                    SizedBox(width: 10),
                    Text(
                      'Asistente Doctrinal IA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_isInitialized)
                      IconButton(
                        tooltip: 'Cambiar API Key',
                        icon: const Icon(Icons.key, size: 20),
                        onPressed: () {
                          ref.read(geminiServiceProvider).clearCredentials();
                          setState(() {
                            _isInitialized = false;
                            _lastFailedMessage = null;
                            _messages.clear();
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: !_isInitialized ? _buildConfigView() : _buildChatView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.vpn_key, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Configurar Asistente IA',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ingresa una API Key de Google AI Studio. La llave se conserva únicamente durante esta sesión y no se guarda en el dispositivo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Las respuestas se limitan al corpus local: 40 Puntos de Fe '
              'oficiales y Biblia Reina-Valera 1909. Se mostrarán las fuentes '
              'consultadas; las decisiones sensibles deben confirmarse con '
              'el pastor o la comisión doctrinal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Google Gemini API Key',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _initKey,
              child: const Text('Usar durante esta sesión'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                alignment: msg.isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 450),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? const Color(0xff2c4d60)
                        : msg.isError
                        ? Theme.of(context).colorScheme.errorContainer
                        : Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: msg.isError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text(
                  'Consultando Gemini; puede realizar reintentos automáticos…',
                ),
              ],
            ),
          ),
        if (!_isLoading && _lastFailedMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => _sendMessage(retryText: _lastFailedMessage),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar última pregunta'),
            ),
          ),
        Text(
          'Modelo: ${ref.read(geminiServiceProvider).activeModelName ?? 'sin configurar'} '
          '· Corpus local: ${ref.read(geminiServiceProvider).corpusStats.totalDocuments} fuentes '
          '· API Key sólo en esta sesión',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Pregunta algo doctrinal...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                enabled: !_isLoading,
                maxLength: GeminiService.maxQuestionCharacters,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              color: Colors.blueAccent,
              onPressed: _isLoading ? null : _sendMessage,
            ),
          ],
        ),
      ],
    );
  }
}
