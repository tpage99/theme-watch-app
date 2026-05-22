class MyAppCompatibilitiesController < ApplicationController
  layout "authenticated"
  before_action :require_clerk_user!

  def index
    @slug = params[:slug]
    response = ShopinfoApi.new(jwt: clerk_jwt).app_compatibilities(@slug)
    @compatibilities = response.is_a?(Hash) ? Array(response["data"]) : []
  rescue ShopinfoApi::Unauthorized
    @compatibilities = []
    @api_error = "shopinfo.app rejected the JWT (401). Confirm the same Clerk instance backs both apps."
  rescue ShopinfoApi::Error => e
    @compatibilities = []
    @api_error = e.status == 404 ? "App listing not found." : "shopinfo.app returned HTTP #{e.status}."
  rescue Faraday::ConnectionFailed
    @compatibilities = []
    @api_error = "Could not reach shopinfo.app at #{ENV.fetch('SHOPINFO_API_BASE_URL', ShopinfoApi::DEFAULT_BASE_URL)}."
  end

  def create
    theme_title = params[:theme_title].to_s.strip
    if theme_title.blank?
      flash[:alert] = "Theme title is required."
      return redirect_to my_app_compatibilities_path(params[:slug])
    end
    save_compatibility(params[:slug], theme_title)
  end

  def update
    save_compatibility(params[:slug], params[:theme_title])
  end

  private

  def save_compatibility(slug, theme_title)
    attrs = params.permit(:status, :notes, :min_theme_version, :visible_publicly).to_h
    attrs["visible_publicly"] = ActiveModel::Type::Boolean.new.cast(attrs["visible_publicly"]) if attrs.key?("visible_publicly")

    ShopinfoApi.new(jwt: clerk_jwt).update_app_compatibility(slug, theme_title, attrs)
    redirect_to my_app_compatibilities_path(slug), notice: "Compatibility saved."
  rescue ShopinfoApi::Forbidden => e
    flash[:alert] = e.reason == "admin_locked" ?
      "This row was last edited by a shopinfo.app admin and the claim review window has closed. Contact support to request a change." :
      "Forbidden: #{e.reason || 'unknown'}."
    redirect_to my_app_compatibilities_path(slug)
  rescue ShopinfoApi::Error => e
    flash[:alert] = "shopinfo.app returned HTTP #{e.status}."
    redirect_to my_app_compatibilities_path(slug)
  end
end
