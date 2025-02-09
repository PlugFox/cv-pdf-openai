// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

void main() => l.capture(
      () => runZonedGuarded<void>(
        () => runApp(const App()),
        (error, stackTrace) => l.e(
          'Top level exception: $error\n$stackTrace',
          stackTrace,
        ),
      ),
      LogOptions(
        outputInRelease: true,
        handlePrint: true,
        printColors: false,
      ),
    );

/// {@template app}
/// App widget.
/// {@endtemplate}
class App extends StatelessWidget {
  /// {@macro app}
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CV Picker',
        debugShowCheckedModeBanner: false,
        home: HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key, // ignore: unused_element
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final Converter<List<int>, Map<String, Object?>> _decoder =
      Utf8Decoder()
          .fuse(const JsonDecoder())
          .cast<List<int>, Map<String, Object?>>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final http.Client _client;
  final CV _cv = CV();
  ScaffoldMessengerState? _messenger;
  late StreamSubscription<LogMessage> _errorSubscription;
  ThemeData? _theme;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _errorSubscription = l
        .where((event) => event.level.maybeWhen(
              error: () => true,
              warning: () => true,
              orElse: () => false,
            ))
        .listen(
      (message) {
        _messenger
          ?..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(message.message.toString()),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
      },
      cancelOnError: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _theme = Theme.of(context);
  }

  @override
  void dispose() {
    super.dispose();
    _errorSubscription.cancel();
    _client.close();
  }

  void _pickPDF() => runZonedGuarded<void>(
        () async {
          const url = String.fromEnvironment('URL', defaultValue: '');
          if (url.isEmpty) {
            l.e('URL is not set');
            return;
          }

          final result = await FilePicker.platform.pickFiles(
            allowMultiple: false,
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
            withData: true,
          );
          if (result == null || result.files.length != 1) return;
          final file = result.files.single;
          final PlatformFile(name: fileName, bytes: fileBytes) = file;
          if (fileBytes == null || fileBytes.isEmpty) {
            l.e('Invalid file: $fileName');
            return;
          }

          final extension = p.extension(fileName);
          if (extension != '.pdf') {
            l.e('Invalid file extension: $extension');
            return;
          }

          {
            setState(_cv.clear);

            final request = http.MultipartRequest(
              'POST',
              Uri.parse(url),
            )..files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  fileBytes,
                  filename: p.basename(fileName),
                ),
              );

            final response = await _client.send(request);
            if (response.statusCode != 200) {
              l.e('Failed to upload file: $response');
              return;
            }

            final responseBytes = await response.stream.toBytes();
            final map = _decoder.convert(responseBytes);

            if (map['error'] case Map<String, Object?> error) {
              l.e(error['message']?.toString() ?? 'Unknown error');
              return;
            } else if (map['data'] case Map<String, Object?> data) {
              setState(() {
                _cv.fromJson(data);
              });
              return;
            } else {
              l.e('Invalid response: $map');
              return;
            }
          }
        },
        l.e,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        body: CustomScrollView(
          primary: true,
          slivers: <Widget>[
            SliverAppBar(
              title: const Text('CV Picker'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Clear',
                  onPressed: () {
                    setState(_cv.clear);
                  },
                ),
                SizedBox(width: 16.0),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Pick PDF',
                  onPressed: _pickPDF,
                ),
                SizedBox(width: 16.0),
              ],
            ),
            if (_cv.isValid) ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_cv.name.isNotEmpty)
                        Text(_cv.name, style: _theme?.textTheme.headlineLarge),
                      if (_cv.position.isNotEmpty)
                        Text(_cv.position,
                            style: _theme?.textTheme.headlineSmall),
                      if (_cv.age > 0)
                        Text('Age: ${_cv.age}',
                            style: _theme?.textTheme.headlineSmall),
                    ],
                  ),
                ),
              ),
              for (final contact in _cv.contacts)
                SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(contact.type),
                    subtitle: Text(contact.value),
                  ),
                ),
              for (final section in _cv.sections) ...[
                SliverToBoxAdapter(
                  child: Divider(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(left: 16.0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      section.type,
                      style: _theme?.textTheme.headlineSmall,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(left: 24.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = section.items[index];
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (item.title.isNotEmpty)
                                Text(
                                  item.title,
                                  style: _theme?.textTheme.titleLarge,
                                ),
                              if (item.subtitle.isNotEmpty)
                                Text(
                                  item.subtitle,
                                  style: _theme?.textTheme.titleSmall,
                                ),
                              if (item.content.isNotEmpty)
                                Text(
                                  item.content,
                                  style: _theme?.textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        );
                      },
                      childCount: section.items.length,
                    ),
                  ),
                ),
              ]
            ] else ...<Widget>[
              SliverFillRemaining(
                child: Center(
                  child: Text('No CV loaded'),
                ),
              ),
            ],
          ],
        ),
      );
}

class CV {
  String name = '';
  int age = 0;
  String position = '';

  List<Contact> contacts = <Contact>[];

  List<Section> sections = <Section>[];

  bool get isValid => name.isNotEmpty && position.isNotEmpty;

  void clear() {
    name = '';
    age = 0;
    position = '';
    contacts.clear();
    sections.clear();
  }

  void normalize() {
    contacts.removeWhere((contact) => !contact.isValid);
    for (final section in sections) {
      section.items.removeWhere((item) => !item.isValid);
    }
    sections.removeWhere((section) => !section.isValid);
  }

  void fromJson(Map<String, Object?> json) {
    clear();

    name = json['name']?.toString() ?? '';
    age = switch (json['age']) {
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      Object? _ => 0,
    };
    position = json['position']?.toString() ?? '';

    if (json['contacts'] case Iterable<Object?> c) {
      for (final map in c.whereType<Map<String, Object?>>()) {
        contacts.add(Contact()
          ..type = map['type']?.toString() ?? ''
          ..value = map['value']?.toString() ?? '');
      }
    }

    if (json['sections'] case Iterable<Object?> s) {
      for (final map in s.whereType<Map<String, Object?>>()) {
        sections.add(
          Section()
            ..type = map['type']?.toString() ?? ''
            ..items = switch (map['items']) {
              Iterable<Object?> i => [
                  for (final item in i.whereType<Map<String, Object?>>())
                    Section$Item()
                      ..title = item['title']?.toString() ?? ''
                      ..subtitle = item['subtitle']?.toString() ?? ''
                      ..content = item['content']?.toString() ?? ''
                ],
              _ => [],
            },
        );
      }
    }

    normalize();
  }
}

class Contact {
  String type = '';
  String value = '';

  bool get isValid => type.isNotEmpty && value.isNotEmpty;
}

class Section {
  String type = '';
  List<Section$Item> items = <Section$Item>[];

  bool get isValid => type.isNotEmpty && items.isNotEmpty;
}

class Section$Item {
  String title = '';
  String subtitle = '';
  String content = '';

  bool get isValid => title.isNotEmpty && content.isNotEmpty;
}
