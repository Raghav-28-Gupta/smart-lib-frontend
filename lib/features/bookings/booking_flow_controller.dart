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
    this.selectedZone,
    this.step = BookingFlowStep.pick,
    this.result,
    this.conflictAlternatives,
    this.alternativeWindow,
  });

  final ResourceType type;
  final int dateIndex;
  final Resource? selectedResource;
  final String? selectedSlot;

  /// The zone the Seats tab shows, as the student chose it. It is only a choice:
  /// the screen falls back to the first zone when this one no longer exists, so
  /// it survives a change of day or time without a check here.
  final String? selectedZone;
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
    String? selectedZone,
    bool clearSelection = false,
    bool clearResource = false,
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
        selectedResource: (clearSelection || clearResource) ? null : (selectedResource ?? this.selectedResource),
        selectedSlot: clearSelection ? null : (selectedSlot ?? this.selectedSlot),
        selectedZone: selectedZone ?? this.selectedZone,
        step: step ?? this.step,
        result: clearResult ? null : (result ?? this.result),
        conflictAlternatives: clearAlternatives ? null : (conflictAlternatives ?? this.conflictAlternatives),
        alternativeWindow: (clearAlternativeWindow || clearSelection || clearResource) ? null : (alternativeWindow ?? this.alternativeWindow),
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

  /// The Seats tab picks the time first. A desk chosen for another time may be
  /// taken at this one, so the desk goes; so does a conflict alternative's
  /// exact window, which belonged to that desk.
  void chooseTime(String slot) =>
      state = state.copyWith(selectedSlot: slot, clearResource: true, clearAlternativeWindow: true);

  /// Moving between zones keeps the time and the desk: a desk picked in one
  /// zone stays picked while the student looks at another.
  void chooseZone(String zone) => state = state.copyWith(selectedZone: zone);

  /// Back from the confirm step or the conflict screen. [clearDesk] is for
  /// "Choose a different slot myself": the map reopens at the same time with
  /// no desk, since the one that was refused is not the student's pick any more.
  void backToPicker({bool clearDesk = false}) => state = state.copyWith(
        step: BookingFlowStep.pick,
        clearResult: true,
        clearAlternatives: true,
        clearResource: clearDesk,
      );

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

// Only the type and the day decide what is loaded. Watching the whole flow
// reloaded the seats on every tap of a time, zone or desk, which put a spinner
// over the map and threw away its scroll position.
final bookingResourcesProvider = FutureProvider.autoDispose<List<Resource>>((ref) {
  final (type, dateIndex) = ref.watch(bookingFlowControllerProvider.select((s) => (s.type, s.dateIndex)));
  return ref.watch(bookingRepositoryProvider).resources(type, dateIndex);
});
