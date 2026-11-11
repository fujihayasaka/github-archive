# typed: true
# frozen_string_literal: true

class Stafftools::UIRuntimeOptOutController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  allow_verified_fetch only: [:update]
  before_action :employee_only, only: [:update]
  before_action :require_ui_service_opt_out_flag, only: [:update]

  def update
    if cookies[:_ui_opt_out].present?
      cookies.delete(:_ui_opt_out)
    else
      cookies[:_ui_opt_out] = "true"
    end

    if request.xhr? || use_verified_fetch?
      head :ok
    else
      safe_redirect_to request.headers["Referer"]
    end
  end

  private

  def require_ui_service_opt_out_flag
    render_404 unless ui_service_opt_out_enabled?
  end
end
