# typed: true
# frozen_string_literal: true

class Stafftools::LicenseComplianceAlertsController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:show]

  before_action :ensure_org_not_user
  before_action :ensure_repo_exists
  before_action :ensure_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:show]

  def show
    response = license_compliance_client.get_alerts_for_pull_request(
      repository_id: current_repository.id,
      number: pull_request_number
    )

    render json: { alerts: response.alerts.map { |alert| serialize_alert(alert) } }, status: :ok
  rescue OSSLicenseCompliance::Twirp::BaseError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { void }
  def ensure_feature_enabled
    repo = current_repository
    unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance, repo, repo.owner, repo.business, default: false)
      render_404
    end
  end

  sig { returns(Integer) }
  def pull_request_number
    params[:pull_request_number].to_i
  end

  sig { params(alert: OSSLicenseCompliance::V0::Alert).returns(Hash) }
  def serialize_alert(alert)
    {
      id: alert.id,
      number: alert.number,
      status: alert.status.to_s.sub("ALERT_STATUS_", "").downcase,
      resolution: alert.resolution.to_s.sub("ALERT_RESOLUTION_", "").downcase,
      created_at: alert.created_at&.to_time&.iso8601,
      repository_id: alert.repository_id,
      organization_id: alert.organization_id,
      enterprise_id: alert.enterprise_id,
      manifest_name: alert.manifest_name,
      manifest_line_number: alert.manifest_line_number,
      package_ecosystem: alert.package_ecosystem.to_s.sub("PACKAGE_MANAGER_", "").downcase,
      package_name: alert.package_name,
      package_version: alert.package_version,
      license: alert.license,
      pull_request_number: alert.pull_request_number
    }
  end
end
