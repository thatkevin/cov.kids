require "net/http"
require "json"
require "csv"
require "uri"
require "set"

namespace :reddit do
  desc "Fetch all event listings from u/HadjiChippoSafri on Reddit"
  task fetch_listings: :environment do
    username = "HadjiChippoSafri"
    base_url = "https://www.reddit.com/user/#{username}/submitted.json"
    user_agent = "CoventryEvents/1.0 (Ruby/Rails)"
    rate_limit = 2

    puts "Fetching event listings from u/#{username}..."

    all_sources = []
    after = nil
    page = 0

    loop do
      page += 1
      print "  Page #{page}..."

      uri = URI(base_url)
      params = { "limit" => "100", "sort" => "new" }
      params["after"] = after if after
      uri.query = URI.encode_www_form(params)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = user_agent

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        warn " HTTP #{response.code}: #{response.message}"
        break
      end

      data = JSON.parse(response.body)
      children = data.dig("data", "children") || []
      break if children.empty?

      events = children.select { |post| post.dig("data", "title").match?(/EVENTS:\s*What'?s On in Coventry/i) }

      events.each do |post|
        d = post["data"]
        title = d["title"]
        week_match = title.match(/#(\d+)/)
        date_match = title.match(/\((.+?)\)/)

        source = Source.find_or_initialize_by(url: "https://www.reddit.com#{d['permalink']}")
        source.assign_attributes(
          week_number: week_match ? week_match[1].to_i : nil,
          title: title,
          date_range: date_match ? date_match[1].strip : nil,
          published_at: Time.at(d["created_utc"].to_f).utc,
          body: d["selftext"],
          source_type: "reddit"
        )
        source.save!
        all_sources << source
      end

      print " found #{events.length} listings (#{all_sources.length} total)\n"

      after = data.dig("data", "after")
      break unless after

      sleep rate_limit
    end

    puts "\nDone! #{all_sources.length} listings saved to database."
    puts "Total sources in DB: #{Source.count}"
  end

  desc "Import listings from the old-listings CSV into the database"
  task import_csv: :environment do
    csv_path = Rails.root.join("old-listings", "listings.csv")
    abort "CSV not found at #{csv_path}" unless File.exist?(csv_path)

    puts "Importing listings from CSV..."
    rows = CSV.read(csv_path, headers: true)
    imported = 0

    rows.each do |row|
      source = Source.find_or_initialize_by(url: row["url"])
      source.assign_attributes(
        week_number: row["week_number"].to_i.nonzero?,
        title: row["title"],
        date_range: row["date_range"],
        published_at: row["created_utc"] ? Time.parse(row["created_utc"]) : nil,
        body: row["selftext"],
        source_type: "csv"
      )
      source.save!
      imported += 1
    end

    puts "Done! Imported #{imported} sources. Total in DB: #{Source.count}"
  end

  desc "Extract and deduplicate events from sources using Bayesian TF-IDF similarity"
  task extract_events: :environment do
    puts "Step 1: Parsing events from sources..."

    all_events = []

    Source.find_each do |source|
      next if source.body.blank?

      current_category = "Uncategorised"

      source.body.each_line do |line|
        line = line.strip

        # Detect category headers
        if line.match?(/^#\s+/)
          current_category = line
            .sub(/^#+\s*/, "")
            .gsub(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}]\uFE0F?/, "")
            .strip
          next
        end

        # Parse table rows
        next unless line.start_with?("|")
        next if line.match?(/^\|[\s:-]+\|/)
        next if line.match?(/^\|\s*Event\s*\|/i)

        cols = line.split("|").map(&:strip).reject(&:empty?)
        next if cols.length < 3

        event_cell = cols[0]
        event_name = nil
        event_url = nil

        if (match = event_cell.match(/\[(.+?)\]\((.+?)\)/))
          event_name = match[1].strip
          event_url = match[2].strip
        else
          event_name = event_cell.gsub(/[\[\]]/, "").strip
        end

        next if event_name.blank?

        all_events << {
          name: event_name,
          date: cols[1]&.strip || "",
          venue: cols[2]&.strip || "",
          category: current_category,
          event_url: event_url,
          listing_date_range: source.date_range || source.title
        }
      end
    end

    puts "  Extracted #{all_events.length} event entries from #{Source.count} sources"

    # --- TF-IDF deduplication ---
    puts "\nStep 2: Building TF-IDF model..."

    tokenise = ->(text) {
      text.downcase.gsub(/[^a-z0-9\s]/, " ").split.reject { |t| t.length < 2 }
    }

    fingerprints = all_events.map { |e| "#{e[:name]} #{e[:venue]}" }
    tokenised = fingerprints.map { |f| tokenise.call(f) }

    # Build IDF
    doc_count = tokenised.length.to_f
    df = Hash.new(0)
    tokenised.each { |tokens| tokens.uniq.each { |t| df[t] += 1 } }
    idf = {}
    df.each { |term, count| idf[term] = Math.log(doc_count / count) }

    puts "  Vocabulary: #{idf.length} terms"

    # Build TF-IDF vectors
    vectors = tokenised.map do |tokens|
      tf = Hash.new(0)
      tokens.each { |t| tf[t] += 1 }
      max_tf = tf.values.max.to_f
      vec = {}
      tf.each { |term, count| vec[term] = (count / max_tf) * (idf[term] || 1.0) }
      vec
    end

    cosine = ->(a, b) {
      common = a.keys & b.keys
      return 0.0 if common.empty?
      dot = common.sum { |k| a[k] * b[k] }
      mag_a = Math.sqrt(a.values.sum { |v| v**2 })
      mag_b = Math.sqrt(b.values.sum { |v| v**2 })
      return 0.0 if mag_a.zero? || mag_b.zero?
      dot / (mag_a * mag_b)
    }

    venue_sim = ->(v1, v2) {
      return 0.0 if v1.empty? || v2.empty?
      t1 = tokenise.call(v1).to_set
      t2 = tokenise.call(v2).to_set
      return 0.0 if t1.empty? || t2.empty?
      (t1 & t2).size.to_f / (t1 | t2).size.to_f
    }

    puts "\nStep 3: Clustering duplicates..."

    name_threshold = 0.70
    venue_boost = 0.15

    cluster_id = Array.new(all_events.length, -1)
    current_cluster = 0

    all_events.length.times do |i|
      next if cluster_id[i] >= 0
      cluster_id[i] = current_cluster

      ((i + 1)...all_events.length).each do |j|
        next if cluster_id[j] >= 0
        combined = cosine.call(vectors[i], vectors[j]) + (venue_sim.call(all_events[i][:venue], all_events[j][:venue]) * venue_boost)
        cluster_id[j] = current_cluster if combined >= name_threshold
      end

      current_cluster += 1
      print "  #{i}/#{all_events.length} (#{current_cluster} unique)\r" if i % 500 == 0 && i > 0
    end

    puts "  Found #{current_cluster} unique events from #{all_events.length} entries"

    # Group clusters and pick best representative
    puts "\nStep 4: Saving to database..."

    clusters = {}
    all_events.each_with_index do |event, idx|
      cid = cluster_id[idx]
      clusters[cid] ||= []
      clusters[cid] << event
    end

    Event.delete_all
    saved = 0

    clusters.each_value do |members|
      best = members.max_by do |m|
        score = m[:name].length
        score += 50 if m[:event_url].present?
        score += 20 if m[:date].present?
        score
      end

      weeks_seen = members.map { |m| m[:listing_date_range] }.uniq.compact

      Event.create!(
        name: best[:name],
        category: best[:category],
        venue: best[:venue],
        date_text: best[:date],
        event_url: best[:event_url],
        times_listed: members.length,
        first_seen: weeks_seen.first,
        last_seen: weeks_seen.last
      )
      saved += 1
    end

    puts "\nDone! #{saved} unique events saved to database."

    # Summary
    puts "\nCategories:"
    Event.group(:category).count.sort_by { |_, v| -v }.each { |cat, n| puts "  #{cat}: #{n}" }

    puts "\nTop 10 recurring events:"
    Event.order(times_listed: :desc).limit(10).each do |e|
      puts "  #{e.times_listed}x - #{e.name} (#{e.venue})"
    end
  end

  desc "Full pipeline: fetch from Reddit, then extract and deduplicate events"
  task full_import: [:fetch_listings, :extract_events]
end
