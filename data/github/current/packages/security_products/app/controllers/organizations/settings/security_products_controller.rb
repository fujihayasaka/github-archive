# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityProductsController < Orgs::Controller
  extend T::Sig
  include ReactHelper
  include Repos::ListHelper
  include GitHub::Memoizer
  include ApplicationController::JsonDependency
  include EnablementAdvancedSecurityLicenseDependency
  include EnablementSettingsDependency
  include Settings::SecurityProducts::RepositoriesHelper
  include ApplicationController::VerifiedFetchDependency
  include Orgs::CustomPropertiesHelper

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  # Access
  before_action :manage_security_products_permission_required
  allow_verified_fetch only: [:in_progress, :refresh]
  before_action :parse_json_params, only: [:in_progress, :refresh]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index, :refresh]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Organizations::Settings::SecurityProductsController#refresh"
  ]

  ENABLEMENT_FAILURES_JSON_PATH = Rails.root.join("config", "code_security_configuration_failures.json")
  ENABLEMENT_FAILURES_MAP = begin
    T.let(
      JSON.parse(File.read(ENABLEMENT_FAILURES_JSON_PATH))["failures"],
      T::Hash[String, T.untyped]
    )
  rescue JSON::ParserError, Errno::ENOENT => e
    Failbot.report(e)
    {}
  end

  sig { void }
  def index
    add_client_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS,
      entity: current_organization)

    repos = serialized_repos
    render_react_app(
      payload: default_payload.merge({
        githubRecommendedConfiguration: serialized_github_recommended_configuration,
        customSecurityConfigurations: serialized_security_configurations,
        customPropertySuggestions: definitions_payload(definitions_manager.get_definitions),
        repositories: repos[:repositories],
        totalRepositoryCount: repos[:total_repository_count],
        pageCount: repos[:page_count],
        showInfoBanner: show_info_banner?,
        licenses: org_license_payload(current_organization),
        failureCounts: failure_counts,
      }),
      title: "Settings · Code security · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
      ssr: true,
    )
  end

  # Returns information about ongoing changes if there are any
  # Ex. If enablement changes are in progress, return { inProgress: true, type: "enablement_changes" }
  #
  def in_progress # rubocop:disable GitHub/UseRestfulActions
    repository_ids = if params[:repository_ids].present?
      current_organization.repositories.active.where(id: params[:repository_ids]).pluck(:id)
    end

    changes = changes_in_progress
    if repository_ids.present?
      repo_security_configs = RepositorySecurityConfiguration.where(repository_id: repository_ids).includes(:security_configuration)
      repository_statuses = {}
      repo_security_configs.each do |config|
        repository_statuses[config.repository_id] = {
          name: config.security_configuration.name,
          status: config.state,
        }
      end

      render json: changes.merge({ repositoryStatuses: repository_statuses })
    else
      render json: changes
    end
  end

  def refresh # rubocop:disable GitHub/UseRestfulActions
    response = {
      githubRecommendedConfiguration: serialized_github_recommended_configuration,
      customSecurityConfigurations: serialized_security_configurations,
      failureCounts: failure_counts,
      licenses: org_license_payload(current_organization),
    }.merge(changes_in_progress)

    # If repository IDs are provided, include repositoryStatuses for each of them:
    if params[:repository_ids].present?
      repository_ids = current_organization.repositories.active.where(id: params[:repository_ids]).pluck(:id)
      serialized_repos = serialized_repos(repository_ids: repository_ids)

      response.merge!({
        totalRepositoryCount: serialized_repos[:total_repository_count],
        repositories: serialized_repos[:repositories]
      })
    end

    render json: response
  end

  private

  memoize def security_configurations
    SecurityConfiguration.where(target_type: "User", target: current_organization).order(:id)
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def github_recommended_configuration
    SecurityConfiguration.github_recommended_configuration
  end

  def serialized_github_recommended_configuration
    security_configuration_serializer.serialize(github_recommended_configuration) if github_recommended_configuration
  end

  def serialized_security_configurations
    security_configuration_serializer.serialize_collection(security_configurations.to_a)
  end

  def serialized_repos(repository_ids: nil)
    serialized_repositories(organization: current_organization, user: T.must(current_user), user_session:, cap_filter:, repository_ids: repository_ids)
  end

  sig { returns(CustomPropertiesDefinitionsManager) }
  def definitions_manager
    CustomProperties::Public.definitions_manager(current_organization)
  end

  sig { returns(T::Boolean) }
  def show_info_banner?
    # On GHES we never want to show the GHAS upsell banner
    return false if GitHub.enterprise? || current_user.nil?

    !current_organization.advanced_security_purchased? &&
    !T.must(current_user).dismissed_notice?(UserNotice::SECURITY_CONFIGURATIONS_NON_GHAS_ORG_INFO_NOTICE)
  end

  def failure_counts
    # Failsafe if ENABLEMENT_FAILURES_MAP isn't loaded:
    return {} if ENABLEMENT_FAILURES_MAP.blank?

    full_counts = RepositorySecurityConfiguration.where(
      organization_id: current_organization.id,
      state: :failed
    ).group(:failure_reason).count

    # If we have nil failure_reasons, replace them with the text "Unknown":
    if full_counts[nil].present?
      full_counts["Unknown"] = full_counts.delete(nil)
    end

    # To ensure we consolodate all the counts correctly, reference the front-end failure reason and combine as needed:
    counts = full_counts.reduce({}) do |memo, (reason, count)|
      banner_reason = ENABLEMENT_FAILURES_MAP.dig(reason, "frontend_banner_reason") \
        || ENABLEMENT_FAILURES_MAP.dig("Unknown", "frontend_banner_reason")

      memo[banner_reason] ||= 0
      memo[banner_reason] += count
      memo
    end

    counts
  end
end
