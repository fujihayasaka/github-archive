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
    only: [:index]

  before_action :edit_permissions_required

  def index
    response = license_compliance_client.get_enterprise_policy(enterprise_id: this_business.id)
    respond_with_react(
      app_name: "license-policy",
      payload: EnterpriseLicensePolicyPayload.new(
        this_business.id,
        get_allowed_licenses(response.policy),
        get_packages(response.policy),
        format_date_added(response.policy&.created_at)
      ),
      title: "License Policy · #{this_business.name}",
      page_data: { selected_link: :business_license_policy_settings, sidebar: :policies },
      layout: "react_business",
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

    def initialize(enterprise_id, allowed, packages, date_added)
      @enterprise_id = enterprise_id
      @allowed = allowed
      @packages = packages
      @date_added = date_added
    end

    def payload
      {
        enterprise_id: @enterprise_id,
        allowed: @allowed,
        packages: @packages,
        date_added: @date_added
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
    policy.licenses&.allowed&.map do |license|
      license.to_h.merge(added_at: format_date_added(license.added_at))
    end || []
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::EnterprisePolicy)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_packages(policy)
    return [] if policy.nil?
    policy.packages.map do |package|
      package.to_h.merge(added_at: format_date_added(package.added_at))
    end
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
    return false unless this_business.feature_flag_enabled?(:dependency_graph_license_compliance, default: false)
    Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, this_business)
  end
end
