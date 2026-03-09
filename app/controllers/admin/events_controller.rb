class Admin::EventsController < Admin::ApplicationController
  before_action :set_event, only: %i[edit update approve reject feature merge]

  # Source types ranked best → worst for determining the canonical event
  SOURCE_PRIORITY = %w[web facebook eventbrite ical email reddit].freeze

  def index
    @events         = Event.pending.includes(:source).order(Arel.sql("start_date ASC NULLS LAST, first_seen DESC, created_at DESC"))
    @featured_event = Event.approved.find_by(featured: true)
    @imageable      = Event.approved.where.not(image_url: [ nil, "" ]).where(featured: false)
                           .order(Arel.sql("start_date ASC NULLS LAST, name")).limit(20)
    @clusters       = find_duplicate_clusters
  end

  def edit
    @similar_events = Event.where.not(id: @event.id)
                           .where("similarity(name, ?) >= ?", @event.name, 0.4)
                           .includes(:source)
                           .order(Arel.sql("similarity(name, #{Event.connection.quote(@event.name)}) DESC"))
                           .limit(5)
    respond_to do |format|
      format.turbo_stream
      format.html
    end
  end

  def update
    if @event.update(curated_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path, notice: "Event updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def approve
    @event.update!(status: :approved, reviewed_at: Time.current, reviewed_by: current_user.email)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_events_path }
    end
  end

  def reject
    @event.update!(status: :rejected, reviewed_at: Time.current, reviewed_by: current_user.email)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_events_path }
    end
  end

  def feature
    Event.where.not(id: @event.id).update_all(featured: false)
    @event.update!(featured: !@event.featured)
    redirect_to admin_events_path
  end

  # POST /admin/events/:id/merge
  # @event is the canonical (survivor). params[:duplicate_event_ids] are absorbed then deleted.
  def merge
    dup_ids    = Array(params[:duplicate_event_ids]).map(&:to_i).reject { |id| id == @event.id }
    duplicates = Event.where(id: dup_ids)

    # Absorb any fields the canonical is missing
    duplicates.each do |dup|
      @event.event_url   = dup.event_url   if @event.event_url.blank?   && dup.event_url.present?
      @event.image_url   = dup.image_url   if @event.image_url.blank?   && dup.image_url.present?
      @event.description = dup.description if @event.description.blank? && dup.description.present?
      @event.date_text   = dup.date_text   if @event.date_text.blank?   && dup.date_text.present?
      @event.start_date  = dup.start_date  if @event.start_date.blank?  && dup.start_date.present?
    end
    @event.times_listed += duplicates.sum(:times_listed)
    @event.save!

    duplicates.destroy_all
    redirect_to admin_events_path, notice: "Merged #{dup_ids.size} duplicate(s) into '#{@event.effective_name}'."
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end

  def curated_params
    p = params.require(:event).permit(:curated_name, :curated_venue, :curated_date_text, :curated_event_url, :curated_category, :start_date)
    # Nil out curated values that are identical to the original — no actual override needed
    p[:curated_name]      = nil if p[:curated_name].to_s.strip      == @event.name.to_s.strip
    p[:curated_venue]     = nil if p[:curated_venue].to_s.strip     == @event.venue.to_s.strip
    p[:curated_date_text] = nil if p[:curated_date_text].to_s.strip == @event.date_text.to_s.strip
    p[:curated_event_url] = nil if p[:curated_event_url].to_s.strip == @event.event_url.to_s.strip
    p[:curated_category]  = nil if p[:curated_category].to_s.strip  == @event.category.to_s.strip
    p
  end

  # Find clusters of approved events with similar names.
  # Orders candidates by source quality so the web/facebook event is the canonical.
  def find_duplicate_clusters(threshold: 0.4)
    # Load approved events ordered by source priority (best first) then times_listed
    priority_sql = Arel.sql(
      "CASE sources.source_type " +
      SOURCE_PRIORITY.each_with_index.map { |t, i| "WHEN '#{t}' THEN #{i}" }.join(" ") +
      " ELSE #{SOURCE_PRIORITY.size} END"
    )

    candidates = Event.approved
                      .left_joins(:source)
                      .order(priority_sql, Arel.sql("events.times_listed DESC"))
                      .to_a

    seen     = Set.new
    clusters = []

    candidates.each do |event|
      next if seen.include?(event.id)
      seen.add(event.id)

      similar = Event.approved
                     .where.not(id: seen.to_a)
                     .where("similarity(name, ?) >= ?", event.name, threshold)
                     .then { |q|
                       # If the canonical has a start_date, only match events within 3 days
                       # (avoids false positives for recurring venue events on different dates)
                       if event.start_date
                         q.where("start_date IS NULL OR start_date BETWEEN ? AND ?",
                                 event.start_date - 3, event.start_date + 3)
                       else
                         q
                       end
                     }
                     .includes(:source)
                     .to_a

      next if similar.empty?

      similar.each { |e| seen.add(e.id) }
      clusters << { canonical: event, duplicates: similar }
    end

    clusters
  end
end
