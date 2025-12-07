import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({super.key});

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LLMService _llmService = LLMService();
  final TTSService _ttsService = TTSService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  final List<Message> _history = [];
  bool _isLoading = false;
  bool _isRecording = false;
  String? _currentStreamingMessage;

  @override
  void initState() {
    super.initState();
    _history.add(
      Message(
        role: MessageRole.system,
        content: 'Connected to Gemini 2.0 Flash Lite. Ready to chat!',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _ttsService.stop();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/temp_audio.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );

        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        final file = File(path);
        final bytes = await file.readAsBytes();
        _sendAudioMessage(bytes);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _sendAudioMessage(List<int> audioBytes) async {
    if (_isLoading) return;

    setState(() {
      _history.add(
        Message(role: MessageRole.user, content: '🎤 [Audio Message]'),
      );
      _isLoading = true;
      _currentStreamingMessage = '';
    });
    _scrollToBottom();

    try {
      final stream = _llmService.streamAudioChat(audioBytes);
      String fullResponse = '';

      await for (final chunk in stream) {
        if (mounted) {
          fullResponse += chunk;
          setState(() {
            _currentStreamingMessage = (_currentStreamingMessage ?? '') + chunk;
          });
          _scrollToBottom();
        }
      }

      if (mounted) {
        setState(() {
          _history.add(
            Message(
              role: MessageRole.assistant,
              content: _currentStreamingMessage ?? '',
            ),
          );
          _currentStreamingMessage = null;
          _isLoading = false;
        });

        // Speak the response
        _ttsService.speak(fullResponse);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _history.add(Message(role: MessageRole.system, content: 'Error: $e'));
          _isLoading = false;
          _currentStreamingMessage = null;
        });
      }
    }
  }

  Future<void> _sendMessage(String text) async {
    if (_isLoading) return;

    _controller.clear();
    setState(() {
      _history.add(Message(role: MessageRole.user, content: text));
      _isLoading = true;
      _currentStreamingMessage = '';
    });
    _scrollToBottom();

    try {
      final stream = _llmService.streamChat(text);

      await for (final chunk in stream) {
        if (mounted) {
          setState(() {
            _currentStreamingMessage = (_currentStreamingMessage ?? '') + chunk;
          });
          _scrollToBottom();
        }
      }

      if (mounted) {
        setState(() {
          _history.add(
            Message(
              role: MessageRole.assistant,
              content: _currentStreamingMessage ?? '',
            ),
          );
          _currentStreamingMessage = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _history.add(Message(role: MessageRole.system, content: 'Error: $e'));
          _isLoading = false;
          _currentStreamingMessage = null;
        });
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1329).withOpacity(0.95),
        border: Border(
          left: BorderSide(color: const Color(0xFF00FFFF).withOpacity(0.3)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(-5, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF00FFFF).withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.smart_toy, color: Color(0xFF00FFFF)),
                const SizedBox(width: 8),
                const Text(
                  'GEMINI AI',
                  style: TextStyle(
                    color: Color(0xFF00FFFF),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00FF88),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF88).withOpacity(0.5),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount:
                  _history.length + (_currentStreamingMessage != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _history.length) {
                  // Streaming message
                  return _buildMessageBubble(
                    Message(
                      role: MessageRole.assistant,
                      content: _currentStreamingMessage!,
                    ),
                    isStreaming: true,
                  );
                }
                return _buildMessageBubble(_history[index]);
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: const Color(0xFF00FFFF).withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ask something...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: const Color(0xFF00FFFF).withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: const Color(0xFF00FFFF).withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF00FFFF)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0A0E27),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (text) {
                      if (text.isNotEmpty) _sendMessage(text);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_controller.text.isNotEmpty) {
                            _sendMessage(_controller.text.trim());
                          }
                        },
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFFF).withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: const Color(0xFF00FFFF).withOpacity(0.3),
                      ),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00FFFF),
                            ),
                          ),
                        )
                      : const Icon(Icons.send, color: Color(0xFF00FFFF)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? const Color(0xFFFF0040).withOpacity(0.2)
                          : const Color(0xFF00FFFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isRecording
                            ? const Color(0xFFFF0040)
                            : const Color(0xFF00FFFF).withOpacity(0.3),
                      ),
                      boxShadow: _isRecording
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF0040).withOpacity(0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      Icons.mic,
                      color: _isRecording
                          ? const Color(0xFFFF0040)
                          : const Color(0xFF00FFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, {bool isStreaming = false}) {
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;

    if (isSystem) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            message.content,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF00FFFF).withOpacity(0.1)
              : const Color(0xFF1A1F3A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(12),
          ),
          border: Border.all(
            color: isUser
                ? const Color(0xFF00FFFF).withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const Text(
                'GEMINI',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
            ],
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: Colors.white),
                a: const TextStyle(
                  color: Color(0xFF00FFFF),
                  decoration: TextDecoration.underline,
                ),
                code: const TextStyle(
                  backgroundColor: Color(0xFF0A0E27),
                  color: Color(0xFF00FF88),
                  fontFamily: 'monospace',
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF0A0E27),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(height: 4),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF00FF88),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Simple Message class to replace Ollama's
class Message {
  final MessageRole role;
  final String content;

  Message({required this.role, required this.content});
}

enum MessageRole { user, assistant, system }
