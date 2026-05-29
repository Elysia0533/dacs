import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:online_story_reader/main.dart';
import 'package:online_story_reader/models/story.dart';
import 'package:online_story_reader/theme/reading_settings_provider.dart';
import 'package:online_story_reader/theme/theme_provider.dart';
import 'package:online_story_reader/theme/user_provider.dart';

void main() {
  testWidgets('app smoke test', (WidgetTester tester) async {
    final cachedServerStory = Story(
      id: 'cached-story',
      title: 'Cached Story',
      iconUrl: 'cached-cover',
    );

    SharedPreferences.setMockInitialValues({
      'local_imported_stories': <String>[],
      'server_stories': <String>[json.encode(cachedServerStory.toJson())],
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => ReadingSettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}
