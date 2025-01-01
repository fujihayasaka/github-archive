# typed: true
# frozen_string_literal: true

class Stafftools::SiteAdminAndEmployeeStatusController < ApplicationController
  # CAP not necessary - this only sets/unsets the session variable :disable_site_admin_and_employee_status
  # While this seems like a controller that should be employee/site_admin only (ignoring the session variable), it can be called by ordinary users.
  # The only thing that happens for normal users is a no-op though: `session.delete(:disable_site_admin_and_employee_status)`
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def update
    if params[:enabled] == "true"
      enable_site_admin_and_employee_mode
    elsif params[:enabled] == "false"
      disable_site_admin_and_employee_mode
    else
      toggle_site_admin_and_employee_mode
    end

    if request.xhr?
      head :ok
    else
      safe_redirect_to request.headers["Referer"]
    end
  end
end
