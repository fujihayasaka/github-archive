# typed: true
# frozen_string_literal: true

class Settings::CopilotDashboardEntryPointEnabledController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  def update
    return head :not_found unless current_copilot_user
    return head :unprocessable_entity unless params[:dashboard_entry_point].present?

    if params[:dashboard_entry_point] == "enabled"
      copilot_user.dashboard_entry_point_enabled!
    else
      copilot_user.dashboard_entry_point_disabled!
    end


    head :ok
  end

  private

  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end
end
