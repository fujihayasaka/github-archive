# typed: true
# frozen_string_literal: true

class Orgs::Settings::UserNameDisplayController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only

  def create
    begin
      current_organization.update_user_name_display_configuration(actor: current_user, config_value: user_name_display_value)
      flash[:success] = "Profile name visibility setting updated."
    rescue Configurable::UserNameDisplayConfiguration::UserNameDisplayConfigurationError => error
      flash[:error] = error.message
    end
    redirect_to settings_org_profile_path(current_organization)
  end

  private

  memoize def user_name_display_value
    case params.require(:value)
    when "1"
      Configurable::UserNameDisplayConfiguration::NAME_AND_HANDLE
    when "0"
      Configurable::UserNameDisplayConfiguration::HANDLE
    else
      nil
    end
  end
end
