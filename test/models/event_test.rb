require "test_helper"

class EventTest < ActiveSupport::TestCase
  # ── parse_start_date ───────────────────────────────────────────────────────

  test "parse_start_date: nil for blank input" do
    assert_nil Event.parse_start_date(nil)
    assert_nil Event.parse_start_date("")
    assert_nil Event.parse_start_date("   ")
  end

  test "parse_start_date: nil for recurring/vague patterns" do
    assert_nil Event.parse_start_date("Every Friday")
    assert_nil Event.parse_start_date("Weekly Fridays")
    assert_nil Event.parse_start_date("Monthly meetup")
    assert_nil Event.parse_start_date("Ongoing until July")
    assert_nil Event.parse_start_date("Various dates")
    assert_nil Event.parse_start_date("TBC")
    assert_nil Event.parse_start_date("  tbc  ")
  end

  test "parse_start_date: parses 'Fri 6th Mar'" do
    travel_to Date.new(2026, 1, 1) do
      result = Event.parse_start_date("Fri 6th Mar")
      assert_equal Date.new(2026, 3, 6), result
    end
  end

  test "parse_start_date: parses 'Sat, Apr 18, 12:15 PM'" do
    travel_to Date.new(2026, 1, 1) do
      result = Event.parse_start_date("Sat, Apr 18, 12:15 PM")
      assert_equal Date.new(2026, 4, 18), result
    end
  end

  test "parse_start_date: parses 'Thu, Mar 26, 8:00 PM'" do
    travel_to Date.new(2026, 1, 1) do
      result = Event.parse_start_date("Thu, Mar 26, 8:00 PM")
      assert_equal Date.new(2026, 3, 26), result
    end
  end

  test "parse_start_date: rolls over to next year when month has passed" do
    travel_to Date.new(2026, 6, 1) do
      result = Event.parse_start_date("Fri 6th Mar")
      assert_equal Date.new(2027, 3, 6), result
    end
  end

  test "parse_start_date: 'today' returns current date" do
    travel_to Date.new(2026, 3, 9) do
      assert_equal Date.new(2026, 3, 9), Event.parse_start_date("Today at 7pm")
    end
  end

  test "parse_start_date: tbc on date with known day/month still parses" do
    travel_to Date.new(2026, 1, 1) do
      result = Event.parse_start_date("SAT 4TH APRIL, tbc")
      assert_equal Date.new(2026, 4, 4), result
    end
  end

  # Regression: month-before-day pattern must not steal time digits.
  # "Sat 21st Mar 8pm" was mis-parsed as March 8th (from "Mar 8pm") when the
  # month-before-day pattern ran before the day-before-month pattern.
  test "parse_start_date: does not confuse time digits for the day (Sat 21st Mar 8pm)" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 3, 21), Event.parse_start_date("Sat 21st Mar 8pm")
    end
  end

  test "parse_start_date: does not confuse time digits for the day (Fri 20th Mar 7:45pm)" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 3, 20), Event.parse_start_date("Fri 20th Mar 7:45pm")
    end
  end

  test "parse_start_date: does not confuse time digits for the day (Sat 21st Mar 5pm)" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 3, 21), Event.parse_start_date("Sat 21st Mar 5pm & 7:45pm")
    end
  end

  test "parse_start_date: parses month-before-day with full month name and year" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 3, 18), Event.parse_start_date("Wednesday March 18th 2026, 7.30pm")
    end
  end

  test "parse_start_date: parses month-before-day without year, future month" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 4, 15), Event.parse_start_date("Wednesday April 15th, 7.30pm")
    end
  end

  test "parse_start_date: uses explicit year to avoid rolling past months into next year" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2026, 2, 28), Event.parse_start_date("28 February 2026, 3pm")
      assert_equal Date.new(2026, 2, 24), Event.parse_start_date("24 February 2026, 7pm")
    end
  end

  test "parse_start_date: rolls past month into next year when no explicit year" do
    travel_to Date.new(2026, 3, 15) do
      assert_equal Date.new(2027, 2, 1), Event.parse_start_date("1st Feb")
    end
  end

  # ── next_occurrence_date ───────────────────────────────────────────────────

  test "next_occurrence_date: returns start_date when set" do
    event = Event.new(start_date: Date.new(2026, 5, 1))
    assert_equal Date.new(2026, 5, 1), event.next_occurrence_date
  end

  test "next_occurrence_date: returns next Friday for 'Jazz Fridays'" do
    travel_to Date.new(2026, 3, 9) do  # Monday
      event = Event.new(name: "Jazz Fridays", date_text: "Every Friday")
      result = event.next_occurrence_date
      assert_equal 5, result.wday  # Friday
      assert result >= Date.new(2026, 3, 9)
    end
  end

  test "next_occurrence_date: nil when past until date" do
    travel_to Date.new(2026, 8, 1) do
      event = Event.new(name: "Jazz Fridays", date_text: "Fridays / Until 3rd Jul")
      assert_nil event.next_occurrence_date
    end
  end

  # ── similar_to scope ───────────────────────────────────────────────────────

  test "similar_to: finds exact match" do
    event = Event.create!(name: "Coventry Jazz Festival", status: :pending)
    assert_includes Event.similar_to("Coventry Jazz Festival"), event
  ensure
    event&.destroy
  end

  test "similar_to: finds near-duplicate" do
    event = Event.create!(name: "Coventry Jazz Festival 2026", status: :pending)
    results = Event.similar_to("Coventry Jazz Festival 2026")
    assert_includes results, event
  ensure
    event&.destroy
  end

  test "similar_to: does not match unrelated names" do
    event = Event.create!(name: "Coventry Jazz Festival", status: :pending)
    results = Event.similar_to("Birmingham Comedy Night")
    assert_not_includes results, event
  ensure
    event&.destroy
  end
end
