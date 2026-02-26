class Admin::FeedsController < Admin::ApplicationController
  before_action :set_feed, only: %i[edit update destroy trigger]

  def index
    @feeds = Feed.order(:feed_type, :name)
  end

  def new
    @feed = Feed.new(feed_type: "web", active: true, fetch_interval_hours: 24)
  end

  def create
    @feed = Feed.new(feed_params)
    if @feed.save
      redirect_to admin_feeds_path, notice: "Feed added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @feed.update(feed_params)
      redirect_to admin_feeds_path, notice: "Feed updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed.destroy
    redirect_to admin_feeds_path, notice: "Feed removed."
  end

  def trigger
    @feed.set_status!(:queued)
    FeedRunnerJob.perform_later(@feed.id)
    redirect_to admin_feeds_path, notice: "#{@feed.name} queued."
  end

  private

  def set_feed
    @feed = Feed.find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(:name, :url, :feed_type, :active, :fetch_interval_hours)
  end
end
