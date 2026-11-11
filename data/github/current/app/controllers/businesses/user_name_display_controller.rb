# typed: true
# frozen_string_literal: true

class Businesses::UserNameDisplayController < Businesses::BusinessController
  before_action :business_owner_required

  def update
    begin
      if user_name_display_params[:value] == "no_policy"
        this_business.reset_user_name_display_configuration(actor: current_user)
      else
        this_business.update_user_name_display_configuration(actor: current_user, config_value: user_name_display_params[:value], final: user_name_display_params[:policy] == "1")
      end
      flash[:profile_success] = "Profile name visibility setting updated."
      redirect_to settings_profile_enterprise_path(this_business)
    rescue Configurable::UserNameDisplayConfiguration::UserNameDisplayConfigurationError => error
      flash.now[:error] = error.message
      render "businesses/settings/profile"
    end
  end

  private

  memoize def user_name_display_params
    params.require(:user_name_display).permit(:value, :policy)
  end
end
