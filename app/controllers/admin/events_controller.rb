class Admin::EventsController < Admin::ApplicationController
  before_action :set_event, only: %i[edit update approve reject]

  def index
    @events = Event.pending.includes(:source).order(Arel.sql("start_date ASC NULLS LAST, first_seen DESC, created_at DESC"))
  end

  def edit
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

  private

  def set_event
    @event = Event.find(params[:id])
  end

  def curated_params
    p = params.require(:event).permit(:curated_name, :curated_venue, :curated_date_text, :curated_event_url, :curated_category)
    # Nil out curated values that are identical to the original — no actual override needed
    p[:curated_name]      = nil if p[:curated_name].to_s.strip      == @event.name.to_s.strip
    p[:curated_venue]     = nil if p[:curated_venue].to_s.strip     == @event.venue.to_s.strip
    p[:curated_date_text] = nil if p[:curated_date_text].to_s.strip == @event.date_text.to_s.strip
    p[:curated_event_url] = nil if p[:curated_event_url].to_s.strip == @event.event_url.to_s.strip
    p[:curated_category]  = nil if p[:curated_category].to_s.strip  == @event.category.to_s.strip
    p
  end
end
