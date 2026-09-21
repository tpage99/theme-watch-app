require "test_helper"
require "socket"

class ShopinfoApiTest < ActiveSupport::TestCase
  # A real TCP listener that accepts connections and never answers. This is the
  # only honest way to prove the read timeout fires: a stubbed adapter cannot
  # tell us how long the client would actually wait.
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

  setup do
    @server = BlackHoleServer.new
    WebMock.disable_net_connect!(allow: "127.0.0.1:#{@server.port}")
  end

  teardown do
    @server.stop
    WebMock.disable_net_connect!
  end

  def client(timeout: 0.2)
    ShopinfoApi.new(
      jwt: "test-jwt",
      base_url: "http://127.0.0.1:#{@server.port}/api/v1",
      timeout: timeout,
      open_timeout: timeout,
    )
  end

  test "a PUT against a stalled upstream raises Faraday::TimeoutError within the configured timeout and is not retried" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(Faraday::TimeoutError) do
      client(timeout: 0.2).update_app_compatibility("loox", "Dawn", { "status" => "supported" })
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 1.0, "PUT waited #{elapsed.round(2)}s; expected to fail at ~0.2s"
    assert_equal 1, @server.accepted, "PUT must be sent exactly once"
  end

  test "a GET against a stalled upstream is retried RETRY_MAX times with backoff and then raises" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(Faraday::TimeoutError) do
      client(timeout: 0.2).me_ping
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    attempts = 1 + ShopinfoApi::RETRY_MAX
    assert_equal attempts, @server.accepted, "expected #{attempts} attempts"
    # Three 0.2s timeouts plus 0.25s and 0.5s backoff (with jitter) is ~1.5s.
    assert_operator elapsed, :<, 3.0, "GET with retries took #{elapsed.round(2)}s"
  end

  test "production timeouts are short" do
    assert_equal 3, ShopinfoApi::OPEN_TIMEOUT
    assert_equal 5, ShopinfoApi::TIMEOUT
    assert_equal %i[get], ShopinfoApi::RETRY_METHODS
  end

  test "requests carry a theme.watch User-Agent and the bearer token" do
    stub = stub_request(:get, "https://shopinfo.test/api/v1/me/ping")
      .with(headers: { "User-Agent" => ShopinfoApi::USER_AGENT, "Authorization" => "Bearer test-jwt" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { clerk_user_id: "user_1" }.to_json)

    api = ShopinfoApi.new(jwt: "test-jwt", base_url: "https://shopinfo.test/api/v1")

    assert_equal({ "clerk_user_id" => "user_1" }, api.me_ping)
    assert_requested stub
  end
end
