// lib/widgets/note_field.dart
import 'package:flutter/material.dart';
import '../core/theme/smartlib_tokens.dart';

/// The longest note or reason the server takes: `z.string().trim().max(300)` on a fine
/// dispute's reason, a copy report's note (sent with the return) and a seat or room
/// report's note. One constant for all three.
const kMaxNoteLength = 300;

/// What a [NoteField] says under itself once its text is over [kMaxNoteLength].
const kNoteTooLongMessage = 'At most $kMaxNoteLength characters';

/// The length of [text] as the server counts it: after trimming, in UTF-16 code units,
/// which is what Dart's `String.length` is (and what JavaScript's is, in the server's zod
/// check). Flutter's own `TextField.maxLength` counts grapheme clusters instead, so a
/// reason of 151 emoji (302 units) or a long Hindi or Punjabi one (a vowel sign, a virama
/// or a conjunct adds units to one visible letter) would pass it and be refused by the
/// server with a bare "Invalid request body". The limit is enforced on this count.
int noteLength(String text) => text.trim().length;

/// Whether [text] is more than the server takes. Not a reason to cut what the student
/// typed: the field says so and the dialog's button stays off until they shorten it.
bool noteTooLong(String text) => noteLength(text) > kMaxNoteLength;

/// A multi-line field for a note or a reason, shared by the three dialogs that take one
/// (the fine dispute, the Return dialog's report and the seat or room report), so that
/// they count, warn and look the same.
///
/// - **Counts like the server**: the counter reads `n/300` of the trimmed text in UTF-16
///   code units ([noteLength]); there is no `maxLength`, and nothing the student typed is
///   cut. Over the limit the counter turns the error colour and the field shows
///   [kNoteTooLongMessage] as its `errorText`, so a screen reader and a colour-blind
///   student hear why the dialog's button is off. The dialog disables its button with
///   [noteTooLong]; this widget does not know about it.
/// - **A rounded rectangle, not the theme's pill**: the theme gives every field a 999 px
///   radius, made for single-line fields. On a multi-line one the radius scales to half
///   the field's height (about 88 px on a 176 px field), and the floating label's gap
///   then removes the top edge of the outline. The border here is the theme's own, with
///   the radius of the app's medium shapes; single-line fields keep the pill.
///
/// The counter redraws itself as the controller changes. The dialog still rebuilds on
/// [onChanged] to recompute whether its button is on.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.autofocus = false,
    this.minLines = 2,
    this.maxLines = 4,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool autofocus;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  /// The radius when the theme carries no [SmartLibTokens] (a test's bare `MaterialApp`);
  /// the same as the tokens' `radiusMd`.
  static const _fallbackRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = theme.extension<SmartLibTokens>()?.radiusMd ?? _fallbackRadius;
    // The theme sets only `border`, which also stands for the enabled, focused and error
    // borders, so this one reshapes them all and keeps the theme's outline colour.
    final themed = theme.inputDecorationTheme.border;
    final border = (themed is OutlineInputBorder ? themed : const OutlineInputBorder())
        .copyWith(borderRadius: BorderRadius.circular(radius));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final length = noteLength(controller.text);
        final tooLong = length > kMaxNoteLength;
        return TextField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            border: border,
            counterText: '$length/$kMaxNoteLength',
            counterStyle: tooLong ? TextStyle(color: theme.colorScheme.error) : null,
            errorText: tooLong ? kNoteTooLongMessage : null,
          ),
          onChanged: onChanged,
        );
      },
    );
  }
}
