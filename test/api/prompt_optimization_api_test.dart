import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/api/prompt_optimization_api.dart';
import 'package:mint_image/core/models/settings_model.dart';

void main() {
  group('PromptOptimizationApi', () {
    test(
      'uses OpenAI Chat Completions format and parses message text',
      () async {
        final server = await _startServer((request) async {
          expect(request.method, 'POST');
          expect(request.uri.path, '/v1/chat/completions');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer test-key',
          );
          final body = await _readJson(request);
          expect(body['model'], 'gpt-test');
          expect(body['messages'], isA<List>());

          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'optimized chat prompt'},
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final result = await const PromptOptimizationApi().optimize(
          prompt: 'cat',
          direction: PromptOptimizationDirection.strengthen,
          profile: _profileFor(
            server,
            protocol: PromptOptimizationProtocol.openAiChatCompletions,
          ),
          timeoutSeconds: 30,
        );

        expect(result, 'optimized chat prompt');
      },
    );

    test('uses OpenAI Responses format and parses output_text', () async {
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/responses');
        final body = await _readJson(request);
        expect(body['model'], 'gpt-test');
        expect(body['input'], isA<List>());
        expect(body['stream'], isTrue);

        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'response prompt'})}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await const PromptOptimizationApi().optimize(
        prompt: 'cat',
        direction: PromptOptimizationDirection.poetic,
        profile: _profileFor(
          server,
          protocol: PromptOptimizationProtocol.openAiResponses,
        ),
        timeoutSeconds: 30,
      );

      expect(result, 'response prompt');
    });

    test('uses Claude Messages format and parses content text', () async {
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/messages');
        expect(request.headers.value('x-api-key'), 'test-key');
        final body = await _readJson(request);
        expect(body['model'], 'gpt-test');
        expect(body['stream'], isTrue);
        expect(body['messages'], isA<List>());
        final messages = body['messages'] as List;
        final firstMessage = messages.first as Map<String, dynamic>;
        expect(firstMessage['content'], isA<List>());

        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'claude prompt'},
          })}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await const PromptOptimizationApi().optimize(
        prompt: 'cat',
        direction: PromptOptimizationDirection.edgeExplore,
        profile: _profileFor(
          server,
          protocol: PromptOptimizationProtocol.claudeMessages,
        ),
        timeoutSeconds: 30,
      );

      expect(result, 'claude prompt');
    });

    test(
      'uses Gemini generateContent format and parses candidate text',
      () async {
        final server = await _startServer((request) async {
          expect(request.uri.path, '/v1beta/models/gpt-test:generateContent');
          expect(request.headers.value('x-goog-api-key'), 'test-key');
          final body = await _readJson(request);
          expect(body['contents'], isA<List>());

          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'gemini prompt'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final result = await const PromptOptimizationApi().optimize(
          prompt: 'cat',
          direction: PromptOptimizationDirection.strengthenToEnglish,
          profile: _profileFor(
            server,
            protocol: PromptOptimizationProtocol.geminiGenerateContent,
          ),
          timeoutSeconds: 30,
        );

        expect(result, 'gemini prompt');
      },
    );

    test('skips reasoning deltas and keeps only the answer text', () async {
      final server = await _startServer((request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        // Responses 协议会把思考过程也按 delta 推送，其中的文本常常复述
        // 任务说明与原始提示词；这些内容不能进入优化结果。
        request.response.write(
          'data: ${jsonEncode({'type': 'response.reasoning_summary_text.delta', 'delta': '优化方向：强化 原始提示词：cat'})}\n\n'
          'data: ${jsonEncode({'type': 'response.reasoning_text.delta', 'delta': '我需要先分析这个提示词'})}\n\n'
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': '一只白猫'})}\n\n'
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': '，柔和逆光'})}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await const PromptOptimizationApi().optimize(
        prompt: 'cat',
        direction: PromptOptimizationDirection.strengthen,
        profile: _profileFor(
          server,
          protocol: PromptOptimizationProtocol.openAiResponses,
        ),
        timeoutSeconds: 30,
      );

      expect(result, '一只白猫，柔和逆光');
    });

    test('skips claude thinking deltas', () async {
      final server = await _startServer((request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({'type': 'content_block_delta', 'delta': {'type': 'thinking_delta', 'thinking': '先分析提示词', 'text': '思考过程不应进入结果'}})}\n\n'
          'data: ${jsonEncode({'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': 'claude prompt'}})}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await const PromptOptimizationApi().optimize(
        prompt: 'cat',
        direction: PromptOptimizationDirection.strengthen,
        profile: _profileFor(
          server,
          protocol: PromptOptimizationProtocol.claudeMessages,
        ),
        timeoutSeconds: 30,
      );

      expect(result, 'claude prompt');
    });

    test('parses a plain JSON response when the relay ignores stream', () async {
      final server = await _startServer((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'output': [
              {
                'type': 'reasoning',
                'content': [
                  {'type': 'reasoning_text', 'text': '思考过程不应进入结果'},
                ],
              },
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'json prompt'},
                ],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await const PromptOptimizationApi().optimize(
        prompt: 'cat',
        direction: PromptOptimizationDirection.strengthen,
        profile: _profileFor(
          server,
          protocol: PromptOptimizationProtocol.openAiResponses,
        ),
        timeoutSeconds: 30,
      );

      expect(result, 'json prompt');
    });
  });
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      await handler(request);
    }),
  );
  return server;
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  return jsonDecode(await utf8.decoder.bind(request).join())
      as Map<String, dynamic>;
}

PromptOptimizationProfile _profileFor(
  HttpServer server, {
  required PromptOptimizationProtocol protocol,
}) {
  return PromptOptimizationProfile(
    id: 'optimizer',
    name: 'Optimizer',
    baseUrl: 'http://${server.address.host}:${server.port}',
    apiKey: 'test-key',
    model: 'gpt-test',
    protocol: protocol,
  );
}
