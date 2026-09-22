require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  # Works whether the policy is still report-only or already enforced.
  def csp_header
    response.headers["Content-Security-Policy"] || response.headers["Content-Security-Policy-Report-Only"]
  end

  def directive(name)
    csp_header.split(";").map(&:strip).find { |d| d.start_with?("#{name} ") }
  end

  test "the landing page sends a CSP that names exactly the expected third parties" do
    get root_path

    assert_response :success
    assert csp_header, "no CSP header sent"

    assert_includes directive("default-src"), "'self'"
    assert_includes directive("object-src"), "'none'"
    assert_includes directive("base-uri"), "'self'"
    assert_includes directive("form-action"), "'self'"

    script = directive("script-src")
    assert_includes script, CLERK_ISSUER
    assert_includes script, "https://cdn.usefathom.com"
    assert_includes script, "https://challenges.cloudflare.com"
    assert_match(/'nonce-[A-Za-z0-9+\/=]+'/, script)
    refute_includes script, "'unsafe-inline'"

    connect = directive("connect-src")
    assert_includes connect, CLERK_ISSUER
    assert_includes connect, "https://themewatch-waitlist.taylor-d3a.workers.dev"

    assert_includes directive("frame-src"), CLERK_ISSUER
    assert_includes directive("style-src"), "https://fonts.googleapis.com"
    assert_includes directive("style-src"), "'unsafe-inline'"
    assert_includes directive("font-src"), "https://fonts.gstatic.com"
    assert_includes directive("img-src"), "https://shopinfo.app"
    assert_includes directive("img-src"), "data:"
    assert_includes directive("worker-src"), "blob:"

    # No stray hosts. Everything allowed must be on this list.
    allowed = %w[
      'self' 'none' 'unsafe-inline' data: blob:
      https://cdn.usefathom.com https://challenges.cloudflare.com https://img.clerk.com
      https://fonts.googleapis.com https://fonts.gstatic.com https://shopinfo.app
      https://themewatch-waitlist.taylor-d3a.workers.dev
    ] << CLERK_ISSUER
    csp_header.split(";").flat_map { |d| d.strip.split(" ").drop(1) }.uniq.each do |source|
      next if source.start_with?("'nonce-")
      assert_includes allowed, source, "unexpected CSP source #{source}"
    end
  end

  test "the JSON-LD block carries the same nonce the header allows" do
    get root_path

    nonce = directive("script-src")[/'nonce-([^']+)'/, 1]
    assert nonce, "no nonce in script-src"
    assert_select "script[type='application/ld+json'][nonce=?]", nonce
    assert_select "meta[name=csp-nonce][content=?]", nonce
  end

  test "the CSP is sent on authenticated pages too" do
    clerk_sign_in

    get alerts_path

    assert_response :success
    assert csp_header
    assert_includes directive("script-src"), CLERK_ISSUER
  end

  test "the session cookie is named and scoped explicitly" do
    get my_apps_path # signed out: stores the return path, which writes the session

    set_cookie = response.headers["Set-Cookie"].to_s
    assert_includes set_cookie, "_theme_watch_session="
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
  end

  test "framing and MIME sniffing protections are on" do
    get root_path

    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end
end
