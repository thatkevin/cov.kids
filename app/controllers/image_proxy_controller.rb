require "net/http"
require "digest"

class ImageProxyController < ApplicationController
  # Cache proxied images in tmp/image_cache/ to avoid re-fetching on every request
  CACHE_DIR = Rails.root.join("tmp/image_cache")
  MAX_SIZE  = 5 * 1024 * 1024 # 5 MB
  TTL       = 7.days

  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp image/svg+xml].freeze

  skip_before_action :verify_authenticity_token

  def show
    url = params[:url].to_s
    return head(:bad_request) if url.blank?
    return head(:bad_request) unless url.start_with?("http://", "https://")

    cache_path = cache_path_for(url)

    unless cache_fresh?(cache_path)
      data, content_type = fetch_image(url)
      return head(:bad_gateway) unless data
      FileUtils.mkdir_p(CACHE_DIR)
      File.binwrite(cache_path, data)
      File.write("#{cache_path}.type", content_type)
    end

    content_type = File.exist?("#{cache_path}.type") ? File.read("#{cache_path}.type") : "image/jpeg"
    send_file cache_path, type: content_type, disposition: "inline"
  rescue => e
    Rails.logger.error("ImageProxy: #{e.message}")
    head(:bad_gateway)
  end

  private

  def cache_path_for(url)
    CACHE_DIR.join(Digest::SHA256.hexdigest(url))
  end

  def cache_fresh?(path)
    File.exist?(path) && File.mtime(path) > TTL.ago
  end

  def fetch_image(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "User-Agent" => "Mozilla/5.0 (compatible; CoventryEvents/1.0)",
               "Referer" => uri.scheme + "://" + uri.host)
    end

    return nil unless response.is_a?(Net::HTTPSuccess)

    content_type = response["Content-Type"].to_s.split(";").first.strip
    return nil unless ALLOWED_CONTENT_TYPES.include?(content_type)
    return nil if response.body.bytesize > MAX_SIZE

    [response.body, content_type]
  rescue => e
    Rails.logger.error("ImageProxy: fetch failed for #{url}: #{e.message}")
    nil
  end
end
