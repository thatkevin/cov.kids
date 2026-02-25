require "net/imap"
require "open3"

class EmailImportJob < ApplicationJob
  queue_as :default

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

  def perform
    messages = fetch_unread_messages
    Rails.logger.info("EmailImportJob: found #{messages.size} unread message(s)")
    messages.each { |msg| process_message(msg) }
  end

  private

  def fetch_unread_messages
    imap = Net::IMAP.new("imap.gmail.com", port: 993, ssl: true)
    imap.login(credentials[:username], credentials[:app_password])
    imap.select("INBOX")

    ids = imap.search(["TO", "ck@kev.cc", "UNSEEN"])
    return [] if ids.empty?

    ids.filter_map do |id|
      raw = imap.fetch(id, "RFC822").first.attr["RFC822"]
      imap.store(id, "+FLAGS", [:Seen])
      Mail.new(raw)
    rescue => e
      Rails.logger.error("EmailImportJob: failed to fetch message #{id}: #{e.message}")
      nil
    end
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  def process_message(message)
    message_id = message.message_id.to_s.gsub(/[<>]/, "").presence || SecureRandom.uuid
    source_url = "email:#{message_id}"

    return if Source.exists?(url: source_url)

    text_body = extract_text(message)

    source = Source.create!(
      title: message.subject.presence || "Email #{message.date}",
      body: text_body,
      url: source_url,
      source_type: detect_source_type(message),
      published_at: message.date
    )

    extract_and_save_events(text_body, source) if text_body.present?

    message.attachments.each do |attachment|
      process_attachment(attachment, source)
    end
  rescue => e
    Rails.logger.error("EmailImportJob: failed to process message: #{e.message}")
  end

  def extract_text(message)
    part = message.text_part || message.html_part || message
    part.decoded.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  rescue => e
    Rails.logger.warn("EmailImportJob: could not decode message body: #{e.message}")
    ""
  end

  def process_attachment(attachment, source)
    ext = File.extname(attachment.filename.to_s).downcase
    return unless SUPPORTED_ATTACHMENT_TYPES.include?(ext)

    Tempfile.create(["ck_attachment", ext]) do |f|
      f.binmode
      f.write(attachment.decoded)
      f.flush
      events_json = run_claude(EXTRACT_PROMPT + "\n\nAnalyse the attached file.", f.path)
      save_events(events_json, source)
    end
  rescue => e
    Rails.logger.error("EmailImportJob: failed to process attachment #{attachment.filename}: #{e.message}")
  end

  def extract_and_save_events(text, source)
    prompt = EXTRACT_PROMPT + "\n\nEmail content:\n#{text.slice(0, 8000)}"
    events_json = run_claude(prompt)
    save_events(events_json, source)
  end

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
    Rails.logger.error("Claude stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("EmailImportJob: claude invocation failed: #{e.message}")
    "[]"
  end

  def save_events(raw, source)
    events = JSON.parse(strip_fences(raw))
    today = Date.current.to_s

    events.each do |data|
      next if data["name"].blank?

      existing = Event.similar_to(data["name"]).first
      if existing
        existing.increment!(:times_listed)
        existing.update!(last_seen: today, source_id: existing.source_id || source.id)
      else
        Event.create!(
          name:       data["name"],
          venue:      data["venue"].presence || "Unknown",
          category:   data["category"],
          date_text:  data["date_text"],
          event_url:  data["event_url"],
          source:     source,
          first_seen: today,
          last_seen:  today,
          status:     :pending
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("EmailImportJob: could not save event '#{data["name"]}': #{e.message}")
    end
  rescue JSON::ParserError => e
    Rails.logger.error("EmailImportJob: could not parse Claude response as JSON: #{e.message}\nRaw: #{raw.slice(0, 200)}")
  end

  def strip_fences(text)
    text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
  end

  def detect_source_type(message)
    from = Array(message.from).join(" ")
    return "facebook" if from.include?("facebookmail.com")
    "email"
  end

  def credentials
    Rails.application.credentials.gmail
  end
end
