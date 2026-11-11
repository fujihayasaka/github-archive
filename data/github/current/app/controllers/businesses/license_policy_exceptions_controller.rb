# typed: true
# frozen_string_literal: true

class Businesses::LicensePolicyExceptionsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON payload parsing for controller actions

  # Allow cluster dependency validation for destroy action
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::LicensePolicyExceptionsController#destroy"
  ].freeze

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    only: [:destroy]

  allow_verified_fetch only: [:destroy]
  before_action :ensure_can_manage_enterprise_license_policy
  before_action :parse_json_params, only: [:destroy]

  # Remove package exceptions from the enterprise policy
  # DELETE /enterprises/:slug/settings/advanced_security/license_policy/exceptions
  def destroy
    packages = Array(params[:packages]).map do |package|
      {
        name: package[:name],
        package_manager: package[:package_manager]
      }
    end

    response = license_compliance_client.delete_package_exceptions_from_enterprise_policy(
      enterprise_id: this_business.id,
      packages: packages
    )

    render json: {
      policy: {
        packages: response.policy&.packages&.map(&:to_h) || []
      }
    }, status: :ok
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to delete package exceptions"
    }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { void }
  def ensure_can_manage_enterprise_license_policy
    unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
      render json: { error: "Not found" }, status: :not_found
    end
  end
end
