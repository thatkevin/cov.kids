class SiteController < ApplicationController
  layout "site"

  before_action :set_archive_years
  before_action :set_zone

  def index
    week_start = Date.current.beginning_of_week(:monday)
    week_end   = Date.current.end_of_week(:monday)

    dated   = zoned_events.where(start_date: week_start..week_end)
    undated = zoned_events.where(start_date: nil).where(last_seen: week_start.to_s..week_end.to_s)
    events  = dated.or(undated).order(Arel.sql("start_date NULLS LAST"), :category, :name)

    # Fallback: show next 4 weeks of upcoming events if nothing is on this week
    if events.empty?
      events = zoned_events.where(start_date: Date.current..(Date.current + 28)).order(:start_date, :category, :name)
    end

    @events_by_category = group_by_category(events)
    @week_label = "#{week_start.strftime('%-d %B')} – #{week_end.strftime('%-d %B %Y')}"
    @nav_active = :home
  end

  def weeks_index
    dates_by_week = Event.approved
                         .where.not(first_seen: nil)
                         .pluck(:first_seen)
                         .filter_map { |d| Date.parse(d) rescue nil }
                         .group_by { |d| d.strftime("%Y-W%02d") % [ d.year, d.cweek ] }

    @weeks = dates_by_week.map do |week_id, dates|
      year_num, week_num = week_id.split("-W").map(&:to_i)
      week_start = Date.commercial(year_num, week_num, 1)
      week_end   = Date.commercial(year_num, week_num, 7)
      count = Event.approved.where(first_seen: week_start.to_s..week_end.to_s).count
      { id: week_id, label: "#{week_start.strftime('%-d %b')} – #{week_end.strftime('%-d %b %Y')}", event_count: count }
    end.sort_by { |w| w[:id] }.reverse

    @nav_active = :weeks
  end

  def week
    @week_id = params[:week_id]
    year_num, week_num = @week_id.split("-W").map(&:to_i)
    week_start = Date.commercial(year_num, week_num, 1)
    week_end   = Date.commercial(year_num, week_num, 7)

    @week_number = week_num
    @date_range  = "#{week_start.strftime('%-d %b')} – #{week_end.strftime('%-d %b %Y')}"

    events = zoned_events.where(first_seen: week_start.to_s..week_end.to_s).order(:category, :name)
    @events_by_category = group_by_category(events)
  end

  def year
    @year = params[:year].to_i
    events = Event.approved.where("first_seen LIKE ?", "#{@year}-%")
    @total_events = events.count

    @months = events.pluck(:first_seen)
                    .filter_map { |d| Date.parse(d) rescue nil }
                    .map(&:month).uniq.sort
                    .map do |month_num|
                      d = Date.new(@year, month_num, 1)
                      count = events.where("first_seen LIKE ?", "#{@year}-#{d.strftime('%m')}-%").count
                      { path: d.strftime("%m"), label: d.strftime("%B"), event_count: count }
                    end

    @nav_active = @year.to_s
  end

  def month
    @year       = params[:year].to_i
    @month_path = params[:month]
    month_date  = Date.new(@year, @month_path.to_i, 1)
    @month_name = month_date.strftime("%B")

    events = zoned_events.where("first_seen LIKE ?", "#{@year}-#{@month_path}-%").order(:category, :name)
    @total_events = events.count
    @events_by_category = group_by_category(events)

    @days = events.pluck(:first_seen)
                  .filter_map { |d| Date.parse(d) rescue nil }
                  .map(&:day).uniq.sort
                  .map do |day_num|
                    d = Date.new(@year, @month_path.to_i, day_num)
                    count = events.where(first_seen: d.to_s).count
                    { path: d.strftime("%d"), label: d.strftime("%-d %B"), event_count: count }
                  end
  end

  def about
    @page_title = "About"
    @nav_active = :about
  end

  def day
    @year       = params[:year].to_i
    @month_path = params[:month]
    @day        = params[:day].to_i
    date        = Date.new(@year, @month_path.to_i, @day)
    @month_name = date.strftime("%B")
    @day_label  = date.strftime("%-d %B %Y")

    @events = zoned_events.where(first_seen: date.to_s).order(:category, :name).map { |e| event_to_hash(e) }
  end

  private

  def set_zone
    @zones = ["coventry"]
    @zones << "warwickshire" if params[:warwickshire] == "1"
    @zones << "birmingham"   if params[:birmingham]   == "1"
  end

  def zoned_events
    Event.approved.where(zone: @zones)
  end

  def set_archive_years
    @archive_years = Event.approved
                          .where.not(first_seen: nil)
                          .pluck(:first_seen)
                          .filter_map { |d| d.split("-").first.to_i rescue nil }
                          .uniq.sort.reverse
  end

  def group_by_category(events)
    grouped = events.group_by { |e| e.effective_category.presence || "other" }
                    .transform_values do |evs|
                      evs.sort_by { |e| [date_sort_key(e), e.effective_name.to_s.downcase] }
                         .map { |e| event_to_hash(e) }
                    end
    Event::CATEGORIES.filter_map { |cat| [cat, grouped[cat]] if grouped.key?(cat) }.to_h
  end

  # Returns a sortable value for an event's date.
  # start_date (Date) sorts first; parseable date_text sorts next; vague/undated sorts last.
  MONTH_ABBREVS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

  def date_sort_key(event)
    return event.start_date if event.start_date

    text = event.effective_date_text.to_s
    return Date.new(9999) if text.blank? || text.match?(/\buntil\b|\bongoing\b|\bvarious\b|\btbc\b/i)

    if text =~ /(\d{1,2})(?:st|nd|rd|th)?\s+(#{MONTH_ABBREVS.join('|')})/i
      day   = $1.to_i
      month = MONTH_ABBREVS.index($2.capitalize) + 1
      year  = Date.current.year
      Date.new(year, month, day) rescue Date.new(9999)
    else
      Date.new(9999)
    end
  end

  def event_to_hash(event)
    { id:           event.id,
      name:         event.effective_name,
      url:          event.effective_event_url,
      times_listed: event.times_listed,
      date_text:    event.effective_date_text,
      venue:        event.effective_venue,
      category:     event.effective_category }
  end
end
