# typed: true
# frozen_string_literal: true

class Businesses::SingleLicensePolicyController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON payload parsing for controller actions

  # Allow cluster dependency validation for update actions
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::SingleLicensePolicyController#update",
    "Businesses::SingleLicensePolicyController#validate"
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
    ApplicationRecord::Authnd,
    only: [:index, :update, :validate]

  allow_verified_fetch only: [:update, :validate]

  before_action :ensure_can_view_enterprise_license_policy
  before_action :ensure_can_manage_enterprise_license_policy, only: [:update, :validate]
  before_action :parse_json_params, only: [:update, :validate]

  def index
    response = license_compliance_client.get_enterprise_policy(enterprise_id: this_business.id)
    can_manage_license_policy = ::Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
    enterprise_overview_enabled = FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, this_business, default: false)
    respond_with_react(
      app_name: "license-policy",
      payload: EnterpriseLicensePolicyPayload.new(
        this_business.id,
        get_allowed_licenses(response.policy),
        get_packages(response.policy),
        format_date_added(response.policy&.created_at),
        can_manage_license_policy,
        enterprise_overview_enabled
      ),
      title: "License compliance · #{this_business.name}",
      page_data: { selected_link: :business_license_policy_settings, sidebar: :policies },
      layout: "react_business"
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  def update
    unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, this_business, default: false)
      render_404
      return
    end

    packages_to_add = Array(params[:add_packages]).map do |package|
      {
        name: package[:name],
        package_manager: package[:package_manager]
      }
    end

    packages_to_delete = Array(params[:delete_packages]).map do |package|
      {
        name: package[:name],
        package_manager: package[:package_manager]
      }
    end

    response = license_compliance_client.save_enterprise_policy(
      enterprise_id: this_business.id,
      context: params[:context],
      user_id: current_user.id,
      add_spdx_ids: params[:add_spdx_ids],
      delete_spdx_ids: params[:delete_spdx_ids],
      add_packages: packages_to_add,
      delete_packages: packages_to_delete
    )

    if response.failed_spdx_ids.any?
      render json: {
        success: true,
        business_id: this_business.id,
        failed_spdx_ids: response.failed_spdx_ids.to_a
      }, status: :ok
    else
      render json: {
        success: true,
        business_id: this_business.id
      }, status: :ok
    end
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to save enterprise policy"
    }, status: :internal_server_error
  end

  def validate # rubocop:todo GitHub/UseRestfulActions
    unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, this_business, default: false)
      render_404
      return
    end

    spdx_ids = params[:spdx_ids]
    if spdx_ids.blank?
      render json: { error: "spdx_ids is required" }, status: :unprocessable_entity
      return
    end

    response = license_compliance_client.validate_licenses(spdx_ids: spdx_ids)

    render json: {
      success: true,
      valid_spdx_ids: response.valid_spdx_ids.to_a,
      invalid_spdx_ids: response.invalid_spdx_ids.to_a
    }, status: :ok
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to validate licenses"
    }, status: :internal_server_error
  end

  # Used to serialize payload that will be served to license policy react app
  class EnterpriseLicensePolicyPayload < ReactPayload::Base
    def route_id
      "enterpriseSingleLicensePolicyRoute"
    end

    def initialize(enterprise_id, allowed, packages, date_added, can_manage_license_policy, enterprise_overview_enabled)
      @enterprise_id = enterprise_id
      @allowed = allowed
      @packages = packages
      @date_added = date_added
      @can_manage_license_policy = can_manage_license_policy
      @enterprise_overview_enabled = enterprise_overview_enabled
    end

    def payload
      {
        enterprise_id: @enterprise_id,
        allowed: @allowed,
        packages: @packages,
        date_added: @date_added,
        can_manage_license_policy: @can_manage_license_policy,
        enterprise_overview_enabled: @enterprise_overview_enabled
      }
    end
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::EnterprisePolicy)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_allowed_licenses(policy)
    return [] if policy.nil?
    # NOTE: this ignores distribution contexts for now. Any license that is allowed
    # in any context will be returned.
    policy.distribution_policies.flat_map do |dist_policy|
      dist_policy.licenses&.allowed&.map do |license|
        license.to_h.merge(added_at: format_date_added(license.added_at))
      end || []
    end
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::EnterprisePolicy)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_packages(policy)
    return [] if policy.nil?
    # NOTE: this ignores distribution contexts for now. Any package that is allowed
    # in any context will be returned.
    policy.distribution_policies.flat_map do |dist_policy|
      dist_policy.packages.map do |package|
        package.to_h.merge(added_at: format_date_added(package.added_at))
      end
    end
  end

  sig { params(date: T.nilable(Google::Protobuf::Timestamp)).returns(String) }
  def format_date_added(date)
    return "" if date.nil?
    date.to_time.strftime("%B %d, %Y")
  end

  sig { void }
  def ensure_can_view_enterprise_license_policy
    render_404 unless Permissions::LicensePolicy.can_view_enterprise_license_policy?(current_user, this_business)
  end

  sig { void }
  def ensure_can_manage_enterprise_license_policy
    render_404 unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
  end
end
