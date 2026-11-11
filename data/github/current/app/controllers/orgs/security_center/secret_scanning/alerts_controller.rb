# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecretScanning::AlertsController < Orgs::SecurityCenter::SecretScanning::AbstractController
  include SecretScanningControllerHelper
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  sig { void }
  def index
    per_page = 25

    after_cursor = params[:after].try(:to_str) || "" # the empty string opts-in to ID-based cursor paging rather than skip offset paging
    after_cursor = Base64.urlsafe_decode64(after_cursor) unless after_cursor.blank?
    before_cursor = params[:before].try(:to_str)
    before_cursor = Base64.urlsafe_decode64(before_cursor) unless before_cursor.blank?

    unless has_repositories?
      return render json: {
        alerts: [],
        alertCount: 0,
        openCount: 0,
        closedCount: 0,
        nextCursor: nil,
        prevCursor: nil,
      }
    end

    alerts, open_alert_count, closed_alert_count, response, request_error = alert_query_service_with_repositories_from_params.get_alerts_with_response(
      after_cursor:,
      before_cursor:,
      per_page:,
    )

    if request_error.present?
      return render json: {
        message: "Loading secret scanning alerts failed: #{request_error.inspect}",
      }, status: :internal_server_error
    end

    next_cursor = T.let(response&.data&.try(:next_cursor), T.nilable(String))
    next_cursor = Base64.urlsafe_encode64(next_cursor) unless next_cursor.blank?
    prev_cursor = T.let(response&.data&.try(:previous_cursor), T.nilable(String))
    prev_cursor = Base64.urlsafe_encode64(prev_cursor) unless prev_cursor.blank?

    # Calculate the number of alerts actually matching the filter
    alert_count = if parsed_query.is_open_page?
      open_alert_count
    elsif parsed_query.is_closed_page?
      closed_alert_count
    else
      open_alert_count + closed_alert_count
    end

    render json: {
      alerts: SecretScanning::SecurityCampaigns::AlertsSerializer.serialized_alerts(alerts: alerts),
      alertCount: alert_count,
      openCount: open_alert_count,
      closedCount: closed_alert_count,
      nextCursor: next_cursor,
      prevCursor: prev_cursor,
    }
  end
end
