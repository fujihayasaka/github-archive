# typed: true
# frozen_string_literal: true

class DashboardSurfacePreferencesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch only: [:update]

  def update
    notice = nil
    status = :ok

    dashboard_surface_compact_mode = params[:dashboard_surface_compact_mode]

    if dashboard_surface_compact_mode.present?
      unless [true, false, "true", "false"].include?(dashboard_surface_compact_mode)
        render json: { notice: "Invalid value for dashboard_surface_compact_mode." }, status: :bad_request
        return
      end

      current_user.settings.set!(:dashboard_surface_compact_mode, dashboard_surface_compact_mode)

      notice = "Dashboard surface compact mode preference successfully saved."
    end

    if notice.nil?
      notice = "No valid parameters provided."
      status = :bad_request
    end

    render json: { notice: }, status:
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
