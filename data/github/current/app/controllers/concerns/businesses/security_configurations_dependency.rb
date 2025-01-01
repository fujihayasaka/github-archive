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
    payload[:securityProducts][:code_scanning][:runnerLabels] = SecurityProductsEnablement::Actions::RunnerChecker.new(this_business).labels
    payload[:capabilities][:ghasPurchased] = this_business.advanced_security_purchased?
    payload[:capabilities][:enterpriseOwned] = true
    payload[:capabilities][:ghasForUserRepositories] = AdvancedSecurity::Features::Business::AdvancedSecurity.new(this_business).feature_available_for_user_repositories?
    payload.merge({
      renderContext: "enterprise",
      enterprise: { slug: this_business.slug, name: this_business.name },
      changesInProgress: changes_in_progress,
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

  def org_failures
    enterprise_config_ids = SecurityConfiguration \
      .where(target: this_business)
      .or(SecurityConfiguration.where(target_type: "global"))
      .ids

    # Filtering by `this_business.organizations.ids` can be very slow if there are tens of thousands of orgs
    # on GHES, we can safely skip this check since we only have one business
    failed_configs = if GitHub.single_business_environment?
      RepositorySecurityConfiguration.where(
        security_configuration_id: enterprise_config_ids,
        state: :failed,
      ).group(:organization_id).count
    else
      RepositorySecurityConfiguration.where(
        security_configuration_id: enterprise_config_ids,
        state: :failed,
        organization_id: this_business.organizations.ids,
      ).group(:organization_id).count
    end

    return {} if failed_configs.blank?

    failed_orgs = this_business.organizations.where(id: failed_configs.keys).pluck(:id, :login).to_h

    {
      totalRepoFailures: failed_configs.values.sum,
      orgs: failed_configs.collect do |org_id, failure_count|
        { name: failed_orgs[org_id], repoFailures: failure_count }
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
end
