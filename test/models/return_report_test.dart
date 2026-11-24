import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/return_report.dart';

void main() {
  group('ReturnReport.toJson', () {
    test("names each category as the server spells it, 'missing_pages' included", () {
      expect(const ReturnReport(category: ReportCategory.damaged, note: 'Cover torn').toJson(), {'category': 'damaged', 'note': 'Cover torn'});
      expect(
        const ReturnReport(category: ReportCategory.missingPages, note: 'Pages 40-52').toJson(),
        {'category': 'missing_pages', 'note': 'Pages 40-52'},
      );
      expect(const ReturnReport(category: ReportCategory.other, note: 'Smells of smoke').toJson(), {'category': 'other', 'note': 'Smells of smoke'});
    });

    test('leaves the note out when there is none, rather than sending null', () {
      final json = const ReturnReport(category: ReportCategory.damaged).toJson();
      expect(json, {'category': 'damaged'});
      expect(json.containsKey('note'), false);
    });
  });
}
