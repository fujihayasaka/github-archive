# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityProductsController < Orgs::Controller
  include Repos::ListHelper
  include GitHub::Memoizer
  include ApplicationController::JsonDependency
  include EnablementAdvancedSecurityLicenseDependency
  include EnablementFailureCountsDependency
  include EnablementSettingsDependency
  include SecurityConfigurations::RepositoriesDependency
  include ApplicationController::VerifiedFetchDependency
  include Orgs::CustomPropertiesHelper

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  # Access
  before_action :manage_security_products_permission_required
  allow_verified_fetch only: [:in_progress, :refresh, :dismiss_failure_banner, :actions_runners_labels]
  before_action :parse_json_params, only: [:in_progress]

  # allow us to render more than 100 pages of alerts
  skip_before_action :cap_pagination, only: :index, unless: :robot?

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
    only: [:index, :refresh, :actions_runners_labels]

  sig { void }
  def index
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: current_organization)

    repos = serialized_repos
    render_react_app(
      payload: default_payload.merge({
        githubRecommendedConfiguration: serialized_github_recommended_configuration,
        customSecurityConfigurations: serialized_security_configurations,
        customEnterpriseSecurityConfigurations: serialized_enterprise_security_configurations,
        customPropertySuggestions: definitions_payload(definitions_manager.get_definitions),
        repositories: repos[:repositories],
        totalRepositoryCount: repos[:total_repository_count],
        pageCount: repos[:page_count],
        showInfoBanner: show_info_banner?,
        showTalkToUsBanner: show_talk_to_us_banner?,
        licenses: org_license_payload(current_organization),
        failureCounts: failure_counts,
      }),
      title: "Settings · Security configurations · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
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
      customEnterpriseSecurityConfigurations: serialized_enterprise_security_configurations,
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

  def dismiss_failure_banner # rubocop:disable GitHub/UseRestfulActions
    failure_timestamp = latest_failure_timestamp
    return head(:no_content) if failure_timestamp.nil?

    SecurityProductsEnablement::KV.set(user_dismissed_banner_for_org_key, failure_timestamp)
    head :created
  end

  def actions_runners_labels # rubocop:disable GitHub/UseRestfulActions
    render json: { labels: SecurityProductsEnablement::Actions::RunnerChecker.new(current_organization).labels }
  end

  private

  memoize def security_configurations
    SecurityConfiguration.where(target_type: "User", target: current_organization).order(:id)
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def github_recommended_configuration
    SecurityConfiguration.github_recommended_configuration
  end

  memoize def enterprise_security_configurations
    return [] unless enterprise_security_configurations?

    owner = current_organization.business
    return [] if owner.nil?

    SecurityConfiguration.where(target: owner).order(:id)
  end

  def serialized_github_recommended_configuration
    security_configuration_serializer.serialize(github_recommended_configuration) if github_recommended_configuration
  end

  def serialized_security_configurations
    security_configuration_serializer.serialize_collection(security_configurations.to_a)
  end

  def serialized_enterprise_security_configurations
    security_configuration_serializer.serialize_collection(enterprise_security_configurations.to_a)
  end

  def serialized_repos(repository_ids: nil)
    search_query = params[:q] || ""
    serialized_repositories(organization: current_organization, user: T.must(current_user), user_session:, cap_filter:, repository_ids: repository_ids, search_query:, current_page:)
  end

  sig { returns(CustomPropertiesDefinitionsManager) }
  def definitions_manager
    CustomProperties::Public.definitions_manager(current_organization)
  end

  sig { returns(T::Boolean) }
  def show_info_banner?
    # On GHES we never want to show the GHAS upsell banner
    return false if GitHub.enterprise? || current_user.nil?

    paid_org = current_organization.advanced_security_purchased? ||
      current_organization.code_security_purchased? ||
      current_organization.secret_protection_purchased?

    !paid_org && !T.must(current_user).dismissed_notice?(UserNotice::SECURITY_CONFIGURATIONS_NON_GHAS_ORG_INFO_NOTICE)
  end

  sig { returns(T::Boolean) }
  def show_talk_to_us_banner?
    return false if show_info_banner?
    return false unless user = current_user
    user.feature_enabled?(:security_configurations_talk_to_us_banner) &&
      !user.dismissed_notice?(UserNotice::SECURITY_CONFIGURATIONS_TALK_TO_US_NOTICE)
  end
end
