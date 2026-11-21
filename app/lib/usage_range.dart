import 'package:fixnum/fixnum.dart';

import 'package:nushi/clock.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

/// The spans of days Settings › Usage shows (ADR 0136), each ending
/// today: a week, a month, a quarter, or everything kept.
enum UsageRange {
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90),
  all('All', 0);

  new(this.label, this.days);

  /// Its segment's label.
  final String label;

  /// How many days it holds, today the last; 0 for every day kept.
  final int days;

  /// The day it starts on, at midnight on the Mac's clock, as [now] has
  /// it; null for [all].
  DateTime? from(DateTime now) =>
      days == 0 ? null : DateTime(now.year, now.month, now.day - (days - 1));

  /// What GetUsage is asked for it: from its first day's midnight, open
  /// at the end (nothing has ended after now), days counted in the
  /// daemon's zone, which is the Mac's own (the call is the Mac's only).
  GetUsageRequest request(DateTime now) =>
      GetUsageRequest(from: Int64(from(now)?.millisecondsSinceEpoch ?? 0));
}

/// [d]'s day as the daemon keys a day's usage: "2026-10-29".
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// The days from [first] to [last], each once, at midnight: what a chart
/// of days lays out, the days without a turn too.
List<DateTime> daysBetween(DateTime first, DateTime last) => [
  for (
    var d = DateTime(first.year, first.month, first.day);
    !d.isAfter(last);
    d = DateTime(d.year, d.month, d.day + 1)
  )
    d,
];
