import 'package:flutter/material.dart';
import 'package:watchtower/watchtower.dart';

// flutter run --dart-define=WT_PUBLISHABLE_KEY=wtp_... --dart-define=WT_RELEASE=1.0.0
void main() {
  Watchtower.runGuarded(WatchtowerOptions.fromEnvironment(), () {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(MaterialApp(
      navigatorObservers: [WatchtowerNavigatorObserver()],
      routes: {'/': (_) => const Home()},
    ));
  });
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => throw StateError('test error from the example app'),
            child: const Text('Throw'),
          ),
        ),
      );
}
