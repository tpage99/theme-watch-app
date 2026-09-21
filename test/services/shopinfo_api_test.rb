require "test_helper"
require "socket"

# Two styles of stubbing here, deliberately:
# - WebMock (the default in test_helper) for response handling, headers and
#   URL building, because it exercises the real Faraday middleware stack.
# - A real local socket that never answers, for the timeout and retry tests,
#   because only a real socket can prove how long the client actually waits.
class ShopinfoApiTest < ActiveSupport::TestCase
  BASE = "https://shopinfo.test/api/v1".freeze

  def api(jwt: "test-jwt", base_url: BASE)
    ShopinfoApi.new(jwt: jwt, base_url: base_url)
  end

  def json(status, body)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  # --- response handling ---------------------------------------------------

  test "a 200 returns the parsed JSON body" do
    stub_request(:get, "#{BASE}/me/ping").to_return(json(200, { clerk_user_id: "user_1", app_developer_id: 7 }))

    assert_equal({ "clerk_user_id" => "user_1", "app_developer_id" => 7 }, api.me_ping)
  end

  test "a 401 raises Unauthorized with the status and parsed body" do
    stub_request(:get, "#{BASE}/me/apps").to_return(json(401, { error: "unauthorized", reason: "invalid_token" }))

    error = assert_raises(ShopinfoApi::Unauthorized) { api.me_apps }
    assert_equal 401, error.status
    assert_equal "invalid_token", error.body["reason"]
  end

  test "a 403 raises Forbidden and exposes the reason" do
    stub_request(:put, "#{BASE}/apps/loox/compatibilities/Dawn")
      .to_return(json(403, { error: "forbidden", reason: "admin_locked" }))

    error = assert_raises(ShopinfoApi::Forbidden) { api.update_app_compatibility("loox", "Dawn", { "status" => "supported" }) }
    assert_equal 403, error.status
    assert_equal "admin_locked", error.reason
  end

  test "Forbidden#reason is nil when the body is not a hash" do
    stub_request(:get, "#{BASE}/me/apps").to_return(status: 403, body: "nope")

    error = assert_raises(ShopinfoApi::Forbidden) { api.me_apps }
    assert_nil error.reason
  end

  test "a 422 raises Error with the status and validation details" do
    stub_request(:put, "#{BASE}/apps/loox/compatibilities/Dawn")
      .to_return(json(422, { error: "validation_failed", details: { status: ["is not included in the list"] } }))

    error = assert_raises(ShopinfoApi::Error) { api.update_app_compatibility("loox", "Dawn", { "status" => "garbage" }) }
    assert_equal 422, error.status
    assert_equal ["is not included in the list"], error.body.dig("details", "status")
    assert_match(/HTTP 422/, error.message)
  end

  test "Unauthorized and Forbidden are subclasses of Error" do
    assert_operator ShopinfoApi::Unauthorized, :<, ShopinfoApi::Error
    assert_operator ShopinfoApi::Forbidden, :<, ShopinfoApi::Error
  end

  # --- request building ----------------------------------------------------

  test "requests carry a theme.watch User-Agent and the bearer token" do
    stub = stub_request(:get, "#{BASE}/me/ping")
      .with(headers: { "User-Agent" => ShopinfoApi::USER_AGENT, "Authorization" => "Bearer test-jwt" })
      .to_return(json(200, { clerk_user_id: "user_1" }))

    api.me_ping

    assert_requested stub
  end

  test "no Authorization header is sent when there is no JWT" do
    stub_request(:get, "#{BASE}/me/ping").to_return(json(200, {}))

    api(jwt: nil).me_ping

    assert_requested(:get, "#{BASE}/me/ping") { |req| !req.headers.key?("Authorization") }
  end

  test "the base URL keeps its /api/v1 prefix with or without a trailing slash" do
    stub = stub_request(:get, "#{BASE}/me/ping").to_return(json(200, {}))

    api(base_url: BASE).me_ping
    api(base_url: "#{BASE}/").me_ping

    assert_requested stub, times: 2
  end

  test "ShopinfoApi.base_url normalizes SHOPINFO_API_BASE_URL to end with a slash" do
    original = ENV["SHOPINFO_API_BASE_URL"]

    ENV["SHOPINFO_API_BASE_URL"] = "https://shopinfo.app/api/v1"
    assert_equal "https://shopinfo.app/api/v1/", ShopinfoApi.base_url

    ENV["SHOPINFO_API_BASE_URL"] = "https://shopinfo.app/api/v1/"
    assert_equal "https://shopinfo.app/api/v1/", ShopinfoApi.base_url

    ENV.delete("SHOPINFO_API_BASE_URL")
    assert_equal "#{ShopinfoApi::DEFAULT_BASE_URL}/", ShopinfoApi.base_url
  ensure
    ENV["SHOPINFO_API_BASE_URL"] = original
  end

  test "update_app_compatibility URL-encodes the theme title and sends a JSON body" do
    stub = stub_request(:put, "#{BASE}/apps/loox/compatibilities/Dawn%202.0%2F%CE%B2")
      .with(
        headers: { "Content-Type" => "application/json" },
        body: { "status" => "supported", "visible_publicly" => true },
      )
      .to_return(json(201, { theme_title: "Dawn 2.0/β" }))

    api.update_app_compatibility("loox", "Dawn 2.0/β", { "status" => "supported", "visible_publicly" => true })

    assert_requested stub
  end

  test "app_compatibilities passes only the query params that are set" do
    stub = stub_request(:get, "#{BASE}/apps/loox/compatibilities")
      .with(query: { "status" => "supported,unknown", "limit" => "10" })
      .to_return(json(200, { data: [] }))

    api.app_compatibilities("loox", status: "supported,unknown", limit: 10)

    assert_requested stub
  end

  # --- timeouts and retries -------------------------------------------------

  # A real TCP listener that accepts connections and never answers.
  class BlackHoleServer
    attr_reader :port, :accepted

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @accepted = 0
      @conns = []
      @thread = Thread.new do
        loop do
          conn = @server.accept
          @accepted += 1
          @conns << conn
        rescue IOError, Errno::EBADF
          break
        end
      end
    end

    def stop
      @server.close
      @conns.each { |c| c.close rescue nil }
      @thread.join(1)
    end
  end

  def with_black_hole
    server = BlackHoleServer.new
    WebMock.disable_net_connect!(allow: "127.0.0.1:#{server.port}")
    client = ShopinfoApi.new(jwt: "test-jwt", base_url: "http://127.0.0.1:#{server.port}/api/v1", timeout: 0.2, open_timeout: 0.2)
    yield server, client
  ensure
    server&.stop
    WebMock.disable_net_connect!
  end

  test "a PUT against a stalled upstream raises Faraday::TimeoutError within the configured timeout and is not retried" do
    with_black_hole do |server, client|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_raises(Faraday::TimeoutError) do
        client.update_app_compatibility("loox", "Dawn", { "status" => "supported" })
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert_operator elapsed, :<, 1.0, "PUT waited #{elapsed.round(2)}s; expected to fail at ~0.2s"
      assert_equal 1, server.accepted, "PUT must be sent exactly once"
    end
  end

  test "a GET against a stalled upstream is retried RETRY_MAX times with backoff and then raises" do
    with_black_hole do |server, client|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_raises(Faraday::TimeoutError) { client.me_ping }

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      attempts = 1 + ShopinfoApi::RETRY_MAX
      assert_equal attempts, server.accepted, "expected #{attempts} attempts"
      # Three 0.2s timeouts plus 0.25s and 0.5s backoff (with jitter) is ~1.5s.
      assert_operator elapsed, :<, 3.0, "GET with retries took #{elapsed.round(2)}s"
    end
  end

  test "production timeouts are short and only GETs are retried" do
    assert_equal 3, ShopinfoApi::OPEN_TIMEOUT
    assert_equal 5, ShopinfoApi::TIMEOUT
    assert_equal %i[get], ShopinfoApi::RETRY_METHODS
  end
end
