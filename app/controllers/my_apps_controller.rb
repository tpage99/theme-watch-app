class MyAppsController < ApplicationController
  layout "authenticated"
  before_action :require_clerk_user!

  def index
    response = ShopinfoApi.new(jwt: clerk_jwt).me_apps
    @apps = response.is_a?(Hash) ? Array(response["data"]) : []
  rescue ShopinfoApi::Unauthorized
    @apps = []
    @api_error = "shopinfo.app rejected the JWT (401). Confirm the same Clerk instance backs both apps."
  rescue ShopinfoApi::Error => e
    @apps = []
    @api_error = "shopinfo.app returned HTTP #{e.status}."
  rescue Faraday::ConnectionFailed
    @apps = []
    @api_error = "Could not reach shopinfo.app at #{ENV.fetch('SHOPINFO_API_BASE_URL', ShopinfoApi::DEFAULT_BASE_URL)}. Is the web_scraper dev server running?"
  end
end
