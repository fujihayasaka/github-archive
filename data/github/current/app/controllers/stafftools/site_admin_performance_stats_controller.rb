# typed: true
# frozen_string_literal: true

class Stafftools::SiteAdminPerformanceStatsController < ApplicationController
  # CAP not necessary - limited to employees and site admins, and allows them to toggle site admin perf mode.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def update
    return render_404 unless can_toggle_site_admin_and_employee_status?

    if params[:enabled] == "true"
      enable_site_admin_performance_stats_mode
    else
      disable_site_admin_performance_stats_mode
    end

    redirect_to :back
  end
end
