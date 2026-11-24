// test/widgets/note_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/widgets/note_field.dart';
import '../support/note_field_expect.dart';

// One emoji outside the BMP is a single character to the eye but two UTF-16 code units.
const _emoji = '\u{1F4A5}';

Widget _app(
  TextEditingController controller, {
  bool enabled = true,
  String label = 'Note (optional)',
  ThemeData? theme,
  ValueChanged<String>? onChanged,
}) =>
    MaterialApp(
      theme: theme ?? buildSmartLibTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: NoteField(controller: controller, label: label, enabled: enabled, onChanged: onChanged),
        ),
      ),
    );

Future<TextEditingController> _pump(WidgetTester tester, {bool enabled = true, ThemeData? theme}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_app(controller, enabled: enabled, theme: theme));
  return controller;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

InputDecoration _decoration(WidgetTester tester) =>
    tester.widget<InputDecorator>(find.descendant(of: find.byType(TextField), matching: find.byType(InputDecorator))).decoration;

void main() {
  group('the limit is the server\'s: the trimmed text\'s length in UTF-16 code units, against one 300', () {
    test('the one constant is 300', () {
      expect(kMaxNoteLength, 300);
    });

    test('counts code units, not what the student sees', () {
      expect(noteLength('abc'), 3);
      expect(noteLength(_emoji), 2); // one emoji, two units
      expect(noteLength('é'), 2); // "e" and a combining acute accent: one letter to the eye
      expect(noteLength('क्षि'), 4); // a Devanagari conjunct with a vowel sign
    });

    test('is the length after trimming, as the server trims first', () {
      expect(noteLength('   hello  \n'), 5);
      expect(noteLength('   \n\t '), 0);
      expect(noteTooLong('${' ' * 20}${'a' * 300}${'\n' * 20}'), false);
    });

    test('300 units are accepted and 301 are not', () {
      expect(noteTooLong('a' * 299), false);
      expect(noteTooLong('a' * 300), false);
      expect(noteTooLong('a' * 301), true);
    });

    test('150 emoji are accepted and 151 are not, though 151 is only 151 characters to the eye', () {
      expect(noteTooLong(_emoji * 150), false);
      expect(noteTooLong(_emoji * 151), true);
      expect(noteTooLong('${_emoji * 150}a'), true); // 301 units
    });

    test('a long text with combining marks counts by code units', () {
      expect(noteTooLong('é' * 150), false); // 300 units, 150 letters
      expect(noteTooLong('é' * 151), true); // 302 units, 151 letters
      expect(noteTooLong('कि' * 150), false);
      expect(noteTooLong('कि' * 151), true);
    });
  });

  group('NoteField', () {
    testWidgets('shows n/300 of the trimmed text, with no error up to 300', (tester) async {
      await _pump(tester);
      expect(find.text('0/300'), findsOneWidget);
      expect(find.text('Note (optional)'), findsOneWidget);

      await _type(tester, '  hello  ');
      expect(find.text('5/300'), findsOneWidget);

      await _type(tester, 'a' * 300);
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
      expect(_decoration(tester).errorText, isNull);
    });

    testWidgets('over the limit it shows the message and the counter in the error colour, and keeps the student\'s text', (tester) async {
      final controller = await _pump(tester);

      await _type(tester, 'a' * 301);

      expect(find.text('301/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);
      expect(_decoration(tester).errorText, noteTooLongMessage);
      expect(tester.widget<Text>(find.text('301/300')).style?.color, Theme.of(tester.element(find.byType(TextField))).colorScheme.error);
      expect(controller.text, 'a' * 301); // not truncated

      await _type(tester, 'a' * 300);
      expect(find.text(noteTooLongMessage), findsNothing);
    });

    testWidgets('151 emoji are over, 150 are not', (tester) async {
      await _pump(tester);

      await _type(tester, _emoji * 151);
      expect(find.text('302/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);

      await _type(tester, _emoji * 150);
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
    });

    testWidgets('a text with combining marks is counted by code units', (tester) async {
      await _pump(tester);

      await _type(tester, 'é' * 151);
      expect(find.text('302/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);

      await _type(tester, 'é' * 150);
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
    });

    testWidgets('the counter follows the controller even when the text is set from outside', (tester) async {
      final controller = await _pump(tester);

      controller.text = 'a' * 301;
      await tester.pump();
      expect(find.text('301/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);

      controller.clear();
      await tester.pump();
      expect(find.text('0/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
    });

    testWidgets('tells its parent about every change, so it can recompute what it allows', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final seen = <String>[];
      await tester.pumpWidget(_app(controller, onChanged: seen.add));

      await _type(tester, 'a');
      await _type(tester, 'ab');

      expect(seen, ['a', 'ab']);
    });

    testWidgets('a disabled field takes no input', (tester) async {
      await _pump(tester, enabled: false);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    });

    testWidgets('is a multi-line field with no maxLength of its own (Flutter would count grapheme clusters)', (tester) async {
      await _pump(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, isNull);
      expect(field.minLines, greaterThan(1));
      expect(field.maxLines, greaterThanOrEqualTo(field.minLines!));
    });

    testWidgets('draws a rounded rectangle under the app theme, not the theme\'s pill', (tester) async {
      await _pump(tester);
      expectNoteFieldIsNotAPill(tester, find.byType(TextField));
      await _type(tester, 'a long note ' * 20);
      expectNoteFieldIsNotAPill(tester, find.byType(TextField));
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a rounded rectangle under the default theme too', (tester) async {
      await _pump(tester, theme: ThemeData());
      expectNoteFieldIsNotAPill(tester, find.byType(TextField));
    });

    testWidgets('keeps the outline colour the theme gives its fields', (tester) async {
      await _pump(tester);
      final themed = Theme.of(tester.element(find.byType(TextField))).inputDecorationTheme.border! as OutlineInputBorder;
      final border = _decoration(tester).border! as OutlineInputBorder;
      expect(border.borderSide, themed.borderSide);
    });
  });

  testWidgets('a single-line field keeps the theme\'s pill: only the note field is reshaped', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildSmartLibTheme(),
      home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: TextField(decoration: InputDecoration(labelText: 'Email')))),
    ));
    final border = tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration.border! as OutlineInputBorder;
    expect(border.borderRadius.resolve(TextDirection.ltr).topLeft.x, 999);
  });
}
