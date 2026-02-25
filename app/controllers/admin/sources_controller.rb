class Admin::SourcesController < Admin::ApplicationController
  before_action :set_source, only: %i[edit update destroy]

  def index
    @sources = Source.order(published_at: :desc).limit(200)
    @grouped = @sources.group_by(&:source_type)
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

  private

  def set_source
    @source = Source.find(params[:id])
  end

  def source_params
    params.require(:source).permit(:title, :url, :source_type, :body, :published_at)
  end
end
