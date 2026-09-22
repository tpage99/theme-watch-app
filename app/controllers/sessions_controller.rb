class SessionsController < ApplicationController
  def new
    @after_sign_in_url = post_sign_in_path
  end

  def sign_up
    @after_sign_up_url = post_sign_in_path
  end

  # Server-side sign-out. Works without JavaScript. Three layers:
  #   1. Revoke the session at Clerk when CLERK_SECRET_KEY is configured, so
  #      Clerk JS cannot re-mint __session from its own __client cookie.
  #   2. Expire the __session cookie for this host and its parent domain.
  #   3. Reset the Rails session (flash, stored return path).
  # With JavaScript, the clerk-sign-out Stimulus controller calls Clerk.signOut()
  # first and then submits this form, so both sides agree.
  def destroy
    revoke_clerk_session
    expire_clerk_session_cookie
    reset_session
    redirect_to root_path, status: :see_other
  end

  private

  def revoke_clerk_session
    return unless ClerkBackend.configured?

    sid = clerk_session_id
    return if sid.blank?

    ClerkBackend.new.revoke_session(sid)
  rescue ClerkBackend::Error, Faraday::Error => e
    # Local sign-out still proceeds; log so an expired secret key is visible.
    Rails.logger.warn("[Clerk] session revoke failed: #{e.class} #{e.message}")
  end

  # Clerk JS may set __session host-only or on the parent domain depending on
  # the instance; expiring both covers either case. Deleting a cookie that was
  # never set is harmless.
  def expire_clerk_session_cookie
    cookies.delete(ClerkAuthenticatable::CLERK_SESSION_COOKIE)
    cookies.delete(ClerkAuthenticatable::CLERK_SESSION_COOKIE, domain: :all)
  end
end
