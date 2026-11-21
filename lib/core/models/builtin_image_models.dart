/// OpenAI 兼容接口常用的 GPT Image 模型候选。
const List<String> gptImageModelIds = <String>[
  'gpt-image-2',
  'gpt-image-2.5-flare',
  'gpt-image-2.5-sunburst',
];

/// 按模型 ID 推测是否为图像模型，供候选列表筛选使用。
///
/// 这不是能力校验；用户仍可手动输入服务商自定义的模型 ID。
bool isLikelyImageModel(String model) {
  final normalized = model.trim().toLowerCase();
  return const [
    'image',
    'dall-e',
    'dalle',
    'flux',
    'imagen',
    'seedream',
    'stable-diffusion',
    'stable_diffusion',
    'stable diffusion',
    'sdxl',
    'ideogram',
    'recraft',
    'kolors',
    'wanx',
    'hidream',
    'nano-banana',
    'nano_banana',
    'nano banana',
  ].any(normalized.contains);
}

/// xAI Grok Imagine 的内置图像模型候选。
///
/// xAI 的 `/v1/models` 不一定返回图像模型，内置候选项可以保证
/// 不联网也能在设置页的模型下拉里直接选中。
const List<String> xaiImagineModelIds = <String>[
  'grok-imagine-image-2.0',
  'grok-imagine-image-quality',
  'grok-imagine-image',
];
