class Admin::SiteController < Admin::ApplicationController
  def publish
    SitePublishJob.perform_later
    redirect_to root_path, notice: "Site publish queued — it'll go live in a moment."
  end
end
