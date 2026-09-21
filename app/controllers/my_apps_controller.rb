class MyAppsController < ApplicationController
  layout "authenticated"
  before_action :require_clerk_user!

  def index
    response = ShopinfoApi.new(jwt: clerk_jwt).me_apps
    @apps = response.is_a?(Hash) ? Array(response["data"]) : []
  end
end
