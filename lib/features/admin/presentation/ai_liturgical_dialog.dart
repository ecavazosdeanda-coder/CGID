import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai_assistant/services/gemini_service.dart';

class AiLiturgicalDialog extends ConsumerStatefulWidget {
  final String? initialTopic;

  const AiLiturgicalDialog({super.key, this.initialTopic});

  static Future<void> show(BuildContext context, {String? initialTopic}) {
    return showDialog(
      context: context,
      builder: (_) => AiLiturgicalDialog(initialTopic: initialTopic),
    );
  }

  @override
  ConsumerState<AiLiturgicalDialog> createState() => _AiLiturgicalDialogState();
}

class _AiLiturgicalDialogState extends ConsumerState<AiLiturgicalDialog> {
  late TextEditingController _topicController;
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isLoading = false;
  String? _suggestions;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _topicController = TextEditingController(text: widget.initialTopic ?? '');
  }

  @override
  void dispose() {
    _topicController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _generateSuggestions() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe el tema de predicación o pasaje bíblico.'),
        ),
      );
      return;
    }

    final gemini = ref.read(geminiServiceProvider);
    if (!gemini.isInitialized) {
      final key = _apiKeyController.text.trim();
      if (key.isEmpty) {
        setState(() {
          _errorMessage = 'Por favor ingresa una API Key de Google AI Studio para continuar.';
        });
        return;
      }
      try {
        await gemini.initialize(key);
      } catch (e) {
        setState(() => _errorMessage = 'Error inicializando Gemini: $e');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _suggestions = null;
    });

    try {
      final prompt =
          '''
Eres el Asistente Litúrgico y Pastoral de la Conferencia General de la Iglesia de Dios.
El ministro predicará sobre el siguiente tema o pasaje bíblico:
"$topic"

Por favor, proporciona una propuesta litúrgica armónica y solemne con:
1. 🎵 **3 Himnos Recomendados del Himnario Oficial:**
   - Indica el número aproximado y título del himno, explicando brevemente por qué encaja con el mensaje.
2. 📖 **2 Lecturas Bíblicas de Acompañamiento (Reina-Valera 1909):**
   - Una para la lectura introductoria y otra para el momento de reflexión u ofrenda.
3. 🙏 **Propuesta de Enfoque de Oración:**
   - Un breve motivo de oración enfocado en el mensaje para guiar a la congregación.

Mantén tu respuesta organizada, concisa y basada en la sana doctrina de los 32 Puntos de Fe de la Iglesia de Dios.
''';

      final response = await gemini.sendMessage(prompt);
      if (mounted) {
        setState(() {
          _suggestions = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al consultar a Gemini: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gemini = ref.watch(geminiServiceProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.blueAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Asistente Litúrgico Inteligente (IA)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Sugerencia de himnos y lecturas según el tema del sermón',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.7),
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
              const SizedBox(height: 16),

              // API Key input if not initialized
              if (!gemini.isInitialized) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.key, size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Text(
                            'Ingresa tu Google AI Studio API Key:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'AIzaSy...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Topic Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _topicController,
                      decoration: const InputDecoration(
                        labelText: 'Tema de Predicación o Pasaje Bíblico',
                        hintText: 'Ej. La Armadura de Dios, Efesios 6:10-18',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.campaign_outlined),
                      ),
                      onSubmitted: (_) => _generateSuggestions(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Consultar'),
                    onPressed: _isLoading ? null : _generateSuggestions,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),

              // Results Area
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Analizando el tema con los 32 Puntos de Fe y el Himnario...',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _suggestions != null
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.15),
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _suggestions!,
                            style: const TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 48,
                              color: Colors.grey.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Escribe el tema de tu sermón arriba para recibir sugerencias litúrgicas.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 14),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_suggestions != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar Propuesta'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _suggestions!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Sugerencias litúrgicas copiadas al portapapeles.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
