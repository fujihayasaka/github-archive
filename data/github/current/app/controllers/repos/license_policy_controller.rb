# typed: strict
# frozen_string_literal: true

require "react_payload"

class Repos::LicensePolicyController < RepositoriesController
  include ApplicationController::VerifiedFetchDependency # validates verifiedFetch requests made from react app
  include ApplicationController::JsonDependency # enables JSON payload parsing for controller actions

  # Allow cluster dependency validation for update actions
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::LicensePolicyController#update"
  ].freeze

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
    only: [:index, :update]

  allow_verified_fetch only: [:update]

  before_action :ensure_can_view_repository_license_policy
  before_action :ensure_can_manage_repository_license_policy, only: [:update]
  before_action :parse_json_params, only: [:update]

  DEFAULT_DISTRIBUTED_POLICY_NAME = "distributed"

  sig { void }
  def index
    response = license_compliance_client.get_combined_repository_policy(
      distribution_policy_name: DEFAULT_DISTRIBUTED_POLICY_NAME,
      repository_id: current_repository.id,
      organization_id: current_repository.owner&.id,
      enterprise_id: current_repository.business_id
    )
    business = Business.find_by(id: current_repository.business_id)
    draft_edit_mode_enabled = FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, current_repository, current_repository.business, default: false)

    respond_with_react(
      app_name: "license-policy",
      payload: RepositoryLicensePolicyPayload.new(
        repository_id: current_repository.id,
        allowed_licenses: get_allowed_licenses(response.policy),
        packages: get_packages(response.policy),
        date_added: format_date_added(response.policy&.licenses&.first&.added_at),
        can_manage_license_policy: Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, current_repository),
        enterprise_name: business&.name,
        enterprise_slug: business&.slug,
        draft_edit_mode_enabled: draft_edit_mode_enabled
      ),
      title: "License Policy · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :license_policy },
      layout: "layouts/repository_settings"
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  sig { void }
  def update
    unless FeatureFlag.vexi.enabled?(:dependency_graph_license_compliance_enterprise_overview, current_repository, current_repository.business, default: false)
      render_404
      return
    end

    packages_to_delete = Array(params[:delete_packages]).map do |package|
      {
        name: package[:name],
        package_manager: package[:package_manager]
      }
    end

    license_compliance_client.save_repository_policy(
      repository_id: current_repository.id,
      delete_spdx_ids: params[:delete_spdx_ids],
      delete_packages: packages_to_delete
    )

    render json: {
      success: true,
      repository_id: current_repository.id
    }, status: :ok
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: {
      error: "Failed to save repository policy"
    }, status: :internal_server_error
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
        can_manage_license_policy: T::Boolean,
        enterprise_name: T.nilable(String),
        enterprise_slug: T.nilable(String),
        draft_edit_mode_enabled: T::Boolean
      ).void
    end
    def initialize(repository_id:, allowed_licenses:, packages:, date_added:, can_manage_license_policy:, enterprise_name:, enterprise_slug:, draft_edit_mode_enabled:)
      @repository_id = repository_id
      @allowed_licenses = allowed_licenses
      @packages = packages
      @date_added = date_added
      @can_manage_license_policy = can_manage_license_policy
      @enterprise_name = enterprise_name
      @enterprise_slug = enterprise_slug
      @draft_edit_mode_enabled = draft_edit_mode_enabled
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        repository_id: @repository_id,
        allowed: @allowed_licenses,
        packages: @packages,
        date_added: @date_added,
        can_manage_license_policy: @can_manage_license_policy,
        enterprise_name: @enterprise_name,
        enterprise_slug: @enterprise_slug,
        draft_edit_mode_enabled: @draft_edit_mode_enabled
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
  def ensure_can_view_repository_license_policy
    render_404 unless Permissions::LicensePolicy.can_view_repository_license_policy?(current_user, current_repository)
  end

  sig { void }
  def ensure_can_manage_repository_license_policy
    render_404 unless Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, current_repository)
  end
end
