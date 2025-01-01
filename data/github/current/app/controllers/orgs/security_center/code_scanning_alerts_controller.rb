# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::CodeScanningAlertsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include CodeScanning::AlertsSerializer
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  sig { void }
  def index
    per_page = 25

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    if query.is_valid?
      # Tenant filtering was performed in alerts_by_repo_with_response so the results here are already filtered
      alert_results, _, has_error, response = alert_query_service.alerts_by_repo_with_response(
        per_page:,
        before_cursor:,
        after_cursor:,
      )
    else
      alert_results = []
      has_error = false
      response = nil
    end

    if has_error
      return render json: {
        message: "Loading code scanning alerts failed",
      }, status: :internal_server_error
    end

    open_count = T.let(response&.data&.try(:open_count) || 0, Integer)
    closed_count = T.let(response&.data&.try(:resolved_count) || 0, Integer)
    next_cursor = T.let(response&.data&.try(:next_cursor), T.nilable(String))
    prev_cursor = T.let(response&.data&.try(:prev_cursor), T.nilable(String))

    render json: {
      alerts: serialized_alerts(alerts: alert_results),
      openCount: open_count,
      closedCount: closed_count,
      nextCursor: next_cursor,
      prevCursor: prev_cursor,
    }
  end

  private

  sig { void }
  def feature_required
    render_404 unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
  end

  sig { void }
  def security_center_required
    render_404 unless SecurityCenter::SecurityFeatures.security_center_available?(this_organization, dotcom_request_only: true)
  end
end
