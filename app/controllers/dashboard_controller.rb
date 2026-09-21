class DashboardController < ApplicationController
  layout "authenticated"
  before_action :require_clerk_user!

  def index
    @ping = ShopinfoApi.new(jwt: clerk_jwt).me_ping
  end
end
