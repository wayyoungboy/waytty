library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/messages.g.dart';

/// Only application-authored messages go through translation. Dynamic user
/// labels, file contents, terminal output, and protocol values stay verbatim.
class LRaw {
  const LRaw(this.value);
  final Object? value;
}

class LMessage {
  const LMessage(this.source, this.arguments);
  final String source;
  final List<Object?> arguments;
}

class WayttyStrings {
  const WayttyStrings(this.locale);
  final Locale locale;
  static const supportedLocales = [Locale('zh', 'CN'), Locale('en')];
  static const delegates = <LocalizationsDelegate<dynamic>>[
    _StringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static WayttyStrings of(BuildContext context) =>
      Localizations.of<WayttyStrings>(context, WayttyStrings) ??
      WayttyStrings(
        Localizations.maybeLocaleOf(context) ?? const Locale('zh', 'CN'),
      );
  String resolve(Object? value) {
    if (value is LRaw) return '${value.value}';
    final source = value is LMessage ? value.source : '$value';
    final translated = wayttyMessages[locale.languageCode]?[source] ?? source;
    if (value is! LMessage) return translated;
    return translated.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      if (index >= value.arguments.length) return match[0]!;
      final argument = value.arguments[index];
      return argument is LMessage || argument is LRaw
          ? resolve(argument)
          : '$argument';
    });
  }
}

String tr(BuildContext context, Object? message) =>
    WayttyStrings.of(context).resolve(message);

class _StringsDelegate extends LocalizationsDelegate<WayttyStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => {'zh', 'en'}.contains(locale.languageCode);
  @override
  Future<WayttyStrings> load(Locale locale) =>
      SynchronousFuture(WayttyStrings(locale));
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

/// A normal Text widget with deferred translation, so const widget subtrees
/// still react to Localizations changes without translating user data.
class LText extends StatelessWidget {
  const LText(
    this.message, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  final Object? message;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel, semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, message),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null ? null : tr(context, semanticsLabel),
    semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}

class WayttyLanguage extends ValueNotifier<Locale> {
  WayttyLanguage() : super(const Locale('zh', 'CN'));
  static final instance = WayttyLanguage();
  static const preferenceKey = 'waytty.locale';
  Future<void>? _pendingWrite;
  static const _nativeMenus = MethodChannel('waytty/localization');
  static const _menuSources = [
    'About waytty',
    'Preferences…',
    'Services',
    'Hide waytty',
    'Hide Others',
    'Show All',
    'Quit waytty',
    'Edit',
    'Undo',
    'Redo',
    'Cut',
    'Copy',
    'Paste',
    'Paste and Match Style',
    'Delete',
    'Select All',
    'Find',
    'Find…',
    'Find and Replace…',
    'Find Next',
    'Find Previous',
    'Use Selection for Find',
    'Jump to Selection',
    'Spelling and Grammar',
    'Spelling',
    'Show Spelling and Grammar',
    'Check Document Now',
    'Check Spelling While Typing',
    'Check Grammar With Spelling',
    'Correct Spelling Automatically',
    'Substitutions',
    'Show Substitutions',
    'Smart Copy/Paste',
    'Smart Quotes',
    'Smart Dashes',
    'Smart Links',
    'Data Detectors',
    'Text Replacement',
    'Transformations',
    'Make Upper Case',
    'Make Lower Case',
    'Capitalize',
    'Speech',
    'Start Speaking',
    'Stop Speaking',
    'View',
    'Enter Full Screen',
    'Exit Full Screen',
    'Window',
    'Minimize',
    'Zoom',
    'Bring All to Front',
    'Help',
  ];
  Future<void> restore() async {
    if (_pendingWrite != null) await _pendingWrite;
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getString(preferenceKey) == 'en'
        ? const Locale('en')
        : const Locale('zh', 'CN');
    await _syncNativeMenus();
  }

  Future<void> select(String code) async {
    if (!{'zh', 'en'}.contains(code)) throw ArgumentError('Unsupported locale');
    final previous = _pendingWrite;
    final completed = Completer<void>();
    _pendingWrite = completed.future;
    try {
      if (previous != null) await previous;
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(preferenceKey, code))
        throw StateError('Unable to save language');
      value = code == 'en' ? const Locale('en') : const Locale('zh', 'CN');
      await _syncNativeMenus();
    } finally {
      if (identical(_pendingWrite, completed.future)) _pendingWrite = null;
      completed.complete();
    }
  }

  Future<void> _syncNativeMenus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    final strings = WayttyStrings(value);
    try {
      await _nativeMenus.invokeMethod<void>('setLanguage', {
        'titles': {
          for (final source in _menuSources) source: strings.resolve(source),
        },
      });
    } on MissingPluginException {
      // The shared package is also used by plugin previews and widget tests.
    } on PlatformException {
      debugPrint('waytty: native menu translation unavailable');
    }
  }
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: WayttyLanguage.instance,
    builder: (context, locale, _) => Row(
      children: [
        const Icon(Icons.language, size: 18),
        const SizedBox(width: 10),
        const Expanded(child: LText('Interface language')),
        DropdownButton<String>(
          value: locale.languageCode,
          items: const [
            DropdownMenuItem(value: 'zh', child: Text('简体中文')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (code) async {
            if (code == null) return;
            try {
              await WayttyLanguage.instance.select(code);
            } catch (e) {
              if (context.mounted)
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$e')));
            }
          },
        ),
      ],
    ),
  );
}
