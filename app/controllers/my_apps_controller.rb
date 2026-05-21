class MyAppsController < ApplicationController
  layout "authenticated"
  before_action :require_clerk_user!

  def index
  end
end
