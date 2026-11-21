import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/models/settings_model.dart';
import 'package:mint_image/core/providers/app_providers.dart';
import 'package:mint_image/core/providers/settings_provider.dart';
import 'package:mint_image/core/services/data_directory_service.dart';
import 'package:mint_image/features/settings/settings_page.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'mint_image_settings_delete_test_',
    );
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPathProvider(testDirectory);
    await DataDirectoryService.initialize();
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  testWidgets('saved APIs have visible delete buttons and cancellation keeps them', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final first = await _showDeleteButton(tester, 'delete-image-profile-primary');
    expect(tester.widget<TextButton>(first).onPressed, isNotNull);
    expect(find.descendant(of: first, matching: find.text('删除')), findsOneWidget);

    final second = await _showDeleteButton(tester, 'delete-image-profile-secondary');
    expect(tester.widget<TextButton>(second).onPressed, isNotNull);
    await tester.tap(second);
    await tester.pumpAndSettle();

    expect(find.text('删除 API 配置'), findsOneWidget);
    await _expectSavedSettings(container, _initialSettings);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    await _expectSavedSettings(container, _initialSettings);
  });

  testWidgets('confirming deletion of the active API selects and saves a fallback', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final button = await _showDeleteButton(tester, 'delete-image-profile-primary');
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('删除 API 配置'), findsOneWidget);
    await _expectSavedSettings(container, _initialSettings);
    await _confirmDelete(tester);

    await _expectSavedSettings(
      container,
      _initialSettings.copyWith(
        profiles: [_secondaryProfile],
        activeProfileId: _secondaryProfile.id,
      ),
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('deleting an inactive API keeps the active API and its saved settings', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final button = await _showDeleteButton(tester, 'delete-image-profile-secondary');
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    await _expectSavedSettings(
      container,
      _initialSettings.copyWith(profiles: [_primaryProfile]),
    );
  });

  testWidgets('the last image API shows a disabled delete button with a reason', (
    tester,
  ) async {
    final settings = _initialSettings.copyWith(profiles: [_primaryProfile]);
    final container = await _pumpSettings(tester, settings: settings);
    final button = await _showDeleteButton(tester, 'delete-image-profile-primary');

    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(find.ancestor(
      of: button,
      matching: find.byTooltip('至少保留一份生图 API，可编辑替换'),
    ), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    await _expectSavedSettings(container, settings);
  });

  testWidgets('the only prompt optimization API can be deleted and stays deleted', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final button = await _showDeleteButton(tester, 'delete-optimizer-profile-optimizer');
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('删除 API 配置'), findsOneWidget);
    await _confirmDelete(tester);

    await _expectSavedSettings(
      container,
      _initialSettings.copyWith(
        promptOptimizationProfiles: [],
        clearActivePromptOptimizationProfileId: true,
      ),
    );
    expect(container.read(settingsProvider).activePromptOptimizationProfile, isNull);
  });
}

const _primaryProfile = ApiProfile(
  id: 'primary',
  name: '常用生图接口',
  baseUrl: 'https://images.example.com',
  apiKey: 'primary-test-key',
  model: 'gpt-image-2',
  availableModels: ['gpt-image-2', 'gpt-image-2.5-sunburst'],
);

const _secondaryProfile = ApiProfile(
  id: 'secondary',
  name: '备用生图接口',
  baseUrl: 'https://other.example.com',
  apiKey: 'secondary-test-key',
  model: 'grok-imagine-image-2.0',
);

const _optimizerProfile = PromptOptimizationProfile(
  id: 'optimizer',
  name: '提示词优化接口',
  baseUrl: 'https://optimizer.example.com',
  apiKey: 'optimizer-test-key',
  model: 'text-model',
  protocol: PromptOptimizationProtocol.openAiResponses,
);

const _initialSettings = SettingsModel(
  profiles: [_primaryProfile, _secondaryProfile],
  activeProfileId: 'primary',
  promptOptimizationProfiles: [_optimizerProfile],
  activePromptOptimizationProfileId: 'optimizer',
  requestTimeoutSeconds: 900,
  previewInfoCollapsed: true,
);

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  SettingsModel settings = _initialSettings,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings_model_v1': settings.encode(),
  });
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialSettingsModelProvider.overrideWithValue(settings),
        // Configuration deletion must not need the image/history database.
        appDatabaseProvider.overrideWith(
          (ref) => throw StateError('Deleting an API must not open the database.'),
        ),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
}

Future<Finder> _showDeleteButton(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(button, findsOneWidget);
  expect(button.hitTestable(), findsOneWidget);
  return button;
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('确认删除'),
  ));
  await tester.pumpAndSettle();
}

Future<void> _expectSavedSettings(
  ProviderContainer container,
  SettingsModel expected,
) async {
  final preferences = await SharedPreferences.getInstance();
  final reloaded = SettingsController.loadFromPreferences(preferences);
  expect(container.read(settingsProvider).toJson(), expected.toJson());
  expect(reloaded.toJson(), expected.toJson());
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root.path, 'support');

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root.path, 'documents');

  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'temporary');
}
