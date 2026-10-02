import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

class GeminiServiceException implements Exception {
  final String message;
  final bool canRetry;

  const GeminiServiceException(this.message, {this.canRetry = false});

  @override
  String toString() => message;
}

class GeminiService {
  static const _modelNames = ['gemini-3.8-flash', 'gemini-3.5-flash-lite'];
  static final _systemInstruction = Content.system(
    'Eres el Asistente Doctrinal de la Conferencia General de la Iglesia de Dios. '
    'Tu propósito es responder dudas teológicas y ayudar a los directores a planear cultos litúrgicos. '
    'Debes basar todas tus respuestas ESTRICTAMENTE en los 32 Puntos de Fe de la Iglesia de Dios y la Biblia Reina-Valera 1909. '
    'Si te preguntan algo fuera de la doctrina (ej. política, programación, etc.), responde amablemente que solo estás autorizado para temas doctrinales y de planeación de cultos. '
    'Tu tono debe ser respetuoso, pastoral y teológico. '
    'Si no tienes base suficiente para una afirmación, dilo claramente y pide verificar la respuesta con las fuentes oficiales.',
  );

  GenerativeModel? _model;
  String? _apiKey;
  String? _detectedModel;
  int _modelIndex = 0;
  final List<Content> _history = [];

  String? get activeModelName => _detectedModel;
  bool get isInitialized => _model != null && _apiKey != null;

  Future<void> initialize(String apiKey) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw const GeminiServiceException(
        'Ingresa una API Key de Google AI Studio.',
      );
    }
    _apiKey = normalizedKey;
    _modelIndex = 0;
    _history.clear();
    _selectModel(_modelNames[_modelIndex]);
  }

  void _selectModel(String modelName) {
    _detectedModel = modelName;
    _model = GenerativeModel(
      model: modelName,
      apiKey: _apiKey!,
      systemInstruction: _systemInstruction,
    );
  }

  Future<String> sendMessage(String message) async {
    final normalizedMessage = message.trim();
    if (!isInitialized) {
      throw const GeminiServiceException(
        'El Asistente no ha sido configurado con una API Key.',
      );
    }
    if (normalizedMessage.isEmpty) {
      throw const GeminiServiceException(
        'Escribe una pregunta antes de enviarla.',
      );
    }

    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final userContent = Content.text(normalizedMessage);
        final response = await _model!.generateContent([
          ..._history,
          userContent,
        ]);
        final text = response.text?.trim();
        if (text == null || text.isEmpty) {
          throw const GeminiServiceException(
            'Gemini respondió sin texto. Intenta formular la pregunta de otra manera.',
            canRetry: true,
          );
        }
        _history
          ..add(userContent)
          ..add(response.candidates.first.content);
        return text;
      } catch (error) {
        lastError = error;
        if (!_isTransient(error) || attempt == 3) break;

        // Tras dos intentos con el modelo principal, usa una alternativa de
        // menor demanda sin perder el historial confirmado de la conversación.
        if (attempt == 1 && _modelIndex + 1 < _modelNames.length) {
          _modelIndex++;
          _selectModel(_modelNames[_modelIndex]);
        }
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }

    throw _friendlyException(lastError!);
  }

  static bool _isTransient(Object error) {
    if (error is GeminiServiceException) return error.canRetry;
    final value = error.toString().toLowerCase();
    return value.contains('503') ||
        value.contains('unavailable') ||
        value.contains('high demand') ||
        value.contains('429') ||
        value.contains('resource_exhausted') ||
        value.contains('408') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('500') ||
        value.contains('502') ||
        value.contains('504') ||
        value.contains('network') ||
        value.contains('socket');
  }

  static GeminiServiceException _friendlyException(Object error) {
    if (error is GeminiServiceException) return error;
    final value = error.toString().toLowerCase();
    if (value.contains('api key') ||
        value.contains('401') ||
        value.contains('403') ||
        value.contains('permission_denied')) {
      return const GeminiServiceException(
        'Google rechazó la API Key. Comprueba que sea válida y que tenga acceso a la API de Gemini.',
      );
    }
    if (value.contains('quota') || value.contains('billing')) {
      return const GeminiServiceException(
        'La cuota de Gemini para esta API Key se agotó. Revisa sus límites en Google AI Studio.',
        canRetry: true,
      );
    }
    if (_isTransient(error)) {
      return const GeminiServiceException(
        'El servicio de Gemini está temporalmente saturado o no responde. '
        'Ya se intentó nuevamente con espera gradual y con un modelo alternativo. '
        'Espera un momento y pulsa “Reintentar”.',
        canRetry: true,
      );
    }
    return const GeminiServiceException(
      'No fue posible obtener una respuesta de Gemini. Revisa la conexión y la configuración de la API Key.',
      canRetry: true,
    );
  }

  void resetChat() {
    _history.clear();
    if (_apiKey != null) {
      _modelIndex = 0;
      _selectModel(_modelNames[_modelIndex]);
    }
  }

  void clearCredentials() {
    _history.clear();
    _apiKey = null;
    _model = null;
    _detectedModel = null;
    _modelIndex = 0;
  }
}
