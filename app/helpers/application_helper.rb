module ApplicationHelper
  # Route external image URLs through the local proxy to avoid hotlink blocking.
  # Pass through data URIs or relative paths unchanged.
  def proxied_image_url(url)
    return url if url.blank?
    return url unless url.start_with?("http://", "https://")
    image_proxy_path(url: url)
  end
end
