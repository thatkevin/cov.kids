require "open3"
require "rake"

class SitePublishJob < ApplicationJob
  queue_as :default

  def perform(commit_message: "Publish: weekly update #{Date.current.strftime('%-d %b %Y')}")
    root = Rails.root.to_s

    # Generate static site
    Rails.logger.info("SitePublishJob: generating site...")
    Rails.application.load_tasks
    Rake::Task["site:generate"].reenable
    Rake::Task["site:generate"].invoke

    # Stage docs/
    _, stage_err, stage_status = Open3.capture3("git", "-C", root, "add", "docs/")
    raise "git add failed: #{stage_err}" unless stage_status.success?

    # Check if anything changed
    diff_out, _, _ = Open3.capture3("git", "-C", root, "status", "--porcelain", "docs/")
    if diff_out.strip.empty?
      Rails.logger.info("SitePublishJob: no changes in docs/, skipping commit")
      return
    end

    # Commit
    _, commit_err, commit_status = Open3.capture3("git", "-C", root, "commit", "-m", commit_message)
    raise "git commit failed: #{commit_err}" unless commit_status.success?

    # Push
    _, push_err, push_status = Open3.capture3("git", "-C", root, "push", "origin", "main")
    raise "git push failed: #{push_err}" unless push_status.success?

    Rails.logger.info("SitePublishJob: pushed to GitHub successfully")
  end
end
