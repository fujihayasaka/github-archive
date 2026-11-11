# typed: true
# frozen_string_literal: true

class Businesses::LicensePolicyController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app

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
    only: [:index]

  before_action :ensure_can_view_enterprise_license_policy

  def index
    unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, this_business, default: false)
      redirect_to settings_single_license_policy_enterprise_path(this_business)
      return
    end

    response = license_compliance_client.get_enterprise_policy(enterprise_id: this_business.id)
    can_manage_license_policy = ::Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)

    # Mirrors the gates on Businesses::EnterpriseRolesController#index
    # (`/enterprises/:slug/enterprise_roles`):
    #   - `custom_enterprise_roles_enabled` before_action -> `custom_enterprise_roles_supported?`
    #   - `read_enterprise_roles_required` before_action -> `read_enterprise_custom_enterprise_role` FGP
    can_read_enterprise_roles = this_business.custom_enterprise_roles_supported? &&
      Authz.domain.check_allowed(current_user, :read_enterprise_custom_enterprise_role, this_business)

    # Mirrors the before_actions on Businesses::CodeRulesetsController#ruleset_index
    # (`/enterprises/:slug/settings/policies/code`):
    #   - `business_owner_required`
    #   - `business_not_downgraded_to_free_plan_required`
    #   - `business_full_plan_required`
    can_view_code_policies = this_business.owner?(current_user) &&
      !this_business.downgraded_to_free_plan? &&
      this_business.seats_plan_full?

    respond_with_react(
      app_name: "license-policy",
      payload: EnterpriseLicensePolicyPayload.new(
        this_business.id,
        get_allowed_licenses(response.policy),
        get_packages(response.policy),
        format_date_added(response.policy&.created_at),
        can_manage_license_policy,
        can_read_enterprise_roles,
        can_view_code_policies
      ),
      title: "License compliance · #{this_business.name}",
      page_data: { selected_link: :business_license_policy_settings, sidebar: :policies },
      layout: "react_business"
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  # Used to serialize payload that will be served to license policy react app
  class EnterpriseLicensePolicyPayload < ReactPayload::Base
    def route_id
      "enterpriseLicensePolicyRoute"
    end

    def initialize(enterprise_id, allowed, packages, date_added, can_manage_license_policy, can_read_enterprise_roles, can_view_code_policies)
      @enterprise_id = enterprise_id
      @allowed = allowed
      @packages = packages
      @date_added = date_added
      @can_manage_license_policy = can_manage_license_policy
      @can_read_enterprise_roles = can_read_enterprise_roles
      @can_view_code_policies = can_view_code_policies
    end

    def payload
      {
        enterprise_id: @enterprise_id,
        allowed: @allowed,
        packages: @packages,
        date_added: @date_added,
        can_manage_license_policy: @can_manage_license_policy,
        can_read_enterprise_roles: @can_read_enterprise_roles,
        can_view_code_policies: @can_view_code_policies
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
end
