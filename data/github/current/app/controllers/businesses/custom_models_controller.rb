# typed: true
# frozen_string_literal: true

class Businesses::CustomModelsController < Businesses::BusinessController
  before_action :github_models_required
  before_action :business_owner_required

  def update
    if params[:enable_custom_models] == "on"
      this_business.enable_custom_models(current_user)
      flash[:notice] = "Custom models access enabled"
    elsif params[:enable_custom_models] == "off"
      this_business.disable_custom_models(current_user)
      flash[:notice] = "Custom models access disabled"
    end

    redirect_to settings_models_enterprise_path(this_business)
  end
end
