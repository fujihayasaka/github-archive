# typed: true
# frozen_string_literal: true

module Businesses::SecurityConfigurationsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer
  include SharedSecurityConfigurationsDependency

  requires_ancestor { Businesses::BusinessController }

  private

  def default_payload
    payload = shared_default_payload

    payload[:capabilities][:enterpriseOwned] = true
    payload[:capabilities][:ghasForUserRepositories] = AdvancedSecurity::Features::Business::AdvancedSecurity.new(this_business).feature_available_for_user_repositories?
    payload[:capabilities][:advancedSecurity] = advanced_security_capability(this_business)

    payload.merge({
      renderContext: "enterprise",
      enterprise: { id: this_business.id, slug: this_business.slug, name: this_business.name },
      changesInProgress: changes_in_progress,
      helperUrls: {
        suggestedBypassersUrl: suggestions_secret_scanning_push_protection_bypassers_path(this_business.display_login),
      }
    })
  end

  def serialized_github_recommended_configuration
    security_configuration_serializer.serialize(github_recommended_configuration) if github_recommended_configuration
  end

  sig { returns(SecurityProductsEnablement::SecurityConfigurationSerializer) }
  memoize def security_configuration_serializer
    SecurityProductsEnablement::SecurityConfigurationSerializer.new(this_business)
  end

  memoize def enterprise_security_configurations
    SecurityConfiguration.where(target: this_business).order(:id)
  end

  def serialized_enterprise_security_configurations
    security_configuration_serializer.serialize_collection(enterprise_security_configurations.to_a)
  end

  GLOBAL_CONFIG_JOIN_REPO_THRESHOLD = 100_000

  def global_config_join_repo_threshold
    GLOBAL_CONFIG_JOIN_REPO_THRESHOLD
  end

  # Adapts the GHR failure query strategy based on the business's data shape. The GitHub
  # Recommended Configuration (GHR) is shared across all businesses, so a single-query approach
  # returns failures for every org on the platform. For businesses whose repo count is smaller
  # than the GHR failure count, we JOIN on repository_security_center_configs to scope by
  # business_id — MySQL drives from the smaller side using the (repository_id) unique key on
  # rscc and the (business_id, ...) index to filter. For businesses with more repos than GHR
  # failures, the JOIN offers no advantage, so we fall back to the unscoped query which uses
  # the (security_configuration_id, state) index on repository_security_configurations.
  def org_failures
    ghr = github_recommended_configuration

    if ghr.nil?
      return org_failures_unscoped(include_ghr: false)
    end

    unless FeatureFlag.vexi.enabled?(:security_configs_enterprise_skip_repo_count_check, this_business, default: false)
      business_repo_count = RepositorySecurityCenterConfig.where(business_id: this_business.id).count
      if business_repo_count >= global_config_join_repo_threshold
        return org_failures_unscoped
      end
    end

    enterprise_config_ids = SecurityConfiguration.where(target: this_business).ids

    # Enterprise-owned configs: failures are naturally scoped to this business's orgs
    failed_configs = if enterprise_config_ids.present?
      RepositorySecurityConfiguration.where(
        security_configuration_id: enterprise_config_ids,
        state: :failed,
      ).group(:organization_id).count
    else
      {}
    end

    # GitHub recommended config: JOIN on repository_security_center_configs to scope by business_id
    ghr_failures = RepositorySecurityConfiguration
      .joins(:repository_security_center_config)
      .where(
        security_configuration_id: ghr.id,
        state: :failed,
      )
      .where(repository_security_center_configs: { business_id: this_business.id })
      .group(:organization_id).count

    ghr_failures.each do |org_id, count|
      failed_configs[org_id] = (failed_configs[org_id] || 0) + count
    end

    filter_and_build_org_failures(failed_configs)
  end

  # Queries failures without scoping by business — used when there's no GHR config or when
  # the business is too large for the JOIN strategy to be efficient.
  # When include_ghr is false, only enterprise-owned configs are queried (no global GHR).
  def org_failures_unscoped(include_ghr: true)
    scope = SecurityConfiguration.where(target: this_business)
    scope = scope.or(SecurityConfiguration.where(target_type: "global", target_id: 0)) if include_ghr
    enterprise_config_ids = scope.ids

    all_failed_configs = RepositorySecurityConfiguration.where(
      security_configuration_id: enterprise_config_ids,
      state: :failed,
    ).group(:organization_id).count

    if include_ghr
      filter_and_build_org_failures_preloaded(all_failed_configs)
    else
      filter_and_build_org_failures(all_failed_configs)
    end
  end

  # Filters failed config counts to orgs belonging to this business,
  # fetches org logins via cross-cluster lookup, and builds the response hash.
  def filter_and_build_org_failures(failed_configs)
    return {} if failed_configs.blank?

    failed_orgs = this_business.organizations.where(id: failed_configs.keys).pluck(:id, :login).to_h
    failed_configs = failed_configs.select { |org_id, _| failed_orgs.key?(org_id) }

    return {} if failed_configs.blank?

    {
      totalRepoFailures: failed_configs.values.sum,
      orgs: failed_configs.collect do |org_id, failure_count|
        { name: failed_orgs[org_id], repoFailures: failure_count }
      end
    }
  end

  # Pre-loads business org IDs and filters in Ruby to avoid an
  # unbounded WHERE IN (...) cross-cluster query.
  def filter_and_build_org_failures_preloaded(failed_configs)
    return {} if failed_configs.blank?

    business_org_ids = Set.new(this_business.organizations.pluck(:id))
    scoped_configs = failed_configs.select { |org_id, _| business_org_ids.include?(org_id) }

    return {} if scoped_configs.blank?

    org_logins = this_business.organizations.where(id: scoped_configs.keys).pluck(:id, :login).to_h
    scoped_configs = scoped_configs.select { |org_id, _| org_logins.key?(org_id) }

    return {} if scoped_configs.blank?

    {
      totalRepoFailures: scoped_configs.values.sum,
      orgs: scoped_configs.collect do |org_id, failure_count|
        { name: org_logins[org_id], repoFailures: failure_count }
      end
    }
  end

  sig { returns(SecurityConfiguration) }
  memoize def security_configuration
    find_security_configuration([this_business])
  end

  def changes_in_progress
    blocked_settings = BlockedSettings.new(this_business).any?
    configs_applying = SecurityProductsEnablement::JobProgressTracker.business_jobs_running?(this_business.id)

    if blocked_settings
      { inProgress: true, type: "enablement_changes" }
    elsif configs_applying
      { inProgress: true, type: "applying_configuration" }
    else
      { inProgress: false }
    end
  end

  # before_action helper to return an HTTP 422 if the business is currently applying or blocking configs.
  sig { void }
  def prevent_duplicate_enablement_events
    if this_business.security_configurations_applying_or_blocked?
      render json: {
        error: "Another enablement event is in progress and your changes could not be saved. Please try again later."
      }, status: :unprocessable_entity
    end
  end
end
