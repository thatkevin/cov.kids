class FeedSyncJob < ApplicationJob
  queue_as :default

  def perform
    Feed.active.each do |feed|
      next unless feed.due?
      feed.set_status!(:queued)
      FeedRunnerJob.perform_later(feed.id)
    end
  end
end
