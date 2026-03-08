require "erb"
require "fileutils"
require "date"

namespace :site do
  desc "Generate static HTML site into docs/ for GitHub Pages"
  task generate: :environment do
    include SiteGenerator
    generate_site
  end
end

module SiteGenerator
  DOCS_DIR = Rails.root.join("docs")
  VIEWS_DIR = Rails.root.join("app", "views", "site")
  ASSETS_DIR = Rails.root.join("app", "assets", "site")

  MONTH_NAMES = %w[January February March April May June July August September October November December].freeze
  MONTH_ABBREVS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
  DAY_NAMES = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze
  DAY_ABBREVS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze

  ORDINAL_PATTERN = /(\d{1,2})(?:st|nd|rd|th)/

  def generate_site
    puts "Generating static site..."

    # Clean and prepare
    FileUtils.rm_rf(DOCS_DIR)
    FileUtils.mkdir_p(DOCS_DIR)

    # Copy assets
    copy_assets

    # Write CNAME
    File.write(DOCS_DIR.join("CNAME"), "cov.kids")

    # Load data
    sources = Source.order(published_at: :desc).to_a
    events = Event.approved.order(:category, :name).to_a

    # Build week data from sources
    weeks = build_weeks(sources, events)

    # Build date-indexed events for archives
    dated_events = build_dated_events(events, sources)

    # Archive years for nav
    archive_years = dated_events.keys.map(&:year).uniq.sort.reverse

    # --- Generate pages ---

    # Homepage: this week's events
    current_week = find_current_week(weeks)
    generate_homepage(current_week, archive_years)

    # Individual week pages
    weeks.each { |w| generate_week_page(w, archive_years) }

    # Weeks index
    generate_weeks_index(weeks, archive_years)

    # Year, month, day archives
    generate_date_archives(dated_events, archive_years)

    # About page
    html = render_template("about.html.erb", root_path: "./")
    write_page("about/index.html", html,
      page_title:    "About",
      archive_years: archive_years,
      root_path:     "../"
    )

    puts "Done! Site generated in docs/"
    puts "  #{Dir[DOCS_DIR.join('**', '*.html')].count} HTML files"
  end

  private

  # --- Asset Copying ---

  def copy_assets
    %w[style.css site.js].each do |file|
      FileUtils.cp(ASSETS_DIR.join(file), DOCS_DIR.join(file))
    end

    images_dest = DOCS_DIR.join("images")
    FileUtils.mkdir_p(images_dest)
    Dir[ASSETS_DIR.join("images", "*")].each do |img|
      FileUtils.cp(img, images_dest.join(File.basename(img)))
    end

    puts "  Copied assets"
  end

  # --- Date Parsing ---

  def parse_date_range(date_range)
    return nil if date_range.blank?

    # Format: "Monday 10th - Sunday 16th February"
    # or: "Monday 10th February - Sunday 16th February"
    # or: "Monday 10th - Sunday 16th February 2025"
    text = date_range.strip

    # Extract year if present, otherwise guess from context
    year = nil
    if text =~ /(\d{4})/
      year = $1.to_i
    end

    # Find month
    month_idx = nil
    MONTH_NAMES.each_with_index do |m, i|
      if text.include?(m)
        month_idx = i + 1
        break
      end
    end

    return nil unless month_idx

    # Find the Monday (first) date
    if text =~ /Monday\s+#{ORDINAL_PATTERN.source}/
      day = $1.to_i
      # Try to build a date — guess year if not present
      if year.nil?
        # Try recent years
        [2026, 2025, 2024, 2023].each do |y|
          d = Date.new(y, month_idx, day) rescue nil
          if d && d.monday?
            year = y
            break
          end
        end
      end
      return nil unless year
      Date.new(year, month_idx, day) rescue nil
    else
      # Fallback: try to get any date from the range
      if text =~ ORDINAL_PATTERN
        day = $1.to_i
        year ||= guess_year(month_idx, day)
        Date.new(year, month_idx, day) rescue nil
      end
    end
  end

  def parse_event_date(date_text, context_year)
    return nil if date_text.blank?

    text = date_text.strip

    # Skip vague ones
    return nil if text =~ /\buntil\b/i
    return nil if text =~ /\bongoing\b/i
    return nil if text =~ /\bvarious\b/i
    return nil if text =~ /\btbc\b/i
    return nil if text == "-"

    # Try patterns like "Sat 15th Feb", "Saturday 15th February", "15th Feb 2025"
    day = nil
    month_idx = nil
    year = nil

    if text =~ ORDINAL_PATTERN
      day = $1.to_i
    elsif text =~ /\b(\d{1,2})\b/
      day = $1.to_i
    end

    (MONTH_NAMES + MONTH_ABBREVS).each_with_index do |m, i|
      if text =~ /\b#{Regexp.escape(m)}\b/i
        month_idx = (i % 12) + 1
        break
      end
    end

    if text =~ /(\d{4})/
      year = $1.to_i
    end

    return nil unless day && month_idx

    year ||= context_year
    Date.new(year, month_idx, day) rescue nil
  end

  def year_from_date_range(date_range_str)
    return nil if date_range_str.blank?
    parsed = parse_date_range(date_range_str)
    parsed&.year
  end

  # --- Week Building ---

  def build_weeks(sources, events)
    weeks = []

    sources.each do |source|
      monday = parse_date_range(source.date_range)
      next unless monday

      iso_year, iso_week = monday.cwyear, monday.cweek
      week_id = format("%04d-w%02d", iso_year, iso_week)
      sunday = monday + 6

      # Parse events from this source's body
      week_events = parse_source_events(source)

      weeks << {
        id: week_id,
        week_number: source.week_number,
        date_range: source.date_range,
        monday: monday,
        sunday: sunday,
        label: "#{monday.strftime('%-d %b')} – #{sunday.strftime('%-d %b %Y')}",
        source: source,
        events: week_events
      }
    end

    # Deduplicate by week_id (keep the one with more events)
    weeks
      .group_by { |w| w[:id] }
      .map { |_id, group| group.max_by { |w| w[:events].length } }
      .sort_by { |w| w[:monday] }
      .reverse
  end

  def parse_source_events(source)
    return [] if source.body.blank?

    events = []
    current_category = "Uncategorised"

    source.body.each_line do |line|
      line = line.strip

      if line.match?(/^#\s+/)
        current_category = line
          .sub(/^#+\s*/, "")
          .gsub(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}]\uFE0F?/, "")
          .strip
        next
      end

      next unless line.start_with?("|")
      next if line.match?(/^\|[\s:-]+\|/)
      next if line.match?(/^\|\s*Event\s*\|/i)

      cols = line.split("|").map(&:strip).reject(&:empty?)
      next if cols.length < 3

      event_cell = cols[0]
      name = nil
      url = nil

      if (match = event_cell.match(/\[(.+?)\]\((.+?)\)/))
        name = match[1].strip
        url = match[2].strip
      else
        name = event_cell.gsub(/[\[\]]/, "").strip
      end

      next if name.blank?

      # Look up the deduplicated Event record for times_listed
      db_event = Event.find_by(name: name)
      times = db_event&.times_listed || 1

      events << {
        name: name,
        date_text: cols[1]&.strip || "",
        venue: cols[2]&.strip || "",
        category: current_category,
        url: url,
        times_listed: times
      }
    end

    events
  end

  def find_current_week(weeks)
    today = effective_date
    # Find the week containing today, or the most recent past week
    current = weeks.find { |w| w[:monday] <= today && w[:sunday] >= today }
    current || weeks.first
  end

  # After 7pm on Sunday, treat it as the start of next week
  def effective_date
    now = Time.now
    now.sunday? && now.hour >= 19 ? Date.today + 1 : Date.today
  end

  # --- Date Archives ---

  def build_dated_events(events, sources)
    dated = {}

    events.each do |event|
      # Use start_date if we have it, otherwise try to parse from date_text
      date = event.start_date
      unless date
        context_year = event.first_seen&.split("-")&.first&.to_i || Date.today.year
        date = parse_event_date(event.effective_date_text, context_year)
      end
      next unless date

      dated[date] ||= []
      dated[date] << {
        name:         event.effective_name,
        date_text:    event.effective_date_text,
        venue:        event.effective_venue,
        category:     event.effective_category,
        url:          event.effective_event_url,
        times_listed: event.times_listed,
        description:  event.description,
        image_url:    event.image_url
      }
    end

    dated
  end

  # --- Page Generation ---

  ZONE_VARIANTS = [
    { zones: %w[coventry],                         path: "index.html",              root_path: "./"  },
    { zones: %w[coventry warwickshire],            path: "warwickshire/index.html", root_path: "../" },
    { zones: %w[coventry birmingham],              path: "birmingham/index.html",   root_path: "../" },
    { zones: %w[coventry warwickshire birmingham], path: "all/index.html",          root_path: "../" },
  ].freeze

  def generate_homepage(week, archive_years)
    return unless week

    featured_event = Event.approved.find_by(featured: true)

    ZONE_VARIANTS.each do |variant|
      events         = fetch_homepage_events(variant[:zones])
      events_by_cat  = group_by_category_from_model(events)

      html = render_template("index.html.erb",
        week_label:         week[:label],
        events_by_category: events_by_cat,
        featured_event:     featured_event,
        root_path:          variant[:root_path]
      )

      write_page(variant[:path], html,
        page_title:    nil,
        nav_active:    :home,
        archive_years: archive_years,
        root_path:     variant[:root_path],
        week_label:    week[:label],
        active_zones:  variant[:zones]
      )
    end

    puts "  Generated homepage (#{week[:id]}) [4 zone variants]"
  end

  def fetch_homepage_events(zones)
    today      = effective_date
    week_start = today.beginning_of_week(:monday)
    week_end   = today.end_of_week(:monday)
    undated_from = Date.today.beginning_of_week(:monday)
    base       = Event.approved.where(zone: zones)

    dated   = base.where(start_date: week_start..week_end)
    undated = base.where(start_date: nil).where(last_seen: undated_from.to_s..week_end.to_s)
    events  = dated.or(undated).order(Arel.sql("start_date NULLS LAST"), :category, :name)

    events = base.where(start_date: today..(today + 28)).order(:start_date, :category, :name) if events.empty?
    events.to_a
  end

  def group_by_category_from_model(events)
    grouped = events.group_by { |e| e.effective_category.presence || "other" }
                    .transform_values { |evs| evs.map { |e| event_to_hash_from_model(e) } }
    Event::CATEGORIES.filter_map { |cat| [cat, grouped[cat]] if grouped.key?(cat) }.to_h
  end

  def event_to_hash_from_model(event)
    next_occ   = event.start_date.nil? ? event.next_occurrence_date : nil
    date_label = next_occ ? next_occ.strftime("%a %-d %b") : event.effective_date_text
    {
      id:           event.id,
      name:         event.effective_name,
      url:          event.effective_event_url,
      times_listed: event.times_listed,
      date_text:    date_label,
      venue:        event.effective_venue,
      category:     event.effective_category.presence || "other",
      description:  event.description,
      image_url:    event.image_url,
      featured:     event.featured?
    }
  end

  def generate_week_page(week, archive_years)
    events_by_category = group_by_category(week[:events])

    html = render_template("week.html.erb",
      week_id: week[:id],
      week_number: week[:week_number] || week[:id],
      date_range: week[:date_range] || week[:label],
      events_by_category: events_by_category,
      root_path: "../../"
    )

    path = File.join("weeks", week[:id], "index.html")
    write_page(path, html,
      page_title: "Week of #{week[:label]}",
      nav_active: :weeks,
      archive_years: archive_years,
      root_path: "../../"
    )
  end

  def generate_weeks_index(weeks, archive_years)
    week_summaries = weeks.map do |w|
      {
        id: w[:id],
        label: w[:label],
        event_count: w[:events].length
      }
    end

    html = render_template("weeks_index.html.erb",
      weeks: week_summaries,
      root_path: "../"
    )

    write_page(File.join("weeks", "index.html"), html,
      page_title: "All Weeks",
      nav_active: :weeks,
      archive_years: archive_years,
      root_path: "../"
    )

    puts "  Generated weeks index (#{weeks.length} weeks)"
  end

  def generate_date_archives(dated_events, archive_years)
    return if dated_events.empty?

    # Group by year
    by_year = dated_events.group_by { |date, _| date.year }

    by_year.each do |year, date_entries|
      all_year_events = date_entries.flat_map(&:last)

      # Group by month
      by_month = date_entries.group_by { |date, _| date.month }

      months = by_month.map do |month_num, month_entries|
        {
          path: format("%02d", month_num),
          label: MONTH_NAMES[month_num - 1],
          event_count: month_entries.flat_map(&:last).length
        }
      end.sort_by { |m| m[:path] }

      # Year page
      html = render_template("year.html.erb",
        year: year,
        months: months,
        total_events: all_year_events.length,
        root_path: "../"
      )

      write_page(File.join(year.to_s, "index.html"), html,
        page_title: year.to_s,
        nav_active: year.to_s,
        archive_years: archive_years,
        root_path: "../"
      )

      # Month pages
      by_month.each do |month_num, month_entries|
        month_events = month_entries.flat_map(&:last)
        month_path = format("%02d", month_num)

        # Group by day
        by_day = month_entries.group_by { |date, _| date.day }
        days = by_day.map do |day_num, day_entries|
          {
            path: format("%02d", day_num),
            label: "#{day_num} #{MONTH_NAMES[month_num - 1]}",
            event_count: day_entries.flat_map(&:last).length
          }
        end.sort_by { |d| d[:path] }

        html = render_template("month.html.erb",
          year: year,
          month_name: MONTH_NAMES[month_num - 1],
          month_path: month_path,
          days: days,
          events_by_category: group_by_category(month_events),
          total_events: month_events.length,
          root_path: "../../"
        )

        write_page(File.join(year.to_s, month_path, "index.html"), html,
          page_title: "#{MONTH_NAMES[month_num - 1]} #{year}",
          nav_active: year.to_s,
          archive_years: archive_years,
          root_path: "../../"
        )

        # Day pages
        by_day.each do |day_num, day_entries|
          day_events = day_entries.flat_map(&:last)
          day_path = format("%02d", day_num)
          date = Date.new(year, month_num, day_num)

          html = render_template("day.html.erb",
            year: year,
            month_name: MONTH_NAMES[month_num - 1],
            month_path: month_path,
            day: day_num,
            day_label: date.strftime("%A %-d %B %Y"),
            events: day_events,
            root_path: "../../../"
          )

          write_page(File.join(year.to_s, month_path, day_path, "index.html"), html,
            page_title: date.strftime("%-d %B %Y"),
            nav_active: year.to_s,
            archive_years: archive_years,
            root_path: "../../../"
          )
        end
      end
    end

    year_count = by_year.keys.length
    puts "  Generated date archives (#{year_count} years)"
  end

  # --- Helpers ---

  def group_by_category(events)
    grouped = {}
    events.each do |e|
      cat = e[:category] || "Uncategorised"
      grouped[cat] ||= []
      grouped[cat] << e
    end
    grouped.sort_by { |cat, _| cat }.to_h
  end

  def render_template(template_name, locals = {})
    template_path = VIEWS_DIR.join(template_name)
    template = ERB.new(File.read(template_path), trim_mode: "-")
    b = binding
    locals.each do |key, val|
      b.local_variable_set(key, val)
      instance_variable_set(:"@#{key}", val)
    end
    template.result(b)
  end

  def write_page(relative_path, content, layout_vars = {})
    layout_vars[:content] = content
    layout_vars[:page_title] ||= nil
    layout_vars[:page_description] ||= nil
    layout_vars[:nav_active] ||= nil
    layout_vars[:archive_years] ||= []
    layout_vars[:root_path] ||= "./"

    layout_template = ERB.new(File.read(VIEWS_DIR.join("_layout.html.erb")), trim_mode: "-")
    b = binding
    layout_vars.each do |key, val|
      b.local_variable_set(key, val)
      instance_variable_set(:"@#{key}", val)
    end
    full_html = layout_template.result(b)

    dest = DOCS_DIR.join(relative_path)
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, full_html)
  end
end
