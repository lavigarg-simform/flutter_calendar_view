// Tests for the TimeSlotTheme declarative API.
//
// Each test drives DayView with a fixed [currentTimeProvider] so rule
// evaluation is deterministic regardless of when the suite is run.

import 'package:calendar_view/calendar_view.dart';
import 'package:calendar_view/src/painters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns the [TimeSlotBackgroundPainter] rendered for [DayView], or null if
/// no background painter is present.
TimeSlotBackgroundPainter? _findSlotPainter(WidgetTester tester) {
  final painted = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is TimeSlotBackgroundPainter,
  );
  if (painted.evaluate().isEmpty) return null;
  final cp = tester.widget<CustomPaint>(painted.first);
  return cp.painter as TimeSlotBackgroundPainter;
}

/// Builds a minimal DayView in an 800×600 Scaffold.
///
/// - startHour: 9, endHour: 11, minuteSlotSize: 30 min → 4 slots
/// - The [date] parameter is the page date shown.
/// - Pass [timeSlotTheme] or [timeSlotColorBuilder] to exercise the APIs.
Widget _buildView({
  required DateTime date,
  TimeSlotTheme? timeSlotTheme,
  TimeSlotColorBuilder? timeSlotColorBuilder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: DayView(
          controller: EventController(),
          initialDay: date,
          minDay: date,
          maxDay: date,
          startHour: 9,
          endHour: 11,
          minuteSlotSize: MinuteSlotSize.minutes30,
          heightPerMinute: 1,
          timeLineWidth: 60,
          verticalLineOffset: 0,
          timeSlotTheme: timeSlotTheme,
          timeSlotColorBuilder: timeSlotColorBuilder,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Monday 30 March 2026 — used as the canonical "today" reference date.
  // currentTimeProvider returns 10:15 so the first two 30-min slots are past.
  final kDate = DateTime(2026, 3, 30); // Monday
  final kNow = DateTime(2026, 3, 30, 10, 15); // 10:15 AM on that day

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — background painter presence', () {
    testWidgets(
      'background painter is rendered when only timeSlotTheme is set',
      (tester) async {
        await tester.pumpWidget(
          _buildView(
            date: kDate,
            timeSlotTheme: TimeSlotTheme(
              defaultSlotColor: Colors.blue.shade50,
              currentTimeProvider: () => kNow,
            ),
          ),
        );

        expect(_findSlotPainter(tester), isNotNull);
      },
    );

    testWidgets(
      'no background painter when neither callback nor theme is provided',
      (tester) async {
        await tester.pumpWidget(_buildView(date: kDate));

        expect(_findSlotPainter(tester), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — past slot rule', () {
    testWidgets(
      'pastSlotColor applied to slots ending before currentTime on today',
      (tester) async {
        // kNow = 10:15  →  slots  9:00-9:30 and 9:30-10:00 are past.
        const pastColor = Color(0xFFFF0000);

        await tester.pumpWidget(
          _buildView(
            date: kDate,
            timeSlotTheme: TimeSlotTheme(
              pastSlotColor: pastColor,
              currentTimeProvider: () => kNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        // Slot 0: 9:00-9:30 — ends before 10:15 → past
        expect(painter.slotColors[0], pastColor);
        // Slot 1: 9:30-10:00 — ends before 10:15 → past
        expect(painter.slotColors[1], pastColor);
        // Slot 2: 10:00-10:30 — ends after 10:15 → not past
        expect(painter.slotColors[2], isNot(pastColor));
        // Slot 3: 10:30-11:00 — ends after 10:15 → not past
        expect(painter.slotColors[3], isNot(pastColor));
      },
    );

    testWidgets(
      'pastSlotColor applied to entire past day when '
      'applyPastRuleToEntirePastDay is true',
      (tester) async {
        // View is one day before kNow's date → all slots are on a past day.
        final pastDay = DateTime(2026, 3, 29); // Sunday (also past day)
        const pastColor = Color(0xFFFF0000);

        await tester.pumpWidget(
          _buildView(
            date: pastDay,
            timeSlotTheme: TimeSlotTheme(
              pastSlotColor: pastColor,
              applyPastRuleToEntirePastDay: true,
              currentTimeProvider: () => kNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, pastColor);
        }
      },
    );

    testWidgets(
      'past-day slots fall through to weekend rule when '
      'applyPastRuleToEntirePastDay is false',
      (tester) async {
        // pastDay is Sunday the 29th; applyPastRuleToEntirePastDay=false means
        // past-day slots are NOT coloured by pastSlotColor unless they are
        // individually past-on-today.  Weekend rule should apply instead.
        final pastSunday = DateTime(2026, 3, 29);
        const pastColor = Color(0xFFFF0000);
        const weekendColor = Color(0xFF00FF00);

        await tester.pumpWidget(
          _buildView(
            date: pastSunday,
            timeSlotTheme: TimeSlotTheme(
              pastSlotColor: pastColor,
              weekendSlotColor: weekendColor,
              applyPastRuleToEntirePastDay: false,
              currentTimeProvider: () => kNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        // All slots on pastSunday are not individually past-on-today
        // (they're on a different day), so weekend rule fires.
        for (final color in painter.slotColors) {
          expect(color, weekendColor);
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — weekend rule', () {
    testWidgets(
      'weekendSlotColor applied on Saturday',
      (tester) async {
        final saturday = DateTime(2026, 3, 28); // Saturday
        const weekendColor = Color(0xFFABCDEF);

        await tester.pumpWidget(
          _buildView(
            date: saturday,
            timeSlotTheme: TimeSlotTheme(
              weekendSlotColor: weekendColor,
              // Use a future "now" so past rule does not interfere.
              currentTimeProvider: () => DateTime(2026, 3, 27),
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, weekendColor);
        }
      },
    );

    testWidgets(
      'weekendSlotColor not applied on a weekday',
      (tester) async {
        final monday = DateTime(2026, 3, 30); // Monday
        const weekendColor = Color(0xFFABCDEF);

        await tester.pumpWidget(
          _buildView(
            date: monday,
            timeSlotTheme: TimeSlotTheme(
              weekendSlotColor: weekendColor,
              // now is far in the future so no past slots
              currentTimeProvider: () => DateTime(2026, 3, 28),
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, isNot(weekendColor));
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — business / off-hours rules', () {
    // startHour:9, endHour:11, slots: 9:00, 9:30, 10:00, 10:30
    // businessStartHour:9, businessEndHour:10 → slots 0&1 in business,
    //                                            slots 2&3 off-hours.
    // Use a future "now" and a weekday so no other rules interfere.
    final kFutureNow = DateTime(2026, 3, 28); // Before kDate
    final kMonday = DateTime(2026, 3, 30);

    testWidgets(
      'businessHoursColor applied for slots inside business window',
      (tester) async {
        const bizColor = Color(0xFF111111);

        await tester.pumpWidget(
          _buildView(
            date: kMonday,
            timeSlotTheme: TimeSlotTheme(
              businessHoursColor: bizColor,
              businessStartHour: 9,
              businessEndHour: 10,
              currentTimeProvider: () => kFutureNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        // Slot 0: starts 09:00 → in [9,10) → business color
        expect(painter.slotColors[0], bizColor);
        // Slot 1: starts 09:30 → in [9,10) → business color
        expect(painter.slotColors[1], bizColor);
        // Slot 2: starts 10:00 → not in [9,10) → not business color
        expect(painter.slotColors[2], isNot(bizColor));
        // Slot 3: starts 10:30 → not in [9,10) → not business color
        expect(painter.slotColors[3], isNot(bizColor));
      },
    );

    testWidgets(
      'offHoursColor applied for slots outside business window',
      (tester) async {
        const offColor = Color(0xFF222222);

        await tester.pumpWidget(
          _buildView(
            date: kMonday,
            timeSlotTheme: TimeSlotTheme(
              offHoursColor: offColor,
              businessStartHour: 9,
              businessEndHour: 10,
              currentTimeProvider: () => kFutureNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        // Slots 0&1 (start at 9:00 and 9:30) are IN business hours → no offColor
        expect(painter.slotColors[0], isNot(offColor));
        expect(painter.slotColors[1], isNot(offColor));
        // Slots 2&3 (start at 10:00 and 10:30) are outside [9,10) → offColor
        expect(painter.slotColors[2], offColor);
        expect(painter.slotColors[3], offColor);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — defaultSlotColor fallback', () {
    testWidgets(
      'defaultSlotColor used when no other rule matches',
      (tester) async {
        const defaultColor = Color(0xFF333333);

        // No past rule: now is before the date; no weekend; no biz/off hours
        // colors provided → falls through to defaultSlotColor.
        await tester.pumpWidget(
          _buildView(
            date: DateTime(2026, 3, 30), // Monday
            timeSlotTheme: TimeSlotTheme(
              defaultSlotColor: defaultColor,
              currentTimeProvider: () => DateTime(2026, 3, 28),
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, defaultColor);
        }
      },
    );

    testWidgets(
      'transparent returned when no rule matches and defaultSlotColor is null',
      (tester) async {
        // Theme with no colors set at all — all slots transparent.
        await tester.pumpWidget(
          _buildView(
            date: DateTime(2026, 3, 30),
            timeSlotTheme: TimeSlotTheme(
              currentTimeProvider: () => DateTime(2026, 3, 28),
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, Colors.transparent);
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — callback vs theme precedence', () {
    testWidgets(
      'timeSlotColorBuilder wins unconditionally over timeSlotTheme',
      (tester) async {
        const themeColor = Color(0xFFFF0000); // theme would produce red
        const callbackColor = Color(0xFF0000FF); // callback returns blue

        await tester.pumpWidget(
          _buildView(
            date: kDate,
            timeSlotTheme: TimeSlotTheme(
              defaultSlotColor: themeColor,
              currentTimeProvider: () => kNow,
            ),
            timeSlotColorBuilder: (_, __, ___, ____) => callbackColor,
          ),
        );

        final painter = _findSlotPainter(tester)!;
        for (final color in painter.slotColors) {
          expect(color, callbackColor);
          expect(color, isNot(themeColor));
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — custom currentTimeProvider', () {
    testWidgets(
      'custom currentTimeProvider determines past-slot boundary',
      (tester) async {
        const pastColor = Color(0xFFFF0000);

        // Override "now" to 9:45 → slot 9:00-9:30 is past, slot 9:30-10:00 is
        // NOT past (ends at 10:00 which is after 9:45).
        final customNow = DateTime(2026, 3, 30, 9, 45);

        await tester.pumpWidget(
          _buildView(
            date: kDate,
            timeSlotTheme: TimeSlotTheme(
              pastSlotColor: pastColor,
              currentTimeProvider: () => customNow,
            ),
          ),
        );

        final painter = _findSlotPainter(tester)!;
        // Only slot 0 (9:00-9:30, end 9:30 < 9:45) is past
        expect(painter.slotColors[0], pastColor);
        // Slot 1 ends at 10:00 which is after 9:45 → not past
        expect(painter.slotColors[1], isNot(pastColor));
      },
    );
  });

  // -------------------------------------------------------------------------
  group('TimeSlotTheme — assert validation', () {
    test('throws when businessStartHour >= businessEndHour', () {
      expect(
        () => TimeSlotTheme(businessStartHour: 10, businessEndHour: 10),
        throwsAssertionError,
      );
    });

    test('throws when businessStartHour is negative', () {
      expect(
        () => TimeSlotTheme(businessStartHour: -1),
        throwsAssertionError,
      );
    });

    test('throws when businessEndHour exceeds 24', () {
      expect(
        () => TimeSlotTheme(businessEndHour: 25),
        throwsAssertionError,
      );
    });
  });
}
