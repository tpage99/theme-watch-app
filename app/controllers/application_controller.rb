class ApplicationController < ActionController::Base
  include ClerkAuthenticatable

  # Every controller that talks to shopinfo.app raises one of these. The handlers
  # below log the full detail for operators and show the user one plain sentence.
  # Order matters: rescue_from searches bottom-up, so the generic Error handler is
  # declared first and the more specific subclasses after it.
  UPSTREAM_UNAVAILABLE = "shopinfo.app is not responding right now. Try again in a minute.".freeze

  rescue_from ShopinfoApi::Error do |e|
    log_api_failure(e)
    case e.status
    when 404
      api_error("That app listing was not found on shopinfo.app.", status: :not_found)
    when 422
      api_error("shopinfo.app did not accept that change. Check the values and try again.", status: :unprocessable_entity)
    else
      api_error(UPSTREAM_UNAVAILABLE, status: :bad_gateway)
    end
  end

  rescue_from ShopinfoApi::Forbidden do |e|
    log_api_failure(e, hint: "reason=#{e.reason.inspect}")
    message =
      case e.reason
      when "admin_locked"
        "This row was last edited by a shopinfo.app admin and the claim review window has closed. Contact support to request a change."
      when "not_owner"
        "You do not own this app listing."
      else
        "shopinfo.app did not allow that change."
      end
    api_error(message, status: :forbidden)
  end

  rescue_from ShopinfoApi::Unauthorized do |e|
    log_api_failure(e, hint: "shopinfo.app rejected the Clerk JWT. Confirm CLERK_FRONTEND_API is identical on both services.")
    api_error("shopinfo.app did not accept your sign-in. Sign out, sign back in, and try again.", status: :bad_gateway)
  end

  rescue_from Faraday::ConnectionFailed, Faraday::TimeoutError do |e|
    log_api_failure(e, hint: "Could not reach shopinfo.app. Check SHOPINFO_API_BASE_URL and that the shopinfo.app service is up.")
    api_error(UPSTREAM_UNAVAILABLE, status: :bad_gateway)
  end

  private

  # GET requests re-render the current page with the error panel in place of
  # the data. Anything else redirects back with the message in the flash.
  def api_error(message, status:)
    if request.get?
      @api_error = message
      render action_name, status: status
    else
      flash[:alert] = message
      redirect_back_or_to dashboard_path
    end
  end

  def log_api_failure(error, hint: nil)
    detail = {
      request_id: request.request_id,
      base_url: ShopinfoApi.base_url,
      error: error.class.name,
    }
    if error.respond_to?(:status)
      detail[:status] = error.status
      detail[:body] = error.body.inspect.truncate(500)
    else
      detail[:message] = error.message
    end
    detail[:hint] = hint if hint

    Rails.logger.error("[ShopinfoApi] #{detail.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}")
  end
end
