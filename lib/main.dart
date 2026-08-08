import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/audio_engine.dart';
import 'state/piano_controller.dart';
import 'state/settings_controller.dart';
import 'screens/gesture_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gesture play + camera preview are designed for portrait; lock to it so the
  // camera orientation and the hand overlay stay aligned.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  final AudioEngine audio = AudioEngine();
  await audio.init();

  final SettingsController settings = SettingsController(audio);
  await settings.load();

  final PianoController piano = PianoController(audio, settings);

  runApp(ArSynthApp(audio: audio, settings: settings, piano: piano));
}

class ArSynthApp extends StatelessWidget {
  const ArSynthApp({
    super.key,
    required this.audio,
    required this.settings,
    required this.piano,
  });

  final AudioEngine audio;
  final SettingsController settings;
  final PianoController piano;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AudioEngine>.value(value: audio),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<PianoController>.value(value: piano),
      ],
      child: MaterialApp(
        title: 'AR Synth',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // Launch straight into the camera instrument; Settings is reachable from
        // its app bar. The old landing screen (HomeScreen) is no longer routed.
        home: const GestureScreen(),
      ),
    );
  }
}
