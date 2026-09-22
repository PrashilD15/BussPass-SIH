/// The BussPass component library — barrel file.
///
/// The implementations live in `src/`, grouped by kind. Screens import this
/// one file (or already do) and get everything: surfaces, chips, buttons,
/// states, layout rows, the progress bar, the bottom-sheet scaffold, the STC
/// identity badge, the data-honesty signal chips, and the live-bus marker.
///
/// The rule for all of it: a screen never reaches for a raw `Container` with a
/// hand-written `BoxDecoration`, and never hardcodes a colour. Each component
/// resolves colour through `context.palette`, so all of it works in dark mode
/// without a second implementation.
library;

export 'src/animation.dart';
export 'src/bus_marker.dart';
export 'src/buttons.dart';
export 'src/chips.dart';
export 'src/layout.dart';
export 'src/progress.dart';
export 'src/sheet.dart';
export 'src/signals.dart';
export 'src/states.dart';
export 'src/stc_badge.dart';
export 'src/surfaces.dart';
export 'src/typography.dart';
