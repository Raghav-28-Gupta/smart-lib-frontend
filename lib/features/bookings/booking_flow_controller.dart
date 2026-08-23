// lib/features/bookings/booking_flow_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/resource_booking.dart';
import 'booking_repository.dart';
import 'bookings_controller.dart';

enum BookingFlowStep { pick, confirm }

class BookingFlowState {
  const BookingFlowState({
    this.type = ResourceType.seat,
    this.dateIndex = 0,
    this.selectedResource,
    this.selectedSlot,
    this.step = BookingFlowStep.pick,
    this.result,
    this.conflictAlternatives,
  });

  final ResourceType type;
  final int dateIndex;
  final Resource? selectedResource;
  final String? selectedSlot;
  final BookingFlowStep step;
  final ResourceBooking? result;
  final List<BookingAlternative>? conflictAlternatives;

  BookingFlowState copyWith({
    int? dateIndex,
    Resource? selectedResource,
    String? selectedSlot,
    bool clearSelection = false,
    BookingFlowStep? step,
    ResourceBooking? result,
    bool clearResult = false,
    List<BookingAlternative>? conflictAlternatives,
    bool clearAlternatives = false,
  }) =>
      BookingFlowState(
        type: type,
        dateIndex: dateIndex ?? this.dateIndex,
        selectedResource: clearSelection ? null : (selectedResource ?? this.selectedResource),
        selectedSlot: clearSelection ? null : (selectedSlot ?? this.selectedSlot),
        step: step ?? this.step,
        result: clearResult ? null : (result ?? this.result),
        conflictAlternatives: clearAlternatives ? null : (conflictAlternatives ?? this.conflictAlternatives),
      );
}

class BookingFlowController extends Notifier<BookingFlowState> {
  @override
  BookingFlowState build() => const BookingFlowState();

  void setType(ResourceType t) => state = BookingFlowState(type: t, dateIndex: state.dateIndex);
  void setDateIndex(int i) => state = state.copyWith(dateIndex: i, clearSelection: true);
  void pickSlot(Resource r, String slot) => state = state.copyWith(selectedResource: r, selectedSlot: slot);
  void goToConfirm() => state = state.copyWith(step: BookingFlowStep.confirm);
  void backToPicker() => state = state.copyWith(step: BookingFlowStep.pick, clearResult: true, clearAlternatives: true);

  Future<void> confirm() async {
    final resource = state.selectedResource;
    final slot = state.selectedSlot;
    if (resource == null || slot == null) return;
    try {
      final booking = await ref.read(bookingRepositoryProvider).createBooking(resource: resource, dateIndex: state.dateIndex, timeSlot: slot);
      ref.read(bookingsControllerProvider.notifier).prependBooking(booking);
      state = state.copyWith(result: booking, clearAlternatives: true);
    } on BookingConflictException catch (e) {
      state = state.copyWith(conflictAlternatives: e.alternatives, clearResult: true);
    }
  }

  void pickAlternative(BookingAlternative a) =>
      state = state.copyWith(selectedResource: a.resource, selectedSlot: a.timeSlot, clearAlternatives: true, clearResult: true);

  void reset() => state = const BookingFlowState();
}

final bookingFlowControllerProvider = NotifierProvider<BookingFlowController, BookingFlowState>(BookingFlowController.new);

final bookingResourcesProvider = FutureProvider.autoDispose<List<Resource>>((ref) {
  final flow = ref.watch(bookingFlowControllerProvider);
  return ref.watch(bookingRepositoryProvider).resources(flow.type, flow.dateIndex);
});
