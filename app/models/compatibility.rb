# Plain Ruby value object (no Active Record; theme.watch has no database).
# Single source of truth for the AppThemeCompatibility status vocabulary as
# defined in the shopinfo.app API contract.
class Compatibility
  STATUSES = {
    "supported"           => "Supported",
    "needs_customization" => "Needs customization",
    "not_supported"       => "Not supported",
    "unknown"             => "Unknown",
  }.freeze

  # [[label, value], ...] in the shape Rails select helpers expect.
  def self.status_options
    STATUSES.map { |value, label| [label, value] }
  end

  def self.status_label(value)
    STATUSES.fetch(value.to_s, value.to_s.humanize)
  end
end
