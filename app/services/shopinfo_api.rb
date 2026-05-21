require "faraday"

# Thin Faraday-backed client for the shopinfo.app HTTP API. Every request is
# authenticated with the Clerk JWT passed in at construction time; shopinfo.app
# auto-upserts the corresponding AppDeveloper row on first call. Endpoints are
# defined in ~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md.
class ShopinfoApi
  class Error < StandardError
    attr_reader :status, :body

    def initialize(status:, body:)
      @status = status
      @body = body
      super("shopinfo.app returned HTTP #{status}: #{body.inspect}")
    end
  end

  class Unauthorized < Error; end

  DEFAULT_BASE_URL = "http://localhost:3000/api/v1".freeze

  def initialize(jwt:)
    @jwt = jwt
  end

  def me_ping
    get("/me/ping")
  end

  private

  def get(path)
    handle(connection.get(path))
  end

  def handle(response)
    return response.body if response.success?
    raise Unauthorized.new(status: response.status, body: response.body) if response.status == 401

    raise Error.new(status: response.status, body: response.body)
  end

  def connection
    @connection ||= Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.headers["Authorization"] = "Bearer #{@jwt}" if @jwt.present?
      f.adapter Faraday.default_adapter
    end
  end

  def base_url
    ENV.fetch("SHOPINFO_API_BASE_URL", DEFAULT_BASE_URL)
  end
end
