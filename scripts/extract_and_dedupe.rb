#!/usr/bin/env ruby
# Extracts individual events from the weekly listings CSV, then deduplicates
# using Bayesian-inspired TF-IDF token similarity scoring.

require "csv"
require "set"
require "json"

INPUT_FILE  = File.expand_path("../../old-listings/listings.csv", __FILE__)
OUTPUT_FILE = File.expand_path("../../old-listings/events_deduped.csv", __FILE__)
STATS_FILE  = File.expand_path("../../old-listings/dedup_stats.json", __FILE__)

# --- Step 1: Parse events from markdown tables ---

def extract_events_from_selftext(selftext, listing_title, listing_date_range, listing_url)
  events = []
  current_category = "Uncategorised"

  selftext.each_line do |line|
    line = line.strip

    # Detect category headers: # 🎨 Art & Exhibitions
    if line.match?(/^#\s+/)
      # Strip markdown heading and emoji
      current_category = line
        .sub(/^#+\s*/, "")
        .gsub(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}]\uFE0F?/, "")
        .strip
      next
    end

    # Parse table rows: |[Event Name](url)|Date|Venue|
    next unless line.start_with?("|")
    next if line.match?(/^\|[\s:-]+\|/)  # skip separator rows
    next if line.match?(/^\|\s*Event\s*\|/i)  # skip header rows

    cols = line.split("|").map(&:strip).reject(&:empty?)
    next if cols.length < 3

    # Extract event name and URL from markdown link
    event_cell = cols[0]
    event_name = nil
    event_url = nil

    if event_cell.match?(/\[(.+?)\]\((.+?)\)/)
      match = event_cell.match(/\[(.+?)\]\((.+?)\)/)
      event_name = match[1].strip
      event_url = match[2].strip
    else
      event_name = event_cell.gsub(/[\[\]]/, "").strip
    end

    next if event_name.nil? || event_name.empty?

    date_str = cols[1]&.strip || ""
    venue = cols[2]&.strip || ""

    events << {
      name: event_name,
      date: date_str,
      venue: venue,
      category: current_category,
      event_url: event_url,
      listing_date_range: listing_date_range,
      listing_url: listing_url
    }
  end

  events
end

# --- Step 2: Bayesian TF-IDF deduplication ---

# Tokenise a string into normalised terms
def tokenise(text)
  text
    .downcase
    .gsub(/[^a-z0-9\s]/, " ")
    .split
    .reject { |t| t.length < 2 }
end

# Build inverse document frequency from a corpus of documents (arrays of tokens)
def build_idf(documents)
  doc_count = documents.length.to_f
  df = Hash.new(0)

  documents.each do |tokens|
    tokens.uniq.each { |t| df[t] += 1 }
  end

  idf = {}
  df.each { |term, count| idf[term] = Math.log(doc_count / count) }
  idf
end

# TF-IDF weighted vector for a token list
def tfidf_vector(tokens, idf)
  tf = Hash.new(0)
  tokens.each { |t| tf[t] += 1 }
  max_tf = tf.values.max.to_f

  vec = {}
  tf.each do |term, count|
    vec[term] = (count / max_tf) * (idf[term] || 1.0)
  end
  vec
end

# Cosine similarity between two TF-IDF vectors
def cosine_similarity(vec_a, vec_b)
  common = vec_a.keys & vec_b.keys
  return 0.0 if common.empty?

  dot = common.sum { |k| vec_a[k] * vec_b[k] }
  mag_a = Math.sqrt(vec_a.values.sum { |v| v**2 })
  mag_b = Math.sqrt(vec_b.values.sum { |v| v**2 })

  return 0.0 if mag_a.zero? || mag_b.zero?
  dot / (mag_a * mag_b)
end

# Venue similarity boost - same venue makes a match more likely (Bayesian prior)
def venue_similarity(v1, v2)
  return 0.0 if v1.empty? || v2.empty?

  t1 = tokenise(v1).to_set
  t2 = tokenise(v2).to_set
  return 0.0 if t1.empty? || t2.empty?

  intersection = (t1 & t2).size.to_f
  union = (t1 | t2).size.to_f
  intersection / union
end

# --- Main ---

puts "Step 1: Parsing events from listings..."

listings = CSV.read(INPUT_FILE, headers: true)
all_events = []

listings.each do |row|
  selftext = row["selftext"]
  next if selftext.nil? || selftext.strip.empty?

  events = extract_events_from_selftext(
    selftext,
    row["title"],
    row["date_range"] || row["title"],
    row["url"]
  )
  all_events.concat(events)
end

puts "  Extracted #{all_events.length} total event entries across #{listings.length} listings"

# --- Step 3: Deduplicate ---

puts "\nStep 2: Building TF-IDF model..."

# Create a "fingerprint" string for each event combining name + venue
fingerprints = all_events.map { |e| "#{e[:name]} #{e[:venue]}" }
tokenised = fingerprints.map { |f| tokenise(f) }
idf = build_idf(tokenised)
vectors = tokenised.map { |tokens| tfidf_vector(tokens, idf) }

puts "  Vocabulary size: #{idf.length} terms"

puts "\nStep 3: Clustering duplicates (this may take a moment)..."

# Similarity threshold - tuned for event matching
# Name similarity is weighted heavily, venue provides a Bayesian prior boost
NAME_SIM_THRESHOLD = 0.70
VENUE_BOOST = 0.15

cluster_id = Array.new(all_events.length, -1)
current_cluster = 0

all_events.length.times do |i|
  next if cluster_id[i] >= 0  # already assigned

  cluster_id[i] = current_cluster
  members = [i]

  # Find all matches for this event
  ((i + 1)...all_events.length).each do |j|
    next if cluster_id[j] >= 0

    name_sim = cosine_similarity(vectors[i], vectors[j])
    v_sim = venue_similarity(all_events[i][:venue], all_events[j][:venue])

    # Bayesian-inspired combined score: text similarity + venue prior
    combined = name_sim + (v_sim * VENUE_BOOST)

    if combined >= NAME_SIM_THRESHOLD
      cluster_id[j] = current_cluster
      members << j
    end
  end

  current_cluster += 1

  # Progress indicator
  if i % 500 == 0 && i > 0
    print "  Processed #{i}/#{all_events.length} events (#{current_cluster} unique so far)\r"
  end
end

puts "  Found #{current_cluster} unique events from #{all_events.length} total entries"

# --- Step 4: Pick the best representative from each cluster ---

puts "\nStep 4: Selecting best representatives and writing output..."

clusters = {}
all_events.each_with_index do |event, idx|
  cid = cluster_id[idx]
  clusters[cid] ||= []
  clusters[cid] << event
end

deduped = clusters.map do |_cid, members|
  # Pick the member with the most complete data (longest name + has URL)
  best = members.max_by do |m|
    score = m[:name].length
    score += 50 if m[:event_url] && !m[:event_url].empty?
    score += 20 if m[:date] && !m[:date].empty?
    score
  end

  # Collect all weeks this event appeared in
  weeks_seen = members.map { |m| m[:listing_date_range] }.uniq.compact
  first_seen = weeks_seen.first
  last_seen = weeks_seen.last

  {
    name: best[:name],
    category: best[:category],
    venue: best[:venue],
    date: best[:date],
    event_url: best[:event_url],
    times_listed: members.length,
    first_seen: first_seen,
    last_seen: last_seen,
    listing_url: best[:listing_url]
  }
end

# Sort by category then name
deduped.sort_by! { |e| [e[:category], e[:name].downcase] }

CSV.open(OUTPUT_FILE, "w") do |csv|
  csv << %w[name category venue date event_url times_listed first_seen last_seen listing_url]

  deduped.each do |event|
    csv << [
      event[:name],
      event[:category],
      event[:venue],
      event[:date],
      event[:event_url],
      event[:times_listed],
      event[:first_seen],
      event[:last_seen],
      event[:listing_url]
    ]
  end
end

# Write stats
stats = {
  total_raw_entries: all_events.length,
  unique_events: deduped.length,
  dedup_ratio: ((1 - deduped.length.to_f / all_events.length) * 100).round(1),
  categories: deduped.map { |e| e[:category] }.tally.sort_by { |_, v| -v }.to_h,
  top_recurring: deduped.select { |e| e[:times_listed] > 5 }
    .sort_by { |e| -e[:times_listed] }
    .first(20)
    .map { |e| { name: e[:name], venue: e[:venue], times: e[:times_listed] } },
  venues: deduped.map { |e| e[:venue] }.tally.sort_by { |_, v| -v }.first(20).to_h
}

File.write(STATS_FILE, JSON.pretty_generate(stats))

puts "\nDone!"
puts "  Raw entries:   #{stats[:total_raw_entries]}"
puts "  Unique events: #{stats[:unique_events]}"
puts "  Dedup ratio:   #{stats[:dedup_ratio]}%"
puts "  Output:        #{OUTPUT_FILE}"
puts "  Stats:         #{STATS_FILE}"
puts "\nTop 10 most recurring events:"
stats[:top_recurring].first(10).each do |e|
  puts "  #{e[:times]} weeks - #{e[:name]} (#{e[:venue]})"
end
puts "\nCategories:"
stats[:categories].each { |cat, count| puts "  #{cat}: #{count}" }
