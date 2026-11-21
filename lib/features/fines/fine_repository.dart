// lib/features/fines/fine_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../models/fine.dart';

/// The student's own fines -- the backend's GET /fines/me. The librarian's side
/// (marking paid, waiving, lowering) is the admin console's.
abstract class FineRepository {
  Future<FinesSummary> myFines();
}

class HttpFineRepository implements FineRepository {
  HttpFineRepository(this._dio);

  final Dio _dio;

  @override
  Future<FinesSummary> myFines() async {
    final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/fines/me'));
    return FinesSummary.fromJson(res.data!);
  }
}

/// Test double. Serves [fines] as they are now (a test may reassign them), with
/// the total the server computes: what is still owed, outstanding or adjusted.
class MockFineRepository implements FineRepository {
  MockFineRepository({List<Fine> fines = const []}) : fines = List.of(fines);

  List<Fine> fines;

  @override
  Future<FinesSummary> myFines() async => FinesSummary(
        fines: List.of(fines),
        outstandingTotal: fines
            .where((f) => f.status == FineStatus.outstanding || f.status == FineStatus.adjusted)
            .fold(0.0, (total, f) => total + f.amount),
      );
}

final fineRepositoryProvider = Provider<FineRepository>((ref) => HttpFineRepository(ref.watch(apiClientProvider)));
