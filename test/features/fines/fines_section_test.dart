// test/features/fines/fines_section_test.dart
//
// The Dispute dialog and the Dispute button on a phone-sized surface, under the app
// theme. The dialog's flow (send, refuse, double tap) is covered with My Loans in
// test/features/loans/loans_screen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/ui/toast_overlay.dart';
import 'package:smartlib_frontend/features/fines/fine_repository.dart';
import 'package:smartlib_frontend/features/fines/fines_section.dart';
import 'package:smartlib_frontend/models/fine.dart';
import '../../support/mock_overrides.dart';
import '../../support/note_field_expect.dart';

Fine _fine(
  String id, {
  String item = 'Operating System Concepts',
  double amount = 30,
  double? was,
  FineStatus status = FineStatus.outstanding,
}) =>
    Fine(
      id: id, reason: FineReason.overdue, item: item, amount: amount, originalAmount: was ?? amount,
      status: status, date: DateTime.now().subtract(const Duration(days: 2)),
    );

/// The Fines section alone, on a 360 x 740 phone (the app's main platform), under the
/// real theme and with the toast layer as the app mounts it.
Future<MockFineRepository> _pumpFines(WidgetTester tester, {List<Fine>? fines}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 740);
  addTearDown(tester.view.reset);
  final repo = MockFineRepository(fines: fines ?? [_fine('f1')]);
  await tester.pumpWidget(ProviderScope(
    overrides: mockRepositoryOverrides(fines: repo),
    child: MaterialApp(
      theme: buildSmartLibTheme(),
      builder: withToasts,
      home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: FinesSection())),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

final _disputeButtons = find.widgetWithText(TextButton, 'Dispute');
final _reasonField = find.byType(TextField);
final _sendButton = find.widgetWithText(FilledButton, 'Send');

bool _sendEnabled(WidgetTester tester) => tester.widget<FilledButton>(_sendButton).onPressed != null;

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(_disputeButtons.first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_reasonField, text);
  await tester.pumpAndSettle();
}

void main() {
  group('the Dispute dialog on a 360 x 740 phone', () {
    testWidgets('fits the screen with a long reason, and its field is a rounded rectangle, not the theme\'s pill', (tester) async {
      await _pumpFines(tester);
      await _openDialog(tester);

      expect(find.text('Dispute this fine'), findsOneWidget);
      expectNoteFieldIsNotAPill(tester, _reasonField); // empty, as it first opens

      // A reason that fills the field and scrolls it (300 characters is about a dozen lines here).
      await _type(tester, List.filled(60, 'delayed').join(' ').substring(0, 300));
      expect(tester.takeException(), isNull);
      expectNoteFieldIsNotAPill(tester, _reasonField);

      // The field and the buttons stay on the screen.
      for (final part in [_reasonField, _sendButton]) {
        final rect = tester.getRect(part);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(740));
      }
      expect(_sendEnabled(tester), true);
    });

    testWidgets('keeps the label, the counter and the hint of the dialog it had', (tester) async {
      await _pumpFines(tester);
      await _openDialog(tester);

      expect(find.text('Why do you think this fine is wrong?'), findsOneWidget);
      expect(find.text('0/300'), findsOneWidget);
      await _type(tester, '  It was returned on time.  ');
      expect(find.text('${'It was returned on time.'.length}/300'), findsOneWidget); // trimmed, as the server counts
      expect(find.text(noteTooLongMessage), findsNothing);
    });
  });

  group('the reason limit counts as the server does, in UTF-16 code units of the trimmed text', () {
    // One emoji outside the BMP is a single character to the eye but two code units.
    const emoji = '\u{1F4A5}';

    testWidgets('150 emoji (300 units) are accepted and 151 (302 units, 151 characters to the eye) are refused', (tester) async {
      await _pumpFines(tester);
      await _openDialog(tester);

      final refused = emoji * 151;
      expect(refused.length, 302);
      expect(refused.characters.length, 151); // Flutter's maxLength would count 151 and let it through
      await _type(tester, refused);
      expect(find.text('302/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);
      expect(_sendEnabled(tester), false);
      // The student's own text is left alone, not cut to fit.
      expect(tester.widget<TextField>(_reasonField).controller!.text, refused);

      await _type(tester, emoji * 150);
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
      expect(_sendEnabled(tester), true);
    });

    testWidgets('a Hindi reason counts its vowel signs and conjuncts, not the letters the student sees', (tester) async {
      await _pumpFines(tester);
      await _openDialog(tester);

      // "ki" (a consonant and a vowel sign): one letter to the eye, two code units.
      const ki = 'कि';
      final refused = ki * 151;
      expect(refused.length, 302);
      expect(refused.characters.length, lessThan(300)); // so Flutter's maxLength would have let it through
      await _type(tester, refused);
      expect(find.text('302/300'), findsOneWidget);
      expect(_sendEnabled(tester), false);

      // "kshi" (consonant, virama, consonant, vowel sign): four units for what reads as one or two letters.
      const kshi = 'क्षि';
      expect(kshi.length, 4);
      await _type(tester, kshi * 76); // 304 units
      expect(find.text('304/300'), findsOneWidget);
      expect(_sendEnabled(tester), false);

      await _type(tester, kshi * 75); // 300 units
      expect(find.text('300/300'), findsOneWidget);
      expect(_sendEnabled(tester), true);
    });

    testWidgets('exactly 300 is accepted and 301 is not; spaces around the reason are not counted', (tester) async {
      final repo = await _pumpFines(tester);
      await _openDialog(tester);

      await _type(tester, 'a' * 301);
      expect(find.text('301/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsOneWidget);
      expect(_sendEnabled(tester), false);

      await _type(tester, '   ${'a' * 300}   \n');
      expect(find.text('300/300'), findsOneWidget);
      expect(find.text(noteTooLongMessage), findsNothing);
      expect(_sendEnabled(tester), true);

      await tester.tap(_sendButton);
      await tester.pumpAndSettle();
      expect(repo.disputes, [(fineId: 'f1', reason: 'a' * 300)]);
      await tester.pump(const Duration(seconds: 3)); // the toast goes
    });

    testWidgets('over the limit the field says why in words, and the counter is in the error colour', (tester) async {
      await _pumpFines(tester);
      await _openDialog(tester);

      await _type(tester, 'a' * 301);

      final decoration = tester.widget<InputDecorator>(find.descendant(of: _reasonField, matching: find.byType(InputDecorator))).decoration;
      expect(decoration.errorText, noteTooLongMessage);
      final error = Theme.of(tester.element(_reasonField)).colorScheme.error;
      expect(tester.widget<Text>(find.text('301/300')).style?.color, error);

      await _type(tester, 'a' * 300);
      final fits = tester.widget<InputDecorator>(find.descendant(of: _reasonField, matching: find.byType(InputDecorator))).decoration;
      expect(fits.errorText, isNull);
    });
  });

  group('the Dispute button for a screen reader', () {
    testWidgets('names its fine, so several cards do not all say "Dispute"; the visible text is unchanged', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpFines(tester, fines: [
        _fine('f1'),
        _fine('f2', item: 'Sapiens', amount: 20, was: 30, status: FineStatus.adjusted),
        _fine('f3', item: ''),
      ]);

      expect(_disputeButtons, findsNWidgets(3));
      expect(find.bySemanticsLabel('Dispute fine of ₹30 for Operating System Concepts'), findsOneWidget);
      expect(find.bySemanticsLabel('Dispute fine of ₹20 for Sapiens'), findsOneWidget);
      // A fine that names no book or resource has nothing to add after its amount.
      expect(find.bySemanticsLabel('Dispute fine of ₹30'), findsOneWidget);
      handle.dispose();
    });
  });
}
