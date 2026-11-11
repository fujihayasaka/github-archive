# typed: true
# frozen_string_literal: true

class Businesses::LicensePolicyLicensesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON payload parsing for controller actions

  # Allow cluster dependency validation for update and destroy actions
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::LicensePolicyLicensesController#update",
    "Businesses::LicensePolicyLicensesController#destroy"
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
    only: [:update, :destroy]

  allow_verified_fetch only: [:update, :destroy]
  before_action :ensure_can_manage_enterprise_license_policy
  before_action :parse_json_params, only: [:update, :destroy]

  # Add licenses to the enterprise policy
  # PUT /enterprises/:slug/settings/advanced_security/license_policy/licenses
  def update
    response = license_compliance_client.add_licenses_to_enterprise_policy(
      enterprise_id: this_business.id,
      spdx_ids: params[:spdx_ids],
      context: params[:context],
      user_id: current_user.id
    )

    render json: {
      allowed: get_allowed_licenses(response.policy),
      date_added: format_date_added(response.policy&.created_at)
    }, status: :ok
  rescue OSSLicenseCompliance::Twirp::InvalidSPDXIdentifiersError => err
    Failbot.report(err)
    render json: { error: err.msg }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to add licenses to enterprise policy"
    }, status: :internal_server_error
  end

  # Remove licenses from the enterprise policy
  # DELETE /enterprises/:slug/settings/advanced_security/license_policy/licenses
  def destroy
    response = license_compliance_client.delete_licenses_from_enterprise_policy(
      enterprise_id: this_business.id,
      spdx_ids: params[:spdx_ids],
      context: params[:context]
    )

    render json: {
      allowed: get_allowed_licenses(response.policy),
      date_added: format_date_added(response.policy&.created_at)
    }, status: :ok
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to delete licenses from enterprise policy"
    }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::EnterprisePolicy)).returns(T::Array[String]) }
  def get_allowed_licenses(policy)
    return [] if policy.nil?
    # NOTE: this ignores distribution contexts for now. Any license that is allowed
    # in any context will be returned.
    policy.licenses&.allowed&.map(&:spdx_id) || []
  end

  sig { params(date: T.nilable(Google::Protobuf::Timestamp)).returns(String) }
  def format_date_added(date)
    return "" if date.nil?
    date.to_time.strftime("%B %d, %Y")
  end

  sig { void }
  def ensure_can_manage_enterprise_license_policy
    unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
      render json: { error: "Not found" }, status: :not_found
    end
  end
end
