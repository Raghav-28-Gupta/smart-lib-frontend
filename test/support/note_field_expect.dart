// test/support/note_field_expect.dart
//
// The three dialogs that take a note (the fine dispute, the Return report and the
// seat/room report) share one `NoteField`, so what they have in common is checked the
// same way in each dialog's own test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The words under a note field that is over the limit, as well as its red counter.
const noteTooLongMessage = 'At most 300 characters';

/// Expects the [textField] (a multi-line note) to draw a modest rounded rectangle, not
/// the 999 px pill the theme gives single-line fields. A pill on a multi-line field
/// scales its corners to half its height (about 88 px on a 176 px field) and the
/// floating label's gap then removes the top edge. Reads the decoration the field
/// really draws, after the theme is merged in.
void expectNoteFieldIsNotAPill(WidgetTester tester, Finder textField) {
  final decorator = find.descendant(of: textField, matching: find.byType(InputDecorator));
  expect(decorator, findsOneWidget);
  final border = tester.widget<InputDecorator>(decorator).decoration.border;
  expect(border, isA<OutlineInputBorder>(), reason: 'a note field draws an outline');
  final radius = (border! as OutlineInputBorder).borderRadius.resolve(TextDirection.ltr);
  final height = tester.getSize(decorator).height;
  for (final corner in [radius.topLeft, radius.topRight, radius.bottomLeft, radius.bottomRight]) {
    expect(corner.x, inInclusiveRange(8, 16), reason: 'a modest radius, as the theme\'s other rounded shapes');
    expect(corner.y, corner.x);
    expect(corner.x * 2, lessThan(height), reason: 'a stadium would round the corners to half the height');
  }
}
