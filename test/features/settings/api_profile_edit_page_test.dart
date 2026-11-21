import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/api/model_list_api.dart';
import 'package:mint_image/core/models/builtin_image_models.dart';
import 'package:mint_image/core/models/settings_model.dart';
import 'package:mint_image/core/providers/app_providers.dart';
import 'package:mint_image/core/providers/settings_provider.dart';
import 'package:mint_image/features/settings/api_profile_edit_page.dart';
import 'package:mint_image/features/settings/model_name_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renaming a legacy profile does not cache built-in models', (
    tester,
  ) async {
    final profile = _cachedProfile.copyWith(availableModels: []);
    final container = await _pumpEditor(tester, profile: profile);

    expect(_displayedModels(tester), gptImageModelIds);
    await tester.enterText(_field('名称'), '只修改名称');
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      profile.copyWith(name: '只修改名称'),
    );
  });

  testWidgets('renaming a profile preserves its existing remote model cache', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);

    expect(_displayedModels(tester), _cachedProfile.availableModels);
    await tester.enterText(_field('名称'), '保留模型缓存');
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      _cachedProfile.copyWith(name: '保留模型缓存'),
    );
  });

  testWidgets('changing Base URL does not inherit the previous model cache', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);
    await tester.enterText(_field('Base URL'), 'https://new.example.com');
    await tester.pump();

    expect(_displayedModels(tester), gptImageModelIds);
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      _cachedProfile.copyWith(
        baseUrl: 'https://new.example.com',
        availableModels: [],
      ),
    );
  });

  testWidgets('changing API Key does not inherit the previous model cache', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);
    await tester.enterText(_field('API Key'), 'different-test-key');
    await tester.pump();

    expect(_displayedModels(tester), gptImageModelIds);
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      _cachedProfile.copyWith(
        apiKey: 'different-test-key',
        availableModels: [],
      ),
    );
  });

  testWidgets('changing API mode does not inherit the previous model cache', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);
    await _selectMode(tester, ImageGenerationApiMode.responses);

    expect(_displayedModels(tester), isEmpty);
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      _cachedProfile.copyWith(
        model: ImageGenerationApiMode.responses.defaultModel,
        apiMode: ImageGenerationApiMode.responses,
        availableModels: [],
      ),
    );
  });

  testWidgets('switching API modes away and back preserves the remote cache', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);
    await _selectMode(tester, ImageGenerationApiMode.responses);
    expect(_displayedModels(tester), isEmpty);

    await _selectMode(tester, ImageGenerationApiMode.images);
    expect(_displayedModels(tester), _cachedProfile.availableModels);
    await _saveEditor(tester);

    await _expectSavedProfile(container, _cachedProfile);
  });

  testWidgets('restoring connection fields restores the original cached list', (
    tester,
  ) async {
    final container = await _pumpEditor(tester);
    await tester.enterText(_field('Base URL'), 'https://temporary.example.com');
    await tester.enterText(_field('API Key'), 'temporary-key');
    await tester.pump();
    expect(_displayedModels(tester), gptImageModelIds);

    await tester.enterText(_field('Base URL'), _cachedProfile.baseUrl);
    await tester.enterText(_field('API Key'), _cachedProfile.apiKey);
    await tester.pump();
    expect(_displayedModels(tester), _cachedProfile.availableModels);
    await _saveEditor(tester);

    await _expectSavedProfile(container, _cachedProfile);
  });

  testWidgets('successfully fetched models are saved as connection cache', (
    tester,
  ) async {
    final profile = _cachedProfile.copyWith(availableModels: []);
    final api = _StubModelListApi();
    final container = await _pumpEditor(
      tester,
      profile: profile,
      modelListApi: api,
    );
    await tester.ensureVisible(find.byTooltip('获取模型列表'));
    await tester.pump();
    await tester.tap(find.byTooltip('获取模型列表'));
    await tester.pumpAndSettle();

    expect(api.requestedProfile?.baseUrl, profile.baseUrl);
    expect(_displayedModels(tester), _remoteModels);
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      profile.copyWith(availableModels: _remoteModels),
    );
  });

  testWidgets('a response for an edited connection is not cached', (
    tester,
  ) async {
    final response = Completer<List<String>>();
    final api = _StubModelListApi(response: response.future);
    final profile = _cachedProfile.copyWith(availableModels: []);
    final container = await _pumpEditor(
      tester,
      profile: profile,
      modelListApi: api,
    );
    await tester.ensureVisible(find.byTooltip('获取模型列表'));
    await tester.pump();
    await tester.tap(find.byTooltip('获取模型列表'));
    await tester.pump();
    expect(api.requestedProfile, isNotNull);

    await tester.ensureVisible(_field('Base URL'));
    await tester.pump();
    await tester.enterText(_field('Base URL'), 'https://changed.example.com');
    response.complete(_remoteModels);
    await tester.pumpAndSettle();
    expect(_displayedModels(tester), gptImageModelIds);
    await _saveEditor(tester);

    await _expectSavedProfile(
      container,
      profile.copyWith(
        baseUrl: 'https://changed.example.com',
        availableModels: [],
      ),
    );
  });
}

const _cachedProfile = ApiProfile(
  id: 'edited-api',
  name: '原配置',
  baseUrl: 'https://images.example.com',
  apiKey: 'original-test-key',
  model: 'gpt-image-2',
  availableModels: ['provider-image-a', 'provider-image-b'],
  useStreaming: true,
);

const _otherProfile = ApiProfile(
  id: 'active-api',
  name: '当前激活的其他配置',
  baseUrl: 'https://other.example.com',
  apiKey: 'other-test-key',
  model: 'grok-imagine-image-2.0',
);

const _remoteModels = ['remote-image-one', 'remote-image-two'];

Finder _field(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

List<String> _displayedModels(WidgetTester tester) {
  return tester.widget<ModelNameField>(find.byType(ModelNameField)).modelOptions;
}

Future<ProviderContainer> _pumpEditor(
  WidgetTester tester, {
  ApiProfile profile = _cachedProfile,
  ModelListApi? modelListApi,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();
  final settings = SettingsModel(
    profiles: [profile, _otherProfile],
    activeProfileId: _otherProfile.id,
    requestTimeoutSeconds: 900,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialSettingsModelProvider.overrideWithValue(settings),
        modelListApiProvider.overrideWithValue(
          modelListApi ?? _StubModelListApi(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ApiProfileEditPage(profile: profile),
                    ),
                  );
                },
                child: const Text('编辑连接'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('编辑连接'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ApiProfileEditPage)),
  );
}

Future<void> _selectMode(
  WidgetTester tester,
  ImageGenerationApiMode mode,
) async {
  final dropdown = find.byType(
    DropdownButtonFormField<ImageGenerationApiMode>,
  );
  await tester.ensureVisible(dropdown);
  await tester.pump();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode.label).last);
  await tester.pumpAndSettle();
}

Future<void> _saveEditor(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final save = find.widgetWithText(ElevatedButton, '保存');
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
  await tester.pumpAndSettle();
  expect(find.byType(ApiProfileEditPage), findsNothing);
}

Future<void> _expectSavedProfile(
  ProviderContainer container,
  ApiProfile expectedProfile,
) async {
  final current = container.read(settingsProvider);
  final preferences = await SharedPreferences.getInstance();
  final reloaded = SettingsController.loadFromPreferences(preferences);
  final expected = SettingsModel(
    profiles: [expectedProfile, _otherProfile],
    activeProfileId: _otherProfile.id,
    requestTimeoutSeconds: 900,
  );
  expect(current.toJson(), expected.toJson());
  expect(reloaded.toJson(), expected.toJson());
}

class _StubModelListApi extends ModelListApi {
  _StubModelListApi({this.response});

  final Future<List<String>>? response;
  ApiProfile? requestedProfile;

  @override
  Future<List<String>> fetchImageGenerationModels({
    required ApiProfile profile,
    required int timeoutSeconds,
    CancelToken? cancelToken,
  }) {
    requestedProfile = profile;
    return response ?? Future.value(_remoteModels);
  }
}
