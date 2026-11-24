// lib/features/fines/fine_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../models/fine.dart';

/// The student's own fines -- the backend's GET /fines/me -- and the one write they
/// can make, disputing a fine. The librarian's side (marking paid, waiving,
/// lowering, answering a dispute) is the admin console's.
abstract class FineRepository {
  Future<FinesSummary> myFines();

  /// Disputes one of the student's own outstanding or adjusted fines, once, with
  /// the [reason] they give (the server takes 1 to 300 characters, trimmed). The
  /// answer carries nothing the app needs: the dispute comes back with the fines.
  /// Refused (409) when the fine is already paid or waived or was disputed before.
  Future<void> dispute(String fineId, String reason);
}

class HttpFineRepository implements FineRepository {
  HttpFineRepository(this._dio);

  final Dio _dio;

  @override
  Future<FinesSummary> myFines() async {
    final res = await guardApi(() => _dio.get<Map<String, dynamic>>('/fines/me'));
    return FinesSummary.fromJson(res.data!);
  }

  @override
  Future<void> dispute(String fineId, String reason) async {
    await guardApi(() => _dio.post<Object?>('/fines/${Uri.encodeComponent(fineId)}/dispute', data: {'reason': reason}));
  }
}

/// Test double. Serves [fines] as they are now (a test may reassign them), with
/// the total the server computes: what is still owed, outstanding or adjusted. A
/// dispute is refused as the server refuses it and otherwise recorded in
/// [disputes] and on the fine as an open dispute.
class MockFineRepository implements FineRepository {
  MockFineRepository({List<Fine> fines = const []}) : fines = List.of(fines);

  List<Fine> fines;

  /// What the student sent, in order, for the disputes the "server" accepted.
  final disputes = <({String fineId, String reason})>[];

  @override
  Future<FinesSummary> myFines() async => FinesSummary(
        fines: List.of(fines),
        outstandingTotal: fines
            .where((f) => f.status == FineStatus.outstanding || f.status == FineStatus.adjusted)
            .fold(0.0, (total, f) => total + f.amount),
      );

  @override
  Future<void> dispute(String fineId, String reason) async {
    final at = fines.indexWhere((f) => f.id == fineId);
    if (at < 0) throw const ApiException(404, 'Fine not found');
    final fine = fines[at];
    if (fine.dispute != null) throw const ConflictException("You've already disputed this fine.");
    if (fine.status != FineStatus.outstanding && fine.status != FineStatus.adjusted) {
      throw const ConflictException("This fine can't be disputed because it is already paid or waived.");
    }
    disputes.add((fineId: fineId, reason: reason));
    fines = [
      for (final f in fines)
        if (f.id == fineId)
          Fine(
            id: f.id, reason: f.reason, item: f.item, amount: f.amount, originalAmount: f.originalAmount,
            status: f.status, date: f.date, note: f.note, dispute: const FineDispute(status: DisputeStatus.open),
          )
        else
          f,
    ];
  }
}

final fineRepositoryProvider = Provider<FineRepository>((ref) => HttpFineRepository(ref.watch(apiClientProvider)));
