# typed: true
# frozen_string_literal: true

class Settings::EnterpriseInstallations::StatsExportController < ApplicationController
  before_action :dotcom_required
  before_action :login_required
  before_action :ensure_current_organization_admin

  def create
    # Download the usage metrics from the S4 service
    export_data = current_organization.s4_usage_metrics(format: params[:format])
    current_organization.instrument_connect_usage_metrics_export actor: current_user, total_entries: export_data[:record_count]
    send_data export_data[:blob], type: export_data[:content_type], filename: "stats-export.#{params[:format]}"
  end

  private

  def current_organization
    helpers.current_organization
  end

  def target_for_conditional_access
    # current_organization can be nil if the current_user doesn't have access to it
    # in this case, we can ignore conditional access policies and subject them to regular authz checks
    return :no_target_for_conditional_access unless current_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_organization
  end

  def ensure_current_organization_admin
    render_404 unless helpers.org_admin?
  end
end
