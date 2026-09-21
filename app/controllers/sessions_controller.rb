class SessionsController < ApplicationController
  def new
    @after_sign_in_url = post_sign_in_path
  end

  def sign_up
    @after_sign_up_url = post_sign_in_path
  end
end
