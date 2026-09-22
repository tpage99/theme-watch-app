module ApplicationHelper
  FOCUS_RING = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-tw-400 focus-visible:ring-offset-2 focus-visible:ring-offset-tw-950".freeze

  BUTTON_VARIANTS = {
    primary:   "rounded-md bg-tw-500 hover:bg-tw-400 text-tw-950 text-sm font-semibold px-4 py-2 transition-colors cursor-pointer",
    secondary: "rounded-md border border-white/10 bg-white/[0.02] hover:bg-white/[0.05] text-xs text-white/65 hover:text-white font-medium px-3 py-2 transition-all cursor-pointer",
    danger:    "rounded-md border border-red-500/30 bg-red-500/[0.06] hover:bg-red-500/[0.12] text-red-200 text-xs font-medium px-3 py-2 transition-colors cursor-pointer",
  }.freeze

  # Shared button classes. Every variant carries a visible keyboard focus ring.
  def button_classes(variant = :primary, extra = nil)
    [BUTTON_VARIANTS.fetch(variant), FOCUS_RING, extra].compact.join(" ")
  end

  # Visible focus ring for links and other non-button controls.
  def focus_ring
    FOCUS_RING
  end

  # Renders an ISO 8601 timestamp as relative time inside a <time> element,
  # keeping the machine-readable value in the datetime attribute. Falls back to
  # the raw string if it does not parse.
  def relative_time(iso)
    return "" if iso.blank?

    time = Time.iso8601(iso.to_s)
    tag.time("#{time_ago_in_words(time)} ago", datetime: time.utc.iso8601, title: time.utc.strftime("%Y-%m-%d %H:%M UTC"))
  rescue ArgumentError
    iso.to_s
  end
end
