import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/models/builtin_image_models.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/settings_model.dart';

void main() {
  test('initial settings use a 600 second timeout', () {
    final settings = SettingsModel.initial();

    expect(
      settings.requestTimeoutSeconds,
      SettingsModel.defaultRequestTimeoutSeconds,
    );
    expect(settings.responseFormat, isNull);
    expect(settings.lastSizePreset, SizePreset.auto);
    expect(settings.lastCustomWidth, 0);
    expect(settings.lastCustomHeight, 0);
    expect(settings.lastQuality, ImageQuality.auto);
    expect(settings.lastOutputFormat, ImageOutputFormat.png);
  });

  test('settings round-trip preserves request timeout', () {
    final optimizer = PromptOptimizationProfile(
      id: 'optimizer-1',
      name: '优化',
      baseUrl: 'https://right.codes/codex/v1',
      apiKey: 'key',
      model: 'gpt-5.5',
      protocol: PromptOptimizationProtocol.openAiResponses,
    );
    final settings = SettingsModel.initial().copyWith(
      requestTimeoutSeconds: 900,
      promptOptimizationProfiles: [optimizer],
      activePromptOptimizationProfileId: optimizer.id,
      lastSizePreset: SizePreset.wide2k,
      lastCustomWidth: 2560,
      lastCustomHeight: 1440,
      lastQuality: ImageQuality.high,
      lastOutputFormat: ImageOutputFormat.webp,
    );

    final decoded = SettingsModel.decode(settings.encode());

    expect(decoded.requestTimeoutSeconds, 900);
    expect(decoded.promptOptimizationProfiles, hasLength(1));
    expect(decoded.activePromptOptimizationProfile?.id, 'optimizer-1');
    expect(
      decoded.activePromptOptimizationProfile?.protocol,
      PromptOptimizationProtocol.openAiResponses,
    );
    expect(decoded.lastSizePreset, SizePreset.wide2k);
    expect(decoded.lastCustomWidth, 2560);
    expect(decoded.lastCustomHeight, 1440);
    expect(decoded.lastQuality, ImageQuality.high);
    expect(decoded.lastOutputFormat, ImageOutputFormat.webp);
  });

  test('settings round-trip preserves WebDAV backup config', () {
    final settings = SettingsModel.initial().copyWith(
      webDavBackupConfig: const WebDavBackupConfig(
        baseUrl: 'https://example.com/dav',
        username: 'user',
        password: 'pass',
        remoteDirectory: 'MintImage/backups',
      ),
    );

    final decoded = SettingsModel.decode(settings.encode());

    expect(decoded.webDavBackupConfig?.baseUrl, 'https://example.com/dav');
    expect(decoded.webDavBackupConfig?.username, 'user');
    expect(decoded.webDavBackupConfig?.password, 'pass');
    expect(decoded.webDavBackupConfig?.remoteDirectory, 'MintImage/backups');
  });

  test('legacy settings default to no prompt optimization profiles', () {
    final decoded = SettingsModel.fromJson({
      'profiles': [
        {
          'id': '1',
          'name': '默认',
          'baseUrl': 'https://api.openai.com',
          'apiKey': 'key',
          'model': 'gpt-image-2',
        },
      ],
      'activeProfileId': '1',
      'requestTimeoutSeconds': 600,
    });

    expect(decoded.promptOptimizationProfiles, isEmpty);
    expect(decoded.activePromptOptimizationProfile, isNull);
    expect(decoded.activeProfile.apiMode, ImageGenerationApiMode.images);
    expect(decoded.activeProfile.availableModels, isEmpty);
    expect(decoded.lastSizePreset, SizePreset.auto);
    expect(decoded.lastQuality, ImageQuality.auto);
    expect(decoded.lastOutputFormat, ImageOutputFormat.png);
  });

  test('image API mode is persisted per profile', () {
    final settings = SettingsModel.initial();
    final profile = settings.activeProfile.copyWith(
      model: 'gpt-5.5',
      apiMode: ImageGenerationApiMode.responses,
    );
    final updated = settings.copyWith(profiles: [profile]);

    final decoded = SettingsModel.decode(updated.encode());

    expect(decoded.activeProfile.apiMode, ImageGenerationApiMode.responses);
    expect(decoded.activeProfile.generationEndpoint, contains('/v1/responses'));
  });

  group('image model candidates', () {
    const profile = ApiProfile(
      id: 'image-api',
      name: '图像接口',
      baseUrl: 'https://example.com',
      apiKey: 'test-key',
      model: 'gpt-image-2',
      apiMode: ImageGenerationApiMode.responses,
      useStreaming: true,
    );

    test('new profiles default to an empty candidate list', () {
      expect(profile.availableModels, isEmpty);
      expect(ApiProfile.initial().availableModels, isEmpty);
    });

    test('fromJson trims, deduplicates and ignores invalid candidates', () {
      final decoded = ApiProfile.fromJson({
        ...profile.toJson(),
        'availableModels': [
          ' gpt-image-2 ',
          null,
          123,
          true,
          {'id': 'ignored'},
          ['ignored'],
          '',
          '   ',
          'gpt-image-2',
          ' gpt-image-2.5-sunburst\n',
          'gpt-image-2.5-sunburst',
          'provider/custom-model',
        ],
      });

      expect(decoded.availableModels, [
        'gpt-image-2',
        'gpt-image-2.5-sunburst',
        'provider/custom-model',
      ]);
      expect(decoded.model, profile.model);
      expect(decoded.baseUrl, profile.baseUrl);
      expect(decoded.apiKey, profile.apiKey);
      expect(decoded.apiMode, profile.apiMode);
      expect(decoded.useStreaming, profile.useStreaming);
    });

    test('missing or malformed candidate lists remain backwards compatible', () {
      final legacyJson = profile.toJson()..remove('availableModels');
      expect(ApiProfile.fromJson(legacyJson).availableModels, isEmpty);

      for (final invalid in <Object?>[null, 'gpt-image-2', 12, {}]) {
        final decoded = ApiProfile.fromJson({
          ...legacyJson,
          'availableModels': invalid,
        });
        expect(decoded.availableModels, isEmpty);
        expect(decoded.model, profile.model);
      }
    });

    test('copyWith preserves, replaces and clears the candidate list', () {
      final populated = profile.copyWith(
        availableModels: ['gpt-image-2', 'gpt-image-2.5-flare'],
      );

      expect(populated.copyWith(name: '改名').availableModels, [
        'gpt-image-2',
        'gpt-image-2.5-flare',
      ]);
      expect(
        populated.copyWith(availableModels: ['custom-model']).toJson(),
        {...profile.toJson(), 'availableModels': ['custom-model']},
      );
      expect(populated.copyWith(availableModels: []).availableModels, isEmpty);
      expect(profile.availableModels, isEmpty);
    });

    test('settings round-trip preserves candidates for each profile', () {
      final first = profile.copyWith(
        availableModels: ['gpt-image-2', 'gpt-image-2.5-flare'],
      );
      final second = profile.copyWith(
        id: 'other-api',
        model: 'grok-imagine-image-2.0',
        availableModels: ['grok-imagine-image-2.0'],
      );
      final settings = SettingsModel(
        profiles: [first, second],
        activeProfileId: first.id,
      );

      final decoded = SettingsModel.decode(settings.encode());

      expect(decoded.toJson(), settings.toJson());
      expect(decoded.profiles, hasLength(2));
      expect(decoded.activeProfile.availableModels, first.availableModels);
      expect(
        decoded.profileById(second.id)?.availableModels,
        second.availableModels,
      );
    });
  });

  group('built-in image models', () {
    test('keeps the GPT Image and xAI candidates available offline', () {
      expect(gptImageModelIds, [
        'gpt-image-2',
        'gpt-image-2.5-flare',
        'gpt-image-2.5-sunburst',
      ]);
      expect(xaiImagineModelIds, [
        'grok-imagine-image-2.0',
        'grok-imagine-image-quality',
        'grok-imagine-image',
      ]);
    });

    test('recognizes image model families ignoring case and padding', () {
      for (final model in [
        ...gptImageModelIds,
        ...xaiImagineModelIds,
        ' GEMINI-2.5-FLASH-IMAGE ',
        'dall-e-3',
        'dalle-3',
        'black-forest-labs/FLUX.1-schnell',
        'imagen-4',
        'doubao-seedream-4-0',
        'stable-diffusion-3.5-large',
        'stable_diffusion',
        'sdxl-turbo',
        'ideogram-v3',
        'recraft-v3',
        'kolors',
        'wanx-v1',
        'hidream-i1-full',
        'nano-banana-pro',
      ]) {
        expect(isLikelyImageModel(model), isTrue, reason: model);
      }
    });

    test('does not classify empty or general text model IDs as images', () {
      for (final model in [
        '',
        '   ',
        'gpt-5.5',
        'claude-sonnet-4-6',
        'deepseek-v4.1-flash',
        'gemini-2.5-flash',
        'text-embedding-3-large',
      ]) {
        expect(isLikelyImageModel(model), isFalse, reason: model);
      }
    });
  });

  test('legacy b64_json responseFormat is normalized to null', () {
    final decoded = SettingsModel.fromJson({
      'profiles': [
        {
          'id': '1',
          'name': '默认',
          'baseUrl': 'https://api.openai.com',
          'apiKey': 'key',
          'model': 'gpt-image-2',
        },
      ],
      'activeProfileId': '1',
      'responseFormat': 'b64_json',
      'requestTimeoutSeconds': 600,
    });

    expect(decoded.responseFormat, isNull);
  });
}
