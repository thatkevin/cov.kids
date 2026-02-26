class FeedRunnerJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find(feed_id)
    feed.set_status!(:running)

    case feed.feed_type
    when "web"
      WebScraperJob.new.perform(feed_id)
    when "ical"
      IcalImportJob.new.perform(feed.url, source_type: "ical", source_name: feed.name)
    when "eventbrite"
      EventbriteImportJob.new.perform
    end

    feed.mark_fetched!
    feed.set_status!(:done)
  rescue => e
    Rails.logger.error("FeedRunnerJob [#{feed_id}]: #{e.message}")
    feed&.set_status!(:error, error: e.message)
  end
end
