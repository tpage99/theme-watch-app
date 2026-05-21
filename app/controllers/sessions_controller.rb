class SessionsController < ApplicationController
  include ClerkAuthenticatable

  def new
  end

  def sign_up
  end

  def destroy
    redirect_to root_path
  end
end
