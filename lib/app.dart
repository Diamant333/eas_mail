import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:provider/provider.dart';

import 'services/mail_session.dart';
import 'ui/screens/mail_shell.dart';
import 'ui/screens/login_screen.dart';

class EasMailApp extends StatelessWidget {
  const EasMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MailSession()..restoreSession(),
      child: const _AppWithSplash(),
    );
  }
}

class _AppWithSplash extends StatefulWidget {
  const _AppWithSplash();

  @override
  State<_AppWithSplash> createState() => _AppWithSplashState();
}

class _AppWithSplashState extends State<_AppWithSplash> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final settings = session.settings;

    return MaterialApp(
      title: settings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      home: _showSplash ? _SplashScreen(settings: settings) : const _Root(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.settings});

  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final splashPath = settings.splashImagePath as String?;
    final appName = settings.appName as String;

    Widget imageWidget;
    if (splashPath != null && !kIsWeb) {
      final file = File(splashPath);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
        );
      } else {
        imageWidget = _defaultLogo(context);
      }
    } else {
      imageWidget = _defaultLogo(context);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            imageWidget,
            const SizedBox(height: 24),
            Text(
              appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _defaultLogo(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.mail_outline,
        size: 64,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();

    // Still loading initial session.
    if (session.loading && !session.isSignedIn && session.accounts.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (session.isSignedIn) {
      return const MailShell();
    }

    // Has saved accounts but failed to reconnect — show shell with error.
    if (session.accounts.isNotEmpty) {
      return const MailShell();
    }

    return const LoginScreen();
  }
}
