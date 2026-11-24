import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/ui/confirm_dialog.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/core/ui/ui_controller.dart';
import 'package:smartlib_frontend/models/return_report.dart';
import '../../support/mock_overrides.dart';
import '../../support/note_field_expect.dart';

typedef _Call = ({String loanId, ReturnReport? report});

/// The Return dialog as the tab shell hosts it, with the action it confirms
/// recorded in [calls] instead of reaching a repository.
class _Shell {
  _Shell(this.ui);

  final UiController ui;
  final calls = <_Call>[];

  void askToReturn([String loanId = 'loan1']) => ui.askReturnLoan(loanId);
}

Future<_Shell> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(),
    child: MaterialApp(
      theme: buildSmartLibTheme(),
      builder: withToasts,
      home: const Scaffold(body: ConfirmDialogHost()),
    ),
  ));
  final container = ProviderScope.containerOf(tester.element(find.byType(ConfirmDialogHost)));
  final shell = _Shell(container.read(uiControllerProvider.notifier));
  shell.ui.onConfirmReturnLoan = (id, report) async => shell.calls.add((loanId: id, report: report));
  return shell;
}

Future<_Shell> _openReturnDialog(WidgetTester tester) async {
  final shell = await _pumpHost(tester);
  shell.askToReturn();
  await tester.pumpAndSettle();
  return shell;
}

const _tickLabel = 'Report a problem with this copy';

final _returnButton = find.widgetWithText(FilledButton, 'Return');
final _noteField = find.byType(TextField);

bool _returnEnabled(WidgetTester tester) => tester.widget<FilledButton>(_returnButton).onPressed != null;

Future<void> _tickTheBox(WidgetTester tester) async {
  await tester.tap(find.text(_tickLabel));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _typeNote(WidgetTester tester, String text) async {
  await tester.enterText(_noteField, text);
  await tester.pumpAndSettle();
}

Future<void> _tapReturn(WidgetTester tester) async {
  await tester.tap(_returnButton);
  await tester.pumpAndSettle();
}

void main() {
  group('the Return dialog', () {
    testWidgets('keeps its title and text, and the report choices are hidden until the box is ticked', (tester) async {
      await _openReturnDialog(tester);

      expect(find.text('Return this book?'), findsOneWidget);
      expect(find.text('This will be marked returned right away.'), findsOneWidget);
      expect(find.text(_tickLabel), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(find.text('Damaged'), findsNothing);
      expect(find.text('Missing pages'), findsNothing);
      expect(find.text('Other'), findsNothing);
      expect(_noteField, findsNothing);

      await _tickTheBox(tester);

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
      expect(find.text('Damaged'), findsOneWidget);
      expect(find.text('Missing pages'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(_noteField, findsOneWidget);
    });

    testWidgets('Return without a report behaves as before', (tester) async {
      final shell = await _openReturnDialog(tester);
      expect(_returnEnabled(tester), true);

      await _tapReturn(tester);

      expect(shell.calls, [(loanId: 'loan1', report: null)]);
      expect(find.text('Return this book?'), findsNothing); // closed at once, the toast reports the outcome
      expect(find.text('Returned.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Cancel closes the dialog and returns nothing', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Return this book?'), findsNothing);
      expect(shell.calls, isEmpty);
    });

    testWidgets('ticking the box without choosing what is wrong keeps Return disabled', (tester) async {
      await _openReturnDialog(tester);
      await _tickTheBox(tester);

      expect(_returnEnabled(tester), false);

      await _choose(tester, 'Damaged');
      expect(_returnEnabled(tester), true);
    });

    testWidgets('Damaged needs no note, and is sent without one', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');

      expect(_returnEnabled(tester), true);
      await _tapReturn(tester);

      expect(shell.calls.single.loanId, 'loan1');
      expect(shell.calls.single.report!.category, ReportCategory.damaged);
      expect(shell.calls.single.report!.note, isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Other needs a note before Return enables', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Other');

      expect(_returnEnabled(tester), false);

      await _typeNote(tester, '    \n  ');
      expect(_returnEnabled(tester), false); // spaces are not a note

      await _typeNote(tester, 'Pages are wet');
      expect(_returnEnabled(tester), true);

      await _tapReturn(tester);
      expect(shell.calls.single.report!.category, ReportCategory.other);
      expect(shell.calls.single.report!.note, 'Pages are wet');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Return with a report calls the action with it, the note trimmed', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Missing pages');
      await _typeNote(tester, '  Pages 40 to 52 are missing \n');

      await _tapReturn(tester);

      expect(shell.calls, hasLength(1));
      expect(shell.calls.single.loanId, 'loan1');
      expect(shell.calls.single.report!.category, ReportCategory.missingPages);
      expect(shell.calls.single.report!.note, 'Pages 40 to 52 are missing');
      expect(shell.calls.single.report!.toJson(), {'category': 'missing_pages', 'note': 'Pages 40 to 52 are missing'});
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a blank note on a category that does not need one is sent as no note, never an empty string', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');
      await _typeNote(tester, '   \n ');

      await _tapReturn(tester);

      expect(shell.calls.single.report!.note, isNull);
      expect(shell.calls.single.report!.toJson().containsKey('note'), false);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('unticking the box again sends no report, whatever was chosen', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Other'); // invalid so far: no note
      expect(_returnEnabled(tester), false);

      await _tickTheBox(tester); // off again
      expect(find.text('Other'), findsNothing);
      expect(_returnEnabled(tester), true);

      await _tapReturn(tester);
      expect(shell.calls, [(loanId: 'loan1', report: null)]);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the toast text differs: Returned. without a report, a thank-you with one', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tapReturn(tester);
      expect(find.text('Returned.'), findsOneWidget);
      expect(find.text('Returned. Thanks for the report.'), findsNothing);
      await tester.pump(const Duration(seconds: 3)); // the toast goes

      shell.askToReturn('loan2');
      await tester.pumpAndSettle();
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');
      await _tapReturn(tester);
      expect(find.text('Returned. Thanks for the report.'), findsOneWidget);
      expect(find.text('Returned.'), findsNothing);
      expect(shell.calls.map((c) => c.loanId), ['loan1', 'loan2']);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('closing and reopening never shows the previous ticks', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Other');
      await _typeNote(tester, 'Smells of smoke');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      shell.askToReturn();
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(find.text('Damaged'), findsNothing);
      expect(_noteField, findsNothing);
      expect(_returnEnabled(tester), true);

      // Ticking it again starts blank too: nothing chosen, no note.
      await _tickTheBox(tester);
      expect(_returnEnabled(tester), false);
      expect(tester.widget<TextField>(_noteField).controller!.text, isEmpty);
      expect(tester.widget<RadioGroup<ReportCategory>>(find.byType(RadioGroup<ReportCategory>)).groupValue, isNull);
    });
  });

  testWidgets('with the choices open on a small phone the dialog scrolls instead of overflowing, Return stays in reach', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.reset);
    final shell = await _openReturnDialog(tester);
    await _tickTheBox(tester);
    await tester.ensureVisible(find.text('Other')); // below the fold, so the student scrolls to it
    await tester.pumpAndSettle();
    await _choose(tester, 'Other');
    await _typeNote(tester, 'Smells of smoke');

    expect(tester.takeException(), isNull);
    await _tapReturn(tester);
    expect(shell.calls.single.report!.category, ReportCategory.other);
    await tester.pump(const Duration(seconds: 3));
  });

  group('the note limit counts as the server does, in UTF-16 code units of the trimmed text', () {
    // One emoji outside the BMP is a single character to the eye but two code units.
    const emoji = '\u{1F4A5}';

    testWidgets('300 code units are accepted, 301 are not, and the counter says so', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Other');

      await _typeNote(tester, 'a' * 300);
      expect(find.text('300/300'), findsOneWidget);
      expect(_returnEnabled(tester), true);

      await _typeNote(tester, 'a' * 301);
      expect(find.text('301/300'), findsOneWidget);
      expect(_returnEnabled(tester), false);

      await _typeNote(tester, 'a' * 300);
      await _tapReturn(tester);
      expect(shell.calls.single.report!.note, 'a' * 300);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a note of 301 code units that is only 151 characters to the eye keeps Return disabled', (tester) async {
      await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');

      final note = '${emoji * 150}a'; // 150 two-unit emoji and one letter
      expect(note.length, 301);
      expect(note.characters.length, 151); // Flutter's maxLength would count this as 151 and let it through
      await _typeNote(tester, note);

      expect(find.text('301/300'), findsOneWidget);
      expect(_returnEnabled(tester), false);

      // Exactly 300 units (150 emoji) is fine.
      await _typeNote(tester, emoji * 150);
      expect(find.text('300/300'), findsOneWidget);
      expect(_returnEnabled(tester), true);
    });

    testWidgets('the limit applies to the trimmed note: surrounding spaces do not count', (tester) async {
      final shell = await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Other');

      await _typeNote(tester, '   ${'a' * 300}   ');
      expect(find.text('300/300'), findsOneWidget);
      expect(_returnEnabled(tester), true);

      await _tapReturn(tester);
      expect(shell.calls.single.report!.note, 'a' * 300);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a note over the limit on Damaged also keeps Return disabled', (tester) async {
      await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');
      await _typeNote(tester, 'b' * 301);

      expect(_returnEnabled(tester), false);
    });

    testWidgets('over the limit the field says why in words, not only in colour, and the words go at 300', (tester) async {
      await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');

      await _typeNote(tester, 'b' * 301);
      expect(find.text(noteTooLongMessage), findsOneWidget);
      expect(tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration.errorText, noteTooLongMessage);
      expect(tester.widget<Text>(find.text('301/300')).style?.color, Theme.of(tester.element(_noteField)).colorScheme.error);
      expect(_returnEnabled(tester), false);

      await _typeNote(tester, 'b' * 300);
      expect(find.text(noteTooLongMessage), findsNothing);
      expect(_returnEnabled(tester), true);
    });

    testWidgets('a note of 151 emoji (302 units) shows the words, and 150 does not', (tester) async {
      await _openReturnDialog(tester);
      await _tickTheBox(tester);
      await _choose(tester, 'Damaged');

      await _typeNote(tester, emoji * 151);
      expect(find.text('302/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);
      expect(_returnEnabled(tester), false);

      await _typeNote(tester, emoji * 150);
      expect(find.text(noteTooLongMessage), findsNothing);
      expect(_returnEnabled(tester), true);
    });
  });

  testWidgets('the note field draws a rounded rectangle under the app theme, and a long note fits a 360 x 740 phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);
    final shell = await _openReturnDialog(tester);
    await _tickTheBox(tester);
    await _choose(tester, 'Other');
    expectNoteFieldIsNotAPill(tester, _noteField);

    await _typeNote(tester, 'it smells of smoke '.padRight(300, 'x'));
    expect(tester.takeException(), isNull);
    expectNoteFieldIsNotAPill(tester, _noteField);

    await tester.ensureVisible(_returnButton);
    await _tapReturn(tester);
    expect(shell.calls.single.report!.category, ReportCategory.other);
    await tester.pump(const Duration(seconds: 3));
  });

  group('accessibility', () {
    testWidgets('the checkbox and each choice carry a plain label', (tester) async {
      final handle = tester.ensureSemantics();
      await _openReturnDialog(tester);
      await _tickTheBox(tester);

      expect(find.bySemanticsLabel(_tickLabel), findsOneWidget);
      expect(find.bySemanticsLabel('Damaged'), findsOneWidget);
      expect(find.bySemanticsLabel('Missing pages'), findsOneWidget);
      expect(find.bySemanticsLabel('Other'), findsOneWidget);
      handle.dispose();
    });
  });
}
