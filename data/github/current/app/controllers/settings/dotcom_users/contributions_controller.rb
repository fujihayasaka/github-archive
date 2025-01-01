# typed: true
# frozen_string_literal: true

class Settings::DotcomUsers::ContributionsController < ApplicationController
  include Settings::DotcomUsers::ControllerMethods

  before_action :login_required
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_user_connection_enabled
  before_action :require_connected_instance

  def update
    bool_value = params[:user][:show_enterprise_contribution_counts_on_dotcom] == "1"
    if !bool_value && !dotcom_user.remove_user_contributions
      redirect_error
    else
      EnterpriseContribution.push_user_contributions_history(current_user) if bool_value
      current_user.show_enterprise_contribution_counts_on_dotcom = bool_value

      redirect_to settings_dotcom_user_path,
        notice: <<-END
          Your contribution counts have been
          #{ bool_value ? "updated on" : "removed from" }
          your #{GitHub.dotcom_host_name_string} profile and will
          #{"not" unless bool_value}
          be sent from now on.
        END
    end
  rescue GitHub::Connect::ConnectionError,
         GitHub::Connect::ApiError
    redirect_error
  end
end
