// lib/features/bookings/booking_flow_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/booking_alternative.dart';
import '../../models/resource_booking.dart';
import 'booking_repository.dart';
import 'bookings_controller.dart';
import 'time_slots.dart';

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
    this.alternativeWindow,
  });

  final ResourceType type;
  final int dateIndex;
  final Resource? selectedResource;
  final String? selectedSlot;
  final BookingFlowStep step;
  final ResourceBooking? result;
  final List<BookingAlternative>? conflictAlternatives;

  /// Set when the selection came from a conflict alternative: the server's
  /// exact window, booked as-is rather than rebuilt from the slot label.
  /// Cleared whenever the user picks a slot themselves.
  final ({DateTime start, DateTime end})? alternativeWindow;

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
    ({DateTime start, DateTime end})? alternativeWindow,
    bool clearAlternativeWindow = false,
  }) =>
      BookingFlowState(
        type: type,
        dateIndex: dateIndex ?? this.dateIndex,
        selectedResource: clearSelection ? null : (selectedResource ?? this.selectedResource),
        selectedSlot: clearSelection ? null : (selectedSlot ?? this.selectedSlot),
        step: step ?? this.step,
        result: clearResult ? null : (result ?? this.result),
        conflictAlternatives: clearAlternatives ? null : (conflictAlternatives ?? this.conflictAlternatives),
        alternativeWindow: (clearAlternativeWindow || clearSelection) ? null : (alternativeWindow ?? this.alternativeWindow),
      );
}

class BookingFlowController extends Notifier<BookingFlowState> {
  // A second confirm would come back as a conflict with the first and replace
  // the success screen with "that slot was just taken".
  bool _confirming = false;

  @override
  BookingFlowState build() => const BookingFlowState();

  void setType(ResourceType t) => state = BookingFlowState(type: t, dateIndex: state.dateIndex);
  void setDateIndex(int i) => state = state.copyWith(dateIndex: i, clearSelection: true);
  void pickSlot(Resource r, String slot) =>
      state = state.copyWith(selectedResource: r, selectedSlot: slot, clearAlternativeWindow: true);
  void goToConfirm() => state = state.copyWith(step: BookingFlowStep.confirm);
  void backToPicker() => state = state.copyWith(step: BookingFlowStep.pick, clearResult: true, clearAlternatives: true);

  Future<void> confirm() async {
    final resource = state.selectedResource;
    final slot = state.selectedSlot;
    if (resource == null || slot == null) return;
    final window = state.alternativeWindow ?? slotWindow(state.dateIndex, slot);
    if (_confirming) return;
    _confirming = true;
    try {
      final booking = await ref.read(bookingRepositoryProvider).createBooking(resource: resource, start: window.start, end: window.end);
      ref.read(bookingsControllerProvider.notifier).prependBooking(booking);
      state = state.copyWith(result: booking, clearAlternatives: true);
    } on BookingConflictException catch (e) {
      state = state.copyWith(conflictAlternatives: e.alternatives, clearResult: true);
    } finally {
      // Any other refusal propagates for the screen to report.
      _confirming = false;
    }
  }

  void pickAlternative(BookingAlternative a) => state = state.copyWith(
        selectedResource: a.toResource(),
        selectedSlot: a.timeSlot,
        alternativeWindow: (start: a.startTime, end: a.endTime),
        clearAlternatives: true,
        clearResult: true,
      );

  void reset() => state = const BookingFlowState();
}

final bookingFlowControllerProvider = NotifierProvider<BookingFlowController, BookingFlowState>(BookingFlowController.new);

final bookingResourcesProvider = FutureProvider.autoDispose<List<Resource>>((ref) {
  final flow = ref.watch(bookingFlowControllerProvider);
  return ref.watch(bookingRepositoryProvider).resources(flow.type, flow.dateIndex);
});
