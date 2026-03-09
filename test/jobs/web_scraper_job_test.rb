require "test_helper"

class WebScraperJobTest < ActiveSupport::TestCase
  setup { @job = WebScraperJob.new }

  # ── strip_html ─────────────────────────────────────────────────────────────

  test "strip_html: removes script and style blocks" do
    html = "<p>Hello</p><script>alert('xss')</script><style>body{}</style><p>World</p>"
    result = @job.send(:strip_html, html)
    assert_includes result, "Hello"
    assert_includes result, "World"
    assert_not_includes result, "alert"
    assert_not_includes result, "body{}"
  end

  test "strip_html: preserves link URLs inline" do
    html = '<a href="https://example.com/event">Buy tickets</a>'
    result = @job.send(:strip_html, html)
    assert_includes result, "https://example.com/event"
    assert_includes result, "Buy tickets"
  end

  test "strip_html: resolves relative URLs against base" do
    html = '<a href="/events/my-show">Show</a>'
    result = @job.send(:strip_html, html, "https://www.theherbert.org/whats-on/")
    assert_includes result, "https://www.theherbert.org/events/my-show"
  end

  test "strip_html: leaves absolute URLs unchanged" do
    html = '<a href="https://other.com/page">Link</a>'
    result = @job.send(:strip_html, html, "https://www.example.com/")
    assert_includes result, "https://other.com/page"
  end

  test "strip_html: decodes HTML entities" do
    html = "<p>Fish &amp; Chips &nbsp; today</p>"
    result = @job.send(:strip_html, html)
    assert_includes result, "Fish & Chips"
  end

  # ── strip_fences ───────────────────────────────────────────────────────────

  test "strip_fences: removes ```json opening and closing fences" do
    raw = "```json\n[{\"name\":\"Test\"}]\n```"
    assert_equal '[{"name":"Test"}]', @job.send(:strip_fences, raw)
  end

  test "strip_fences: handles trailing whitespace after closing fence" do
    raw = "```json\n[]\n```  \n"
    assert_equal "[]", @job.send(:strip_fences, raw)
  end

  test "strip_fences: leaves plain JSON unchanged" do
    raw = '[{"name":"Test"}]'
    assert_equal raw, @job.send(:strip_fences, raw)
  end

  test "strip_fences: handles ``` without json tag" do
    raw = "```\n[]\n```"
    assert_equal "[]", @job.send(:strip_fences, raw)
  end
end
