require "faraday"

# Minimal client for the Clerk Backend API. The only call theme.watch makes is
# session revocation on sign-out, so this stays a single method rather than
# pulling in the Clerk SDK. Optional: when CLERK_SECRET_KEY is not set,
# `configured?` is false and callers skip revocation.
class ClerkBackend
  class Error < StandardError; end

  BASE_URL = "https://api.clerk.com/v1/".freeze
  OPEN_TIMEOUT = 3
  TIMEOUT = 5

  def self.configured?
    ENV["CLERK_SECRET_KEY"].present?
  end

  def initialize(secret_key: ENV.fetch("CLERK_SECRET_KEY"), base_url: BASE_URL)
    @secret_key = secret_key
    @base_url = base_url
  end

  # POST /sessions/{id}/revoke. Ends the session on Clerk's side so the browser
  # script cannot re-mint a __session cookie from its __client cookie.
  def revoke_session(session_id)
    response = connection.post("sessions/#{ERB::Util.url_encode(session_id.to_s)}/revoke")
    return true if response.success?

    raise Error, "Clerk returned HTTP #{response.status}: #{response.body.inspect.truncate(300)}"
  end

  private

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = TIMEOUT
      f.response :json, content_type: /\bjson$/
      f.headers["Authorization"] = "Bearer #{@secret_key}"
      f.headers["User-Agent"] = ShopinfoApi::USER_AGENT
      f.adapter Faraday.default_adapter
    end
  end
end
