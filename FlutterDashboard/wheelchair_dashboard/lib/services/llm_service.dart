import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class LLMService {
  GenerativeModel? _model;
  ChatSession? _chat;

  // Default model
  final String _modelName = 'gemini-2.0-flash-lite-preview-02-05';
  // Hardcoded API Key
  final String _apiKey = 'AIzaSyCf45W5GLCDyoPoW_gt7PukuUUrPOqttdc';

  LLMService() {
    _model = GenerativeModel(model: _modelName, apiKey: _apiKey);
    _chat = _model!.startChat();
  }

  bool get hasApiKey => true;

  /// Sets the API Key (No-op now as it is hardcoded)
  void setApiKey(String key) {
    // No-op
  }

  /// Streams a chat response with audio input
  Stream<String> streamAudioChat(List<int> audioBytes) async* {
    if (_model == null || _chat == null) {
      yield 'Error: Model not initialized.';
      return;
    }

    try {
      final content = Content.multi([
        TextPart('Please listen to this audio and respond.'),
        DataPart('audio/wav', Uint8List.fromList(audioBytes)),
      ]);

      final response = _chat!.sendMessageStream(content);
      await for (final chunk in response) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      yield 'Error: $e';
    }
  }

  /// Streams a chat response
  Stream<String> streamChat(String prompt) async* {
    if (_model == null || _chat == null) {
      yield 'Error: Model not initialized.';
      return;
    }

    try {
      final response = _chat!.sendMessageStream(Content.text(prompt));
      await for (final chunk in response) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      yield 'Error: $e';
    }
  }

  /// Resets the chat session
  void clearChat() {
    if (_model != null) {
      _chat = _model!.startChat();
    }
  }
}
