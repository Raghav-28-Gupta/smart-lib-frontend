// lib/features/notices/notice_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/notice.dart';

/// The student's own library notices -- the backend's GET /notices/me: the last 7
/// days, newest first, at most 20. The library writes them (a librarian's
/// reminder, the outcome of a dispute or a report); the student only reads them.
abstract class NoticeRepository {
  Future<List<Notice>> myNotices();
}

class HttpNoticeRepository implements NoticeRepository {
  HttpNoticeRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Notice>> myNotices() async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/notices/me'));
    return res.data!.cast<Map<String, dynamic>>().map(Notice.fromJson).toList();
  }
}

/// Test double. Serves [notices] as they are now (a test may reassign them).
class MockNoticeRepository implements NoticeRepository {
  MockNoticeRepository({List<Notice> notices = const []}) : notices = List.of(notices);

  List<Notice> notices;

  @override
  Future<List<Notice>> myNotices() async => List.of(notices);
}

final noticeRepositoryProvider = Provider<NoticeRepository>((ref) => HttpNoticeRepository(ref.watch(apiClientProvider)));
