# cov.kids — Dev Notes

## Date parsing (`Event.parse_start_date`)

Patterns are checked **in order** — be very careful about ordering if adding new ones.

### Known pitfall: month-before-day must come AFTER day-before-month

The "month before day" pattern (`March 18th`) must be checked **after** the "day before month"
pattern (`18th Mar`). If you reverse the order, the month-before-day regex will match the time
digits in strings like `"Sat 21st Mar 8pm"` — it finds `Mar` then grabs `8` (from `8pm`) as the
day, giving March 8th instead of March 21st.

This wiped out correct dates for ~40 events in March 2026 when the patterns were added in the
wrong order. The fix was ordering: day-before-month → month-before-day.

### Always capture the explicit year when present

Both day-before-month and month-before-day patterns accept an optional 4-digit year suffix.
Without it, a past month (e.g. February) rolls over to the next calendar year. Strings like
`"28 February 2026, 3pm"` must use the explicit `2026`, not infer year from today's date.

### After any changes to parse_start_date, run the full test suite

```
bin/rails test test/models/event_test.rb
```

And verify a sample of real events in the DB still parse correctly:

```ruby
bin/rails runner "
  samples = ['Sat 21st Mar 8pm', 'Fri 20th Mar 7:45pm', 'Wednesday March 18th 2026, 7.30pm', '28 February 2026, 3pm']
  samples.each { |s| puts \"#{s.ljust(45)} -> #{Event.parse_start_date(s)}\" }
"
```

Expected output (from March 2026):
```
Sat 21st Mar 8pm                              -> 2026-03-21
Fri 20th Mar 7:45pm                           -> 2026-03-20
Wednesday March 18th 2026, 7.30pm             -> 2026-03-18
28 February 2026, 3pm                         -> 2026-02-28
```

### After a bulk backfill, always re-check for drift

If you run a backfill script that re-parses `start_date` for many events, run it **twice** —
the second pass will catch any events whose dates were mis-set by the first pass (e.g. due to a
bug that was fixed mid-session). Check the output of the second pass is empty before publishing.
