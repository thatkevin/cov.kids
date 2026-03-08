require "open3"
require "rake"
require "cgi"

class SitePublishJob < ApplicationJob
  queue_as :default

  STREAM = "site_publish_log"

  def perform(commit_message: "Publish: weekly update #{Date.current.strftime('%-d %b %Y')}")
    root = Rails.root.to_s

    log "Generating static site..."
    Rails.application.load_tasks
    Rake::Task["site:generate"].reenable
    Rake::Task["site:generate"].invoke
    log "Site generated."

    log "Staging docs/..."
    Open3.capture3("git", "-C", root, "rm", "-r", "--cached", "--ignore-unmatch", "docs/")
    _, stage_err, stage_status = Open3.capture3("git", "-C", root, "add", "docs/")
    raise "git add failed: #{stage_err}" unless stage_status.success?

    log "Checking for changes..."
    diff_out, _, _ = Open3.capture3("git", "-C", root, "status", "--porcelain", "docs/")
    if diff_out.strip.empty?
      log "No new changes to commit.", :muted
    else
      changed = diff_out.strip.lines.count
      log "#{changed} file(s) changed — committing..."
      _, commit_err, commit_status = Open3.capture3("git", "-C", root, "commit", "-m", commit_message)
      raise "git commit failed: #{commit_err}" unless commit_status.success?
    end

    log "Checking if push is needed..."
    ahead_out, _, _ = Open3.capture3("git", "-C", root, "rev-list", "--count", "pages/main..HEAD")
    if ahead_out.strip == "0"
      log "Already up to date with GitHub.", :muted
      log "Done.", :success
      return
    end

    log "Pushing to GitHub..."
    _, push_err, push_status = Open3.capture3("git", "-C", root, "push", "--force-with-lease", "pages", "main")
    raise "git push failed: #{push_err}" unless push_status.success?

    log "Done — site is live.", :success
  rescue => e
    log "Failed: #{e.message}", :error
    raise
  end

  private

  STYLES = {
    default: "text-gray-700",
    muted:   "text-gray-400 italic",
    success: "text-green-600 font-medium",
    error:   "text-red-600 font-medium",
  }.freeze

  def log(message, style = :default)
    css = STYLES.fetch(style, STYLES[:default])
    html = "<div class='font-mono text-xs py-0.5 #{css}'>#{CGI.escapeHTML(message)}</div>"
    Turbo::StreamsChannel.broadcast_append_to(STREAM, target: "publish-log-lines", html: html)
  end
end
