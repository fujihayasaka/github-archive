# typed: true
# frozen_string_literal: true

class Businesses::LicensePolicyController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON payload parsing for controller actions

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::LicensePolicyController#create"
  ].freeze

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]
  before_action :edit_permissions_required

  def index
    response = license_compliance_client.get_enterprise_policy(enterprise_id: this_business.id)
    respond_with_react(
      app_name: "license-policy",
      payload: LicensePolicyPayload.new(
        this_business.id,
        get_allowed_licenses(response.policy),
        format_date_added(response.policy&.created_at)
      ),
      title: "License Policy · #{this_business.name}",
      page_data: { selected_link: :business_license_policy_settings, sidebar: :policies },
      layout: "react_business",
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    ## TODO: Create a custom error page (message) for license policy
    render_404
  end

  def create
    licenses = params[:licenses][:allowed].map do |license|
      {
        spdx_id: license[:spdx_id],
        contexts: license[:contexts]
      }
    end

    response = license_compliance_client.create_enterprise_policy(
      enterprise_id: this_business.id,
      licenses: { allowed: licenses }
    )

    render json: {
      allowed: get_allowed_licenses(response.policy),
      date_added: format_date_added(response.policy&.created_at)
    }, status: :ok

  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to create enterprise policy: #{err.message}"
    }, status: :internal_server_error
  end

  # Used to serialize payload that will be served to license policy react app
  class LicensePolicyPayload < ReactPayload::Base
    def route_id
      "licensePolicyRoute"
    end

    def initialize(enterprise_id, allowed, date_added)
      @enterprise_id = enterprise_id
      @allowed = allowed
      @date_added = date_added
    end

    def payload
      {
        enterprise_id: @enterprise_id,
        allowed: @allowed,
        date_added: @date_added
      }
    end
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
  def edit_permissions_required
    render_404 unless can_manage_enterprise_license_policy?
  end

  sig { returns(T::Boolean) }
  def can_manage_enterprise_license_policy?
    async_can_manage_enterprise_license_policy?.sync
  end

  # Checks if current user is authorized to edit license policy
  # A user is authorized if they are 1. admin of enterprise or 2. have been granted the manage_enterprise_license_policy fgp
  sig { returns(Promise[T::Boolean]) }
  def async_can_manage_enterprise_license_policy?
    return Promise.resolve(T.let(false, T::Boolean)) unless this_business.feature_flag_enabled?(:dependency_graph_license_compliance, default: false)

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :manage_enterprise_license_policy,
      actor: current_user,
      subject: this_business,
    ).then(&:allow?)
  end
end
