# typed: true
# frozen_string_literal: true

class PerformanceProfilingController < ApplicationController
  # This controller just sets a cookie allowing flamegraph generation.
  # It does not access or grant access to any resources.
  skip_before_action :perform_conditional_access_checks, only: [:show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Collab, ApplicationRecord::NotificationsEntries, ApplicationRecord::Mysql2

  def show
    render "error/404", status: :not_found and return unless current_user&.feature_flag_enabled?(:performance_profiling_allowed, default: false)

    cookie = GitHub::PerformanceProfilingCookie.generate(current_user)
    if cookie
      cookie.save!(cookies)
      render json: { status: 201 }, status: 201
    else
      render json: { status: 422 }, status: :unprocessable_entity
    end
  end
end
