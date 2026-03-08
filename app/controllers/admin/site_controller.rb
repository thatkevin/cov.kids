class Admin::SiteController < Admin::ApplicationController
  def publish
    SitePublishJob.perform_later
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("publish-log-lines", html: "")
      end
      format.html { redirect_to admin_root_path, notice: "Publish started." }
    end
  end
end
