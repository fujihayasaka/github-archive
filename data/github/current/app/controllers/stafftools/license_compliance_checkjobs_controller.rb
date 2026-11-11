# typed: true
# frozen_string_literal: true

class Stafftools::LicenseComplianceCheckjobsController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:show, :destroy]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Stafftools::LicenseComplianceCheckjobsController#destroy"]

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
    only: [:show, :destroy]

  def show
    response = license_compliance_client.check_status(
      repository_id: current_repository.id,
      number: pull_request_number
    )

    render json: serialize_check_status(response), status: :ok
  rescue OSSLicenseCompliance::Twirp::BaseError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def destroy
    response = license_compliance_client.restart_check_job(
      repository_id: current_repository.id,
      number: pull_request_number
    )

    render json: { success: response.success }, status: :ok
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

  sig { params(response: OSSLicenseCompliance::V0::CheckStatusResponse).returns(Hash) }
  def serialize_check_status(response)
    {
      id: response.id,
      status: response.status.to_s.sub("CHECK_JOB_STATUS_", "").downcase,
      check_started_at: response.check_started_at&.to_time&.iso8601,
      repository_id: response.repository_id,
      organization_id: response.organization_id,
      pull_request_id: response.pull_request_id,
      pull_request_number: response.pull_request_number,
      enterprise_id: response.enterprise_id,
      base_sha: response.base_sha,
      commit_sha: response.commit_sha,
      expected_snapshots: response.expected_snapshots,
      received_snapshots: response.received_snapshots
    }
  end
end
