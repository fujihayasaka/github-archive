# typed: strict
# frozen_string_literal: true

require "react_payload"

class Repos::LicensePolicyController < RepositoriesController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index]

  before_action :ensure_can_access_license_policy

  DEFAULT_DISTRIBUTED_POLICY_NAME = "distributed"

  sig { void }
  def index
    response = license_compliance_client.get_combined_repository_policy(
      distribution_policy_name: DEFAULT_DISTRIBUTED_POLICY_NAME,
      repository_id: current_repository.id,
      organization_id: current_repository.owner&.id,
      enterprise_id: current_repository.business_id
    )
    respond_with_react(
      app_name: "license-policy",
      payload: RepositoryLicensePolicyPayload.new(
        repository_id: current_repository.id,
        allowed_licenses: get_allowed_licenses(response.policy),
        packages: get_packages(response.policy),
        date_added: format_date_added(response.policy&.licenses&.first&.added_at),
        has_repo_admin_permissions: Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, current_repository)
      ),
      title: "License Policy · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :license_policy },
      layout: "layouts/repository_settings"
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  # Used to serialize payload that will be served to license policy react app
  class RepositoryLicensePolicyPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repositoryLicensePolicyRoute"
    end

    sig do
      params(
        repository_id: Integer,
        allowed_licenses: T::Array[T::Hash[Symbol, T.untyped]],
        packages: T::Array[T::Hash[Symbol, T.untyped]],
        date_added: String,
        has_repo_admin_permissions: T::Boolean
      ).void
    end
    def initialize(repository_id:, allowed_licenses:, packages:, date_added:, has_repo_admin_permissions:)
      @repository_id = repository_id
      @allowed_licenses = allowed_licenses
      @packages = packages
      @date_added = date_added
      @has_repo_admin_permissions = has_repo_admin_permissions
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        repository_id: @repository_id,
        allowed: @allowed_licenses,
        packages: @packages,
        date_added: @date_added,
        has_repo_admin_permissions: @has_repo_admin_permissions
      }
    end
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::CombinedRepositoryPolicy)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def get_allowed_licenses(policy)
    return [] if policy.nil?
    policy.licenses.map do |license|
      license.to_h.merge(added_at: format_date_added(license.added_at))
    end
  end

  sig { params(policy: T.nilable(OSSLicenseCompliance::V0::CombinedRepositoryPolicy)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
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
  def ensure_can_access_license_policy
    return render_404 unless current_repository
    business = current_repository.owner&.business
    return render_404 unless Permissions::LicensePolicy.is_license_compliance_enabled?(business)
    render_404 unless current_user_can_read_repo?
  end
end
