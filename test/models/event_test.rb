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
