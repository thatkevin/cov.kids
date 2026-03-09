require "test_helper"

class SiteControllerTest < ActionDispatch::IntegrationTest
  # ── effective_date ─────────────────────────────────────────────────────────
  # After 7pm Sunday → treat as next Monday

  test "effective_date: Sunday before 7pm stays as Sunday" do
    # Sunday 8 Mar 2026, 6:59pm
    travel_to Time.zone.local(2026, 3, 8, 18, 59) do
      get root_path
      assert_response :success
      assert_select ".page-week", /8 March/
    end
  end

  test "effective_date: Sunday at 7pm shifts to Monday" do
    # Sunday 8 Mar 2026, 7:00pm → should show week of Mon 9 Mar
    travel_to Time.zone.local(2026, 3, 8, 19, 0) do
      get root_path
      assert_response :success
      assert_select ".page-week", /9 March/
    end
  end

  # ── homepage renders ───────────────────────────────────────────────────────

  test "homepage returns 200" do
    get root_path
    assert_response :success
  end

  test "featured event from next week does not appear on homepage" do
    future_event = Event.create!(
      name:       "Future Gig",
      status:     :approved,
      featured:   true,
      start_date: Date.current + 14,
      first_seen: Date.current.to_s,
      last_seen:  Date.current.to_s
    )

    travel_to Time.zone.local(2026, 3, 9, 12, 0) do
      get root_path
      assert_response :success
      assert_select ".featured-hero-label", text: "Event of the Week", count: 0
    end
  ensure
    future_event&.destroy
  end

  # ── about page ─────────────────────────────────────────────────────────────

  test "about page returns 200" do
    get about_path
    assert_response :success
  end
end
