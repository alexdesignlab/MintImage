import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/settings_model.dart';
import 'package:mint_image/core/providers/app_providers.dart';
import 'package:mint_image/core/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const primaryProfile = ApiProfile(
    id: 'primary-api',
    name: '现有接口',
    baseUrl: 'https://images.example.com/custom/',
    apiKey: 'primary-test-key',
    model: 'gpt-image-2',
    availableModels: ['gpt-image-2', 'gpt-image-2.5-flare'],
    apiMode: ImageGenerationApiMode.responses,
    useStreaming: true,
  );
  const otherProfile = ApiProfile(
    id: 'other-api',
    name: '其他接口',
    baseUrl: 'https://other.example.com',
    apiKey: 'other-test-key',
    model: 'grok-imagine-image-2.0',
    availableModels: ['grok-imagine-image-2.0'],
    apiMode: ImageGenerationApiMode.xaiImagine,
  );
  const initialSettings = SettingsModel(
    profiles: [primaryProfile, otherProfile],
    activeProfileId: 'primary-api',
    promptOptimizationProfiles: [
      PromptOptimizationProfile(
        id: 'optimizer',
        name: '优化配置',
        baseUrl: 'https://optimizer.example.com',
        apiKey: 'optimizer-test-key',
        model: 'text-model',
        protocol: PromptOptimizationProtocol.openAiResponses,
      ),
    ],
    activePromptOptimizationProfileId: 'optimizer',
    responseFormat: 'url',
    requestTimeoutSeconds: 900,
    lastSizePreset: SizePreset.wide2k,
    lastCustomWidth: 2560,
    lastCustomHeight: 1440,
    lastQuality: ImageQuality.high,
    lastOutputFormat: ImageOutputFormat.webp,
    previewInfoCollapsed: true,
    webDavBackupConfig: WebDavBackupConfig(
      baseUrl: 'https://backup.example.com/dav',
      username: 'backup-user',
      password: 'backup-password',
      remoteDirectory: 'MintImage/backups',
    ),
  );

  late SharedPreferences preferences;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'settings_model_v1': initialSettings.encode(),
    });
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialSettingsModelProvider.overrideWithValue(initialSettings),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  void expectStateAndPersistence(SettingsModel expected) {
    final current = container.read(settingsProvider);
    final reloaded = SettingsController.loadFromPreferences(preferences);
    expect(current.toJson(), expected.toJson());
    expect(reloaded.toJson(), expected.toJson());
  }

  test('switching image models updates the same profile and persists', () async {
    await container
        .read(settingsProvider.notifier)
        .setImageModel(primaryProfile.id, '  gpt-image-2.5-sunburst\n');

    final expected = initialSettings.copyWith(
      profiles: [
        primaryProfile.copyWith(
          model: 'gpt-image-2.5-sunburst',
          availableModels: [
            'gpt-image-2',
            'gpt-image-2.5-flare',
            'gpt-image-2.5-sunburst',
          ],
        ),
        otherProfile,
      ],
    );
    expectStateAndPersistence(expected);
    expect(container.read(settingsProvider).profiles, hasLength(2));
    expect(container.read(settingsProvider).activeProfileId, primaryProfile.id);
  });

  test('switching an inactive profile does not activate it', () async {
    await container
        .read(settingsProvider.notifier)
        .setImageModel(otherProfile.id, ' grok-imagine-image-quality ');

    expectStateAndPersistence(
      initialSettings.copyWith(
        profiles: [
          primaryProfile,
          otherProfile.copyWith(
            model: 'grok-imagine-image-quality',
            availableModels: [
              'grok-imagine-image-2.0',
              'grok-imagine-image-quality',
            ],
          ),
        ],
      ),
    );
    expect(container.read(settingsProvider).activeProfileId, primaryProfile.id);
  });

  test('switching back to a known model does not duplicate candidates', () async {
    final controller = container.read(settingsProvider.notifier);
    await controller.setImageModel(primaryProfile.id, 'gpt-image-2.5-flare');
    await controller.setImageModel(primaryProfile.id, ' gpt-image-2 ');
    await controller.setImageModel(primaryProfile.id, 'gpt-image-2');

    expectStateAndPersistence(initialSettings);
    expect(container.read(settingsProvider).profiles, hasLength(2));
  });

  test('empty models and unknown profile IDs are ignored', () async {
    final controller = container.read(settingsProvider.notifier);
    await controller.setImageModel(primaryProfile.id, ' \n\t');
    await controller.setImageModel('missing-api', 'gpt-image-2.5-sunburst');

    expect(container.read(settingsProvider), same(initialSettings));
    expectStateAndPersistence(initialSettings);
  });

  test('candidate updates normalize only the selected profile list', () async {
    final candidates = [
      ' custom-image-model ',
      '',
      'custom-image-model',
      ' \n',
      ' gpt-image-2.5-flare\t',
      'gpt-image-2.5-flare',
    ];
    await container
        .read(settingsProvider.notifier)
        .setAvailableModels(primaryProfile.id, candidates);
    candidates.add('added-after-saving');

    expectStateAndPersistence(
      initialSettings.copyWith(
        profiles: [
          primaryProfile.copyWith(
            availableModels: ['custom-image-model', 'gpt-image-2.5-flare'],
          ),
          otherProfile,
        ],
      ),
    );
    expect(container.read(settingsProvider).activeProfile.model, 'gpt-image-2');
  });

  test('candidate lists can be cleared without changing the model', () async {
    await container
        .read(settingsProvider.notifier)
        .setAvailableModels(primaryProfile.id, []);

    expectStateAndPersistence(
      initialSettings.copyWith(
        profiles: [
          primaryProfile.copyWith(availableModels: []),
          otherProfile,
        ],
      ),
    );
  });

  test('updating candidates does not activate an inactive profile', () async {
    await container
        .read(settingsProvider.notifier)
        .setAvailableModels(otherProfile.id, [' grok-imagine-image ']);

    expectStateAndPersistence(
      initialSettings.copyWith(
        profiles: [
          primaryProfile,
          otherProfile.copyWith(availableModels: ['grok-imagine-image']),
        ],
      ),
    );
  });

  test('candidate updates for unknown profile IDs are ignored', () async {
    await container
        .read(settingsProvider.notifier)
        .setAvailableModels('missing-api', ['gpt-image-2.5-sunburst']);

    expect(container.read(settingsProvider), same(initialSettings));
    expectStateAndPersistence(initialSettings);
  });

  test('legacy saved profiles keep credentials and gain model candidates', () async {
    final legacyJson = initialSettings.toJson();
    for (final profile in legacyJson['profiles'] as List) {
      (profile as Map<String, dynamic>).remove('availableModels');
    }
    final legacySettings = SettingsModel.fromJson(legacyJson);
    final legacyController = SettingsController(preferences, legacySettings);
    addTearDown(legacyController.dispose);

    await legacyController.setImageModel(primaryProfile.id, 'gpt-image-2.5-flare');

    final reloaded = SettingsController.loadFromPreferences(preferences);
    expect(
      reloaded.toJson(),
      legacySettings.copyWith(
        profiles: [
          legacySettings.profiles.first.copyWith(
            model: 'gpt-image-2.5-flare',
            availableModels: ['gpt-image-2.5-flare'],
          ),
          legacySettings.profiles.last,
        ],
      ).toJson(),
    );
    expect(reloaded.profiles, hasLength(2));
    expect(reloaded.activeProfileId, primaryProfile.id);
  });
}
