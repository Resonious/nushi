import 'package:fixnum/fixnum.dart';
import 'package:nushi/gen/nushi/v1/nushi.pb.dart';
import 'package:nushi/usage_range.dart';

import 'harness.dart';

// Made-up usage for Settings › Usage's tests and renders (ADR 0136): the
// demo's imaginary lumen projects, invented chats.

/// Turns summed: [usd] dollars (none when null), tokens in and out, the
/// cache's, and how many turns.
UsageTotals usageTotals({
  double? usd,
  int input = 0,
  int output = 0,
  int read = 0,
  int written = 0,
  int turns = 0,
}) => UsageTotals(
  cost: [if (usd != null) UsageCost(currency: 'USD', amount: usd)],
  inputTokens: Int64(input),
  outputTokens: Int64(output),
  cacheReadTokens: Int64(read),
  cacheWriteTokens: Int64(written),
  turns: Int64(turns),
);

/// [fixtureNow]'s day less [back] days, as the daemon keys it.
String usageDay(int back) =>
    dayKey(DateTime(fixtureNow.year, fixtureNow.month, fixtureNow.day - back));

/// A busy week: Claude, PiG and OpenCode report a cost, Codex and Ante
/// none; Claude's two limits, the 5-hour one near it.
GetUsageResponse busyUsage() => GetUsageResponse(
  totals: usageTotals(
    usd: 145.80,
    input: 4120000,
    output: 1630000,
    read: 18300000,
    written: 2100000,
    turns: 412,
  ),
  days: [
    for (final (back, usd, tok) in [
      (6, 18.20, 610000),
      (5, 5.10, 140000),
      (4, 1.20, 30000),
      (3, 29.40, 980000),
      (2, 42.10, 1420000),
      (1, 37.40, 1260000),
      (0, 12.40, 1310000),
    ])
      UsageGroup(
        key: usageDay(back),
        totals: usageTotals(
          usd: usd,
          input: tok * 3 ~/ 4,
          output: tok ~/ 4,
          turns: tok ~/ 14000,
        ),
      ),
  ],
  agents: [
    UsageGroup(
      key: 'ante',
      totals: usageTotals(input: 520000, output: 180000, turns: 31),
    ),
    UsageGroup(
      key: 'claude',
      totals: usageTotals(
        usd: 112.60,
        input: 2510000,
        output: 980000,
        read: 16900000,
        written: 1900000,
        turns: 228,
      ),
    ),
    UsageGroup(
      key: 'codex',
      totals: usageTotals(input: 610000, output: 240000, turns: 74),
    ),
    UsageGroup(
      key: 'opencode',
      totals: usageTotals(usd: 11.90, input: 180000, output: 90000, turns: 22),
    ),
    UsageGroup(
      key: 'pig',
      totals: usageTotals(usd: 21.30, input: 300000, output: 140000, turns: 57),
    ),
  ],
  models: [
    UsageGroup(
      key: '',
      totals: usageTotals(input: 90000, output: 30000, turns: 6),
    ),
    UsageGroup(
      key: 'big-model',
      totals: usageTotals(usd: 98.10, input: 1900000, output: 700000),
    ),
    UsageGroup(
      key: 'quick-model',
      totals: usageTotals(usd: 47.70, input: 1500000, output: 610000),
    ),
    UsageGroup(
      key: 'coder-large',
      totals: usageTotals(input: 630000, output: 290000),
    ),
  ],
  folders: [
    UsageGroup(
      key: '',
      totals: usageTotals(usd: 3.20, input: 60000, output: 20000),
    ),
    UsageGroup(
      key: '/Users/me/src/lumen',
      totals: usageTotals(usd: 101.40, input: 2900000, output: 1100000),
    ),
    UsageGroup(
      key: '/Users/me/src/lumen-docs',
      totals: usageTotals(usd: 41.20, input: 1160000, output: 510000),
    ),
  ],
  chats: [
    UsageChat(
      chatId: 'a',
      title: 'Fix the login redirect',
      agent: 'claude',
      totals: usageTotals(usd: 38.20, input: 820000, output: 310000),
    ),
    UsageChat(
      chatId: 'gone',
      agent: 'claude',
      totals: usageTotals(usd: 22.75, input: 540000, output: 160000),
    ),
    UsageChat(
      chatId: 'c',
      title: 'Release notes',
      agent: 'pig',
      totals: usageTotals(usd: 14.10, input: 210000, output: 90000),
    ),
    UsageChat(
      chatId: 'b',
      title: 'Bump the API version',
      agent: 'codex',
      totals: usageTotals(input: 610000, output: 240000),
    ),
  ],
  noCost: ['ante', 'codex'],
  earliest: msAgo(const Duration(days: 23)),
  limits: [
    UsageLimit(
      agent: 'claude',
      kind: 'five_hour',
      status: 'allowed_warning',
      utilization: 0.86,
      resetsAt: Int64(
        fixtureNow
            .add(const Duration(hours: 1, minutes: 5))
            .millisecondsSinceEpoch,
      ),
      seen: msAgo(const Duration(minutes: 12)),
    ),
    UsageLimit(
      agent: 'claude',
      kind: 'seven_day',
      status: 'allowed',
      utilization: 0.64,
      resetsAt: Int64(
        fixtureNow.add(const Duration(days: 4)).millisecondsSinceEpoch,
      ),
      seen: msAgo(const Duration(minutes: 12)),
    ),
  ],
);

/// The first day: nothing kept yet.
GetUsageResponse emptyUsage() => GetUsageResponse();

/// A week on Codex and Ante alone, which report no cost.
GetUsageResponse noCostUsage() => GetUsageResponse(
  totals: usageTotals(
    input: 8100000,
    output: 3300000,
    read: 41000000,
    turns: 268,
  ),
  days: [
    for (final (back, tok) in [
      (6, 1400000),
      (5, 200000),
      (3, 2600000),
      (2, 3300000),
      (1, 2900000),
      (0, 1000000),
    ])
      UsageGroup(
        key: usageDay(back),
        totals: usageTotals(
          input: tok * 7 ~/ 10,
          output: tok * 3 ~/ 10,
          turns: tok ~/ 40000,
        ),
      ),
  ],
  agents: [
    UsageGroup(
      key: 'ante',
      totals: usageTotals(input: 1600000, output: 700000, turns: 61),
    ),
    UsageGroup(
      key: 'codex',
      totals: usageTotals(input: 6500000, output: 2600000, turns: 207),
    ),
  ],
  models: [
    UsageGroup(
      key: 'coder-large',
      totals: usageTotals(input: 6500000, output: 2600000),
    ),
    UsageGroup(
      key: 'open-model',
      totals: usageTotals(input: 1600000, output: 700000),
    ),
  ],
  folders: [
    UsageGroup(
      key: '/Users/me/src/lumen',
      totals: usageTotals(input: 5300000, output: 2300000),
    ),
    UsageGroup(
      key: '/Users/me/src/lumen-docs',
      totals: usageTotals(input: 2800000, output: 1000000),
    ),
  ],
  chats: [
    UsageChat(
      chatId: 'b',
      title: 'Bump the API version',
      agent: 'codex',
      totals: usageTotals(input: 2100000, output: 900000),
    ),
    UsageChat(
      chatId: 'x',
      title: 'Translate the CLI messages',
      agent: 'ante',
      totals: usageTotals(input: 900000, output: 300000),
    ),
  ],
  noCost: ['ante', 'codex'],
  earliest: msAgo(const Duration(days: 9)),
);

/// [busyUsage] over 90 days: a day's spend rises and falls by the week,
/// weekends quiet, a few days without a turn.
GetUsageResponse quarterUsage() => busyUsage()
  ..days.clear()
  ..days.addAll([
    for (var back = 89; back >= 0; back--)
      if (back % 13 != 5)
        UsageGroup(
          key: usageDay(back),
          totals: usageTotals(
            usd: (back % 7 < 2 ? 2 : 14) + (back * 37 % 23).toDouble(),
            input: 400000 + back * 9000,
            output: 120000 + back * 3000,
            turns: 20 + back % 30,
          ),
        ),
  ]);
