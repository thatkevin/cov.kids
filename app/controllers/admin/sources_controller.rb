class Admin::SourcesController < Admin::ApplicationController
  before_action :set_source, only: %i[edit update destroy reprocess archive unarchive]

  GROUP_JOB_TYPES = %w[email facebook reddit].freeze

  def index
    show_archived = params[:show_archived] == "1"
    @show_archived = show_archived
    @sources = Source.where(archived: show_archived).order(published_at: :desc).limit(200)
    @grouped = @sources.group_by(&:source_type)
    @archived_count = Source.where(archived: true).count unless show_archived

    @import_statuses = ImportStatus::KEYS.index_with { |key| ImportStatus.for(key) }

    @recent_by_source = Event
      .where.not(source_id: nil)
      .order(created_at: :desc)
      .select(:id, :name, :status, :source_id, :created_at)
      .each_with_object(Hash.new { |h, k| h[k] = [] }) do |ev, h|
        h[ev.source_id] << ev if h[ev.source_id].size < 5
      end
  end

  def new
    @source = Source.new(source_type: "web", published_at: Time.current)
  end

  def create
    @source = Source.new(source_params)
    if @source.save
      redirect_to admin_sources_path, notice: "Source added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @source.update(source_params)
      redirect_to admin_sources_path, notice: "Source updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy
    redirect_to admin_sources_path, notice: "Source removed."
  end

  # Group-level trigger for email/facebook/reddit
  def run_by_type
    type = params[:type].to_s
    case type
    when "email", "facebook"
      ImportStatus.set!(:email, :queued)
      EmailImportJob.perform_later
      redirect_to admin_sources_path, notice: "Email import queued."
    when "reddit"
      ImportStatus.set!(:reddit, :queued)
      RedditImportJob.perform_later
      redirect_to admin_sources_path, notice: "Reddit import queued."
    else
      redirect_to admin_sources_path, alert: "Cannot run type: #{type}."
    end
  end

  # Per-source trigger for ical/web (feed-backed)
  def reprocess
    case @source.source_type
    when "ical"
      feed = Feed.find_by(url: @source.url)
      if feed
        feed.set_status!(:queued)
        FeedRunnerJob.perform_later(feed.id)
        redirect_to admin_sources_path, notice: "Re-processing #{@source.title}."
      else
        IcalImportJob.perform_later(@source.url, source_type: "ical", source_name: @source.title)
        redirect_to admin_sources_path, notice: "iCal import queued for #{@source.title}."
      end
    when "web", "eventbrite"
      feed = Feed.find_by(url: @source.url)
      if feed
        feed.set_status!(:queued)
        FeedRunnerJob.perform_later(feed.id)
        redirect_to admin_sources_path, notice: "Re-processing #{@source.title}."
      else
        redirect_to admin_sources_path, alert: "No feed configured for this source. Add it under Feeds."
      end
    else
      redirect_to admin_sources_path, alert: "Use the group Run button for #{@source.source_type} sources."
    end
  end

  def archive
    @source.update!(archived: true)
    redirect_to admin_sources_path, notice: "Archived."
  end

  def unarchive
    @source.update!(archived: false)
    redirect_to admin_sources_path(show_archived: "1"), notice: "Unarchived."
  end

  private

  def set_source
    @source = Source.find(params[:id])
  end

  def source_params
    params.require(:source).permit(:title, :url, :source_type, :body, :published_at)
  end
end
