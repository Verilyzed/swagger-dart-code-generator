import 'dart:io';

import 'package:swagger_dart_code_generator/src/code_generators/swagger_additions_generator.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:test/test.dart';

void main() {
  group('Additions generator tests', () {
    final generator = SwaggerAdditionsGenerator(
      GeneratorOptions(inputFolder: '', outputFolder: ''),
    );

    test('Should generate correct imports', () {
      final result = generator.generateImportsContent(
        'swagger.fileName',
        true,
        false,
        false,
        false,
      );

      expect(result, contains("part 'swagger.fileName.swagger.chopper.dart';"));
      expect(result, contains("part 'swagger.fileName.swagger.g.dart';"));
    });

    test('Should generate correct imports', () {
      final result = generator.generateImportsContent(
        'swagger.fileName',
        true,
        false,
        true,
        false,
      );

      expect(
        result,
        contains("import 'swagger.fileName.enums.swagger.dart' as enums;"),
      );
    });

    test('Should generate indexes file', () {
      final result = generator.generateIndexes(<String>[
        'someFile.dart',
        'secondFile',
      ]);

      expect(result, contains("export 'someFile.dart.dart' show SomeFile;"));
      expect(result, contains("export 'secondFile.dart' show SecondFile;"));
    });

    test('Generated JSON converter handles real Chopper responses', () async {
      final directory = await Directory.systemTemp.createTemp(
        'json_converter_',
      );
      try {
        final source = File('${directory.path}/converter_test.dart');
        await source.writeAsString('''
import 'dart:async';
import 'package:chopper/chopper.dart';
import 'package:chopper/chopper.dart' as chopper;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

${generator.generateConverterMappings(true)}
${generator.generateCustomJsonConverter('test')}
$_converterTests
''');
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=${Directory.current.path}/.dart_tool/package_config.json',
          source.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
  group('Test for generateDateToJson', () {
    final generator = SwaggerAdditionsGenerator(
      GeneratorOptions(inputFolder: '', outputFolder: ''),
    );
    test('Should dateToJson with parameter', () {
      const expectedResult = 'String? _dateToJson(DateTime? date)';
      final result = generator.generateDateToJson();

      expect(result, contains(expectedResult));
    });
  });
}

const _converterTests = r'''
class Model {
  Model.fromJson(Map<String, dynamic> json) : name = json['name'] as String;

  final String name;
}

chopper.Response<String> responseFor(String body, {
  int statusCode = 200,
  String? contentType = 'application/json',
}) {
  final base = http.Response(body, statusCode, headers: {
    if (contentType != null) 'content-type': contentType,
    'x-test': 'preserved',
  });
  return chopper.Response<String>(base, body, error: Object());
}

void main() {
  generatedMapping[Model] = Model.fromJson;
  final converter = $JsonSerializableConverter();

  for (final body in ['null', ' \nnull\t ', '', ' \r\n\t ']) {
    test('Nullable model body: ${body.codeUnits}', () async {
      final original = responseFor(body);
      final result = await converter.convertResponse<Model, Model>(original);

      expect(result.body, isNull);
      expect(result.base, same(original.base));
      expect(result.statusCode, 200);
      expect(result.headers, original.headers);
      expect(result.error, same(original.error));
    });
  }

  test('Null also works for non-nullable containers and special types', () async {
    final list = await converter.convertResponse<List<Model>, Model>(
      responseFor('null'),
    );
    final string = await converter.convertResponse<String, String>(
      responseFor('null'),
    );
    final date = await converter.convertResponse<DateTime, DateTime>(
      responseFor('null'),
    );
    final dynamicResult = await converter.convertResponse<dynamic, dynamic>(
      responseFor('null'),
    );

    expect(list.body, isNull);
    expect(string.body, isNull);
    expect(date.body, isNull);
    expect(dynamicResult.body, isNull);
  });

  test('Empty 204 response', () async {
    final original = responseFor('', statusCode: 204);
    final result = await converter.convertResponse<Model, Model>(original);

    expect(result.body, isNull);
    expect(result.base, same(original.base));
    expect(result.statusCode, 204);
    expect(result.error, same(original.error));
  });

  test('JSON object maps to a model and preserves response metadata', () async {
    final original = responseFor('{"name":"example"}');
    final result = await converter.convertResponse<Model, Model>(original);

    expect(result.body, isA<Model>());
    expect(result.body!.name, 'example');
    expect(result.base, same(original.base));
    expect(result.headers, original.headers);
    expect(result.error, same(original.error));
  });

  test('JSON list maps to models', () async {
    final result = await converter.convertResponse<List<Model>, Model>(
      responseFor('[{"name":"first"},{"name":"second"}]'),
    );

    expect(result.body, isA<List<Model>>());
    expect(result.body!.map((model) => model.name), ['first', 'second']);
  });

  test('Quoted null stays a string', () async {
    final result = await converter.convertResponse<String, String>(
      responseFor('"null"'),
    );

    expect(result.body, 'null');
  });

  for (final contentType in [
    'application/json; charset=utf-8',
    'Application/JSON; Charset=UTF-8',
    'application/problem+json',
    'application/vnd.api+json; charset=utf-8',
    'APPLICATION/VND.EXAMPLE+JSON; charset=utf-8',
  ]) {
    test('JSON media type is decoded: $contentType', () async {
      final nullResult = await converter.convertResponse<Model, Model>(
        responseFor(' \nnull\t ', contentType: contentType),
      );
      final string = await converter.convertResponse<String, String>(
        responseFor('"null"', contentType: contentType),
      );
      final object = await converter.convertResponse<Model, Model>(
        responseFor('{"name":"example"}', contentType: contentType),
      );

      expect(nullResult.body, isNull);
      expect(string.body, 'null');
      expect(object.body!.name, 'example');
    });
  }

  for (final contentType in <String?>[
    'text/plain',
    'text/plain; charset=utf-8',
    'application/octet-stream',
    'application/notjson',
    'text/plain; note="application/json"',
    null,
  ]) {
    test('Non-JSON media type preserves raw bodies: $contentType', () async {
      for (final body in [
        'null', ' \nnull\t ', '"null"', '"text\\nvalue"',
        ' \r\n\t ', '{"name":"example"}', '[1,true]', '42', 'true',
      ]) {
        final original = responseFor(body, contentType: contentType);
        final string = await converter.convertResponse<String, String>(original);
        final dynamicResult =
            await converter.convertResponse<dynamic, dynamic>(original);

        for (final result in [string, dynamicResult]) {
          expect(result.body, body);
          expect(result.base, same(original.base));
          expect(result.headers, original.headers);
          expect(result.error, same(original.error));
        }
      }
    });
  }

  test('Existing raw String responses are preserved', () async {
    for (final body in ['plain text', '42', 'true', '{"name":"example"}']) {
      final result = await converter.convertResponse<String, String>(
        responseFor(body),
      );

      expect(result.body, body);
    }
  });

  test('Primitive and dynamic JSON responses are preserved', () async {
    final integer = await converter.convertResponse<int, int>(responseFor('42'));
    final decimal = await converter.convertResponse<double, double>(
      responseFor('1.25'),
    );
    final boolean = await converter.convertResponse<bool, bool>(
      responseFor('true'),
    );
    final object = await converter.convertResponse<dynamic, dynamic>(
      responseFor('{"name":"example"}'),
    );
    final list = await converter.convertResponse<dynamic, dynamic>(
      responseFor('[1,true,"text"]'),
    );

    expect(integer.body, 42);
    expect(decimal.body, 1.25);
    expect(boolean.body, isTrue);
    expect(object.body, {'name': 'example'});
    expect(list.body, [1, true, 'text']);
  });

  test('DateTime responses are preserved', () async {
    final result = await converter.convertResponse<DateTime, DateTime>(
      responseFor('"2026-10-19T10:00:00Z"'),
    );

    expect(result.body, DateTime.utc(2026, 10, 19, 10));
  });

  test('Client accepts a successful JSON null response', () async {
    final client = chopper.ChopperClient(
      baseUrl: Uri.parse('https://example.test'),
      client: MockClient((request) async => http.Response('null', 200,
          headers: {'content-type': 'application/json'})),
      converter: converter,
      errorConverter: converter,
    );
    addTearDown(client.dispose);

    final result = await client.send<Model, Model>(
      chopper.Request('GET', Uri.parse('/model'), client.baseUrl),
    );

    expect(result.body, isNull);
    expect(result.isSuccessful, isTrue);
    expect(result.error, isNull);
  });

  for (final statusCode in [400, 500]) {
    for (final body in ['{"message":"failed"}', 'null', '', '"null"']) {
      test('Error conversion stays unchanged: $statusCode $body', () async {
        final original = responseFor(body, statusCode: statusCode);
        final expected = await const chopper.JsonConverter()
            .convertError<Model, Model>(original);
        final result = await converter.convertError<Model, Model>(original);

        expect(result.body, expected.body);
        expect(result.base, same(original.base));
        expect(result.statusCode, statusCode);
        expect(result.headers, original.headers);
        expect(result.error, same(original.error));
      });
    }

    test('Client preserves a $statusCode error response', () async {
      final client = chopper.ChopperClient(
        baseUrl: Uri.parse('https://example.test'),
        client: MockClient((request) async => http.Response(
            '{"message":"failed"}', statusCode,
            headers: {'content-type': 'application/json'})),
        converter: converter,
        errorConverter: converter,
      );
      addTearDown(client.dispose);

      final result = await client.send<Model, Model>(
        chopper.Request('GET', Uri.parse('/model'), client.baseUrl),
      );

      expect(result.body, isNull);
      expect(result.statusCode, statusCode);
      expect(result.error, {'message': 'failed'});
    });
  }
}
''';
