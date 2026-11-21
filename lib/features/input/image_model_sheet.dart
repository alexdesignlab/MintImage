import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/openai_client.dart';
import '../../core/models/builtin_image_models.dart';
import '../../core/models/settings_model.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/settings_provider.dart';
import '../../shared/theme.dart';

/// Selects a model while keeping the current API connection and credentials.
class ImageModelSheet extends ConsumerStatefulWidget {
  const ImageModelSheet({super.key, required this.profile});

  final ApiProfile profile;

  @override
  ConsumerState<ImageModelSheet> createState() => _ImageModelSheetState();
}

class _ImageModelSheetState extends ConsumerState<ImageModelSheet> {
  final _searchController = TextEditingController();
  late List<String> _models;
  bool _loading = false;
  bool _showAll = false;
  String? _error;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _showAll = profile.apiMode == ImageGenerationApiMode.responses;
    final sameConnection = ref.read(settingsProvider).profiles.where(
      (other) =>
          other.normalizedBaseUrl == profile.normalizedBaseUrl &&
          other.apiKey == profile.apiKey &&
          other.apiMode == profile.apiMode,
    );
    _models = _normalizeModels([
      profile.model,
      ...profile.availableModels,
      for (final other in sameConnection) ...[
        other.model,
        ...other.availableModels,
      ],
      if (profile.availableModels.isEmpty) ...[
        if (profile.apiMode.isXaiImagine)
          ...xaiImagineModelIds
        else if (profile.apiMode == ImageGenerationApiMode.images)
          ...gptImageModelIds,
      ],
    ]);
    if (profile.availableModels.isEmpty && profile.apiKey.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_fetchModels());
        }
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('model picker closed');
    _searchController.dispose();
    super.dispose();
  }

  List<String> _normalizeModels(Iterable<String> models) {
    return models.map((model) => model.trim()).where((model) => model.isNotEmpty)
        .toSet().toList();
  }

  Future<void> _fetchModels() async {
    if (_loading) {
      return;
    }
    final profile = widget.profile;
    if (profile.apiKey.trim().isEmpty) {
      setState(() => _error = '请先在 API 配置中填写密钥，也可以直接选择或输入模型名。');
      return;
    }
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await ref.read(modelListApiProvider)
          .fetchImageGenerationModels(
        profile: profile,
        timeoutSeconds: ref.read(settingsProvider).requestTimeoutSeconds,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) {
        return;
      }
      final current = ref.read(settingsProvider).profileById(profile.id);
      if (current == null ||
          current.normalizedBaseUrl != profile.normalizedBaseUrl ||
          current.apiKey != profile.apiKey ||
          current.apiMode != profile.apiMode) {
        return;
      }
      await ref.read(settingsProvider.notifier)
          .setAvailableModels(profile.id, models);
      if (!mounted || cancelToken.isCancelled) {
        return;
      }
      setState(() {
        _models = _normalizeModels([current.model, ...models]);
      });
    } catch (error) {
      if (mounted && !cancelToken.isCancelled) {
        setState(() {
          final message = error is ApiException ? error.message : error.toString();
          _error = '获取模型失败：$message。仍可选择已有模型或直接输入模型名。';
        });
      }
    } finally {
      if (mounted && identical(_cancelToken, cancelToken)) {
        setState(() {
          _loading = false;
          _cancelToken = null;
        });
      }
    }
  }

  void _select(String model) {
    final trimmed = model.trim();
    if (trimmed.isNotEmpty) {
      Navigator.of(context).pop(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final lowerQuery = query.toLowerCase();
    final visibleModels = _models.where((model) {
      if (query.isNotEmpty) {
        return model.toLowerCase().contains(lowerQuery);
      }
      return _showAll ||
          model == widget.profile.model ||
          isLikelyImageModel(model);
    }).toList();
    final canUseCustom = query.isNotEmpty && !_models.contains(query);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('选择生图模型',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('当前 API：${widget.profile.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppThemeTokens.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新模型列表',
                      onPressed: _loading ? null : _fetchModels,
                      icon: _loading
                          ? const SizedBox.square(
                              key: Key('image-model-loading'),
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const Key('image-model-search'),
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: '搜索或输入模型名',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _select,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('显示全部模型'),
                      selected: _showAll,
                      onSelected: (value) => setState(() => _showAll = value),
                    ),
                    Text('选择后自动记住，下次直接使用',
                      style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(_error!,
                    key: const Key('image-model-error'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppThemeTokens.warningText)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (canUseCustom)
                      ListTile(
                        key: const Key('use-custom-image-model'),
                        leading: const Icon(Icons.add_circle_outline_rounded),
                        title: Text('使用模型：$query'),
                        subtitle: const Text('复用当前 API 配置'),
                        onTap: () => _select(query),
                      ),
                    if (visibleModels.isEmpty && !canUseCustom)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('没有匹配的图片模型，可显示全部模型或输入完整模型名。'),
                      ),
                    for (final model in visibleModels)
                      ListTile(
                        key: ValueKey('image-model-option-$model'),
                        leading: Icon(
                          model == widget.profile.model
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: model == widget.profile.model
                              ? AppThemeTokens.primary
                              : AppThemeTokens.textSecondary,
                        ),
                        title: Text(model, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                        onTap: () => _select(model),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
