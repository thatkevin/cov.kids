class ImportStatus < ApplicationRecord
  KEYS = %w[email reddit eventbrite].freeze

  def self.for(key)
    find_or_create_by!(key: key.to_s)
  end

  def self.set!(key, status, error: nil)
    record = find_or_create_by!(key: key.to_s)
    record.update!(
      status: status.to_s,
      last_run_error: error,
      last_run_at: status.to_s.in?(%w[running queued]) ? record.last_run_at : Time.current
    )
    record.broadcast_replace_to(
      "admin_import_statuses",
      target: "import-status-#{key}",
      partial: "admin/sources/import_status_badge",
      locals: { import_status: record }
    )
    record
  end

  def idle?;    status == "idle";    end
  def queued?;  status == "queued";  end
  def running?; status == "running"; end
  def done?;    status == "done";    end
  def error?;   status == "error";   end
end
