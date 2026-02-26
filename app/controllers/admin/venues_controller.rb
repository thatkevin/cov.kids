class Admin::VenuesController < Admin::ApplicationController
  before_action :set_venue, only: %i[edit update destroy merge merge_into]

  def index
    @venues = Venue.left_joins(:events)
                   .select("venues.*, COUNT(events.id) AS events_count")
                   .group("venues.id")
                   .order(Arel.sql("COUNT(events.id) DESC"))
                   .to_a

    # Find clusters of similar venues (similarity > 0.7) for the "possible duplicates" panel
    @clusters = find_clusters
  end

  def new
    @venue = Venue.new(zone: "coventry")
  end

  def create
    @venue = Venue.new(venue_params)
    if @venue.save
      redirect_to admin_venues_path, notice: "Venue added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @venue.update(venue_params)
      redirect_to admin_venues_path, notice: "#{@venue.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @venue.destroy
    redirect_to admin_venues_path, notice: "Venue removed."
  end

  # Merge THIS venue into another (target) venue — used from the edit page.
  def merge_into
    target = Venue.find(params[:target_venue_id])
    count  = Event.where(venue_id: @venue.id).update_all(venue_id: target.id)
    @venue.destroy
    redirect_to admin_venues_path, notice: "Merged '#{@venue.name}' into '#{target.name}' — #{count} event(s) moved."
  end

  # Merge source venues into this venue — all their events are reassigned here.
  def merge
    source_ids = Array(params[:source_venue_ids]).map(&:to_i).reject { |id| id == @venue.id }
    count = Event.where(venue_id: source_ids).update_all(venue_id: @venue.id)
    Venue.where(id: source_ids).destroy_all
    redirect_to admin_venues_path, notice: "Merged #{source_ids.size} venue(s) — #{count} events moved to #{@venue.name}."
  end

  private

  def set_venue
    @venue = Venue.find(params[:id])
  end

  def venue_params
    params.require(:venue).permit(:name, :address, :zone)
  end

  # Greedy clustering: find groups of venues where names are similar.
  # Returns array of arrays; each inner array is [canonical_venue, *similar_venues].
  def find_clusters(threshold: 0.5)
    all = Venue.left_joins(:events)
               .select("venues.*, COUNT(events.id) AS events_count")
               .group("venues.id")
               .order(Arel.sql("COUNT(events.id) DESC"))
               .to_a

    seen = Set.new
    clusters = []

    all.each do |venue|
      next if seen.include?(venue.id)
      seen.add(venue.id)

      similar = Venue.where("id != ? AND similarity(name, ?) >= ?", venue.id, venue.name, threshold)
                     .where.not(id: seen.to_a)
      next if similar.empty?

      similar.each { |s| seen.add(s.id) }
      clusters << { canonical: venue, similar: similar.to_a }
    end

    clusters
  end
end
