# typed: true
# frozen_string_literal: true

class Repos::LicensePolicyLicensesController < RepositoriesController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:destroy]
  before_action :ensure_can_manage_repository_license_policy
  before_action :parse_json_params, only: [:destroy]

  # Remove licenses from the repository policy
  # DELETE /:owner/:repo/security/advanced_security/license_policy/licenses
  def destroy
    response = license_compliance_client.delete_licenses_from_repository_policy(
      repository_id: current_repository.id,
      spdx_ids: params[:spdx_ids]
    )

    render json: { success: true }
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to delete licenses from repository policy"
    }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { void }
  def ensure_can_manage_repository_license_policy
    unless Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, current_repository)
      render json: { error: "Not found" }, status: :not_found
    end
  end
end
