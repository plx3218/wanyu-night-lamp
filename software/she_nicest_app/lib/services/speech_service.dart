import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  Future<bool> init() async {
    _available = await _speech.initialize(
      onError: (e) => _available = false,
      onStatus: (_) {},
    );
    return _available;
  }

  bool get isAvailable => _available;

  bool get isListening => _speech.isListening;

  void startListening(Function(String) onResult, Function() onDone) {
    if (!_available) return;
    _speech.listen(
      onResult: (r) {
        if (r.recognizedWords.isNotEmpty) {
          onResult(r.recognizedWords);
        }
        if (r.finalResult) {
          onDone();
        }
      },
      localeId: 'zh_CN',
      listenMode: ListenMode.dictation,
    );
  }

  void stop() {
    _speech.stop();
  }
}
