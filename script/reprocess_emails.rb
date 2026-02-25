require "net/imap"
require "open3"

# One-off script to reprocess all emails to ck@kev.cc regardless of SEEN status.
# Run from a terminal (not inside a Claude Code session):
#   bin/rails runner script/reprocess_emails.rb

SUPPORTED_ATTACHMENT_TYPES = %w[.jpg .jpeg .png .gif .webp .pdf].freeze

EXTRACT_PROMPT = <<~PROMPT.freeze
  Extract all events from the provided content. Return ONLY a JSON array, no markdown, no explanation.
  Each element should have these fields (use null for any that are missing):
    name       - event name (required, skip if blank)
    date_text  - date/time as written in the source
    venue      - venue name
    category   - one of: music, comedy, arts, sport, food, film, family, community, other
    event_url  - URL to buy tickets or get more info

  If no events are found, return [].
PROMPT

def run_claude(prompt, file_path = nil)
  env = { "CLAUDECODE" => nil }
  if file_path
    full_prompt = "#{prompt}\n\nRead and analyse the file at this path: #{file_path}"
    args = ["claude", "--print", "--add-dir", File.dirname(file_path)]
  else
    full_prompt = prompt
    args = ["claude", "--print"]
  end
  stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: full_prompt)
  $stderr.puts "Claude stderr: #{stderr}" if stderr.present?
  stdout
end

def strip_fences(text)
  text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
end

def save_events(raw, source)
  events = JSON.parse(strip_fences(raw))
  today = Date.current.to_s
  puts "  → #{events.size} event(s) extracted"

  events.each do |data|
    next if data["name"].blank?

    venue = data["venue"].presence || "Unknown"
    event = Event.find_or_initialize_by(name: data["name"], venue: venue)

    if event.persisted?
      event.increment!(:times_listed)
      event.update!(last_seen: today)
      puts "    Updated: #{data["name"]}"
    else
      event.assign_attributes(
        category: data["category"],
        date_text: data["date_text"],
        event_url: data["event_url"],
        first_seen: today,
        last_seen: today
      )
      event.save!
      puts "    Created: #{data["name"]} @ #{venue} (#{data["date_text"]})"
    end
  rescue ActiveRecord::RecordInvalid => e
    puts "    FAILED to save '#{data["name"]}': #{e.message}"
  end
rescue JSON::ParserError => e
  puts "  FAILED to parse Claude response: #{e.message}"
  puts "  Raw response: #{raw.slice(0, 300)}"
end

creds = Rails.application.credentials.gmail
imap = Net::IMAP.new("imap.gmail.com", port: 993, ssl: true)
imap.login(creds[:username], creds[:app_password])
imap.select("INBOX")

ids = imap.search(["TO", "ck@kev.cc"])
puts "Found #{ids.size} email(s) to ck@kev.cc\n\n"

ids.each do |id|
  raw = imap.fetch(id, "RFC822")[0].attr["RFC822"]
  msg = Mail.new(raw)
  message_id = msg.message_id.to_s.gsub(/[<>]/, "").presence || SecureRandom.uuid
  source_url = "email:#{message_id}"

  puts "Processing: #{msg.subject} (#{msg.date})"

  source = Source.find_or_initialize_by(url: source_url)
  if source.persisted?
    puts "  Source already exists (id=#{source.id}), reprocessing events..."
  else
    text_body = begin
      part = msg.text_part || msg.html_part || msg
      part.decoded.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    rescue
      ""
    end

    source = Source.create!(
      title: msg.subject.presence || "Email #{msg.date}",
      body: text_body,
      url: source_url,
      source_type: "email",
      published_at: msg.date
    )
    puts "  Source created (id=#{source.id})"
  end

  # Process text body
  text_body = source.body.presence
  if text_body.present?
    puts "  Running Claude on email body..."
    prompt = EXTRACT_PROMPT + "\n\nEmail content:\n#{text_body.slice(0, 8000)}"
    result = run_claude(prompt)
    save_events(result, source)
  end

  # Process attachments
  msg.attachments.each do |attachment|
    ext = File.extname(attachment.filename.to_s).downcase
    unless SUPPORTED_ATTACHMENT_TYPES.include?(ext)
      puts "  Skipping attachment: #{attachment.filename} (unsupported type)"
      next
    end

    puts "  Running Claude on attachment: #{attachment.filename}..."
    Tempfile.create(["ck_attachment", ext]) do |f|
      f.binmode
      f.write(attachment.decoded)
      f.flush
      result = run_claude(EXTRACT_PROMPT + "\n\nAnalyse the attached file.", f.path)
      save_events(result, source)
    end
  end

  puts
end

imap.logout
imap.disconnect

puts "\nDone. Events in DB: #{Event.count}"
