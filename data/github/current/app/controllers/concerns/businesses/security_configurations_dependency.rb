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

    # Override malware_alerts availability based on FF check with business actor
    if payload.dig(:securityProducts, :dependabot_alerts, :malware_alerts, :availability) == :available
      unless FeatureFlag.vexi.enabled?("dependabot_allow_malware_frontend", current_user, this_business, default: false)
        payload[:securityProducts][:dependabot_alerts][:malware_alerts][:availability] = :unavailable
      end
    end

    payload[:capabilities][:enterpriseOwned] = true
    payload[:capabilities][:ghasForUserRepositories] = AdvancedSecurity::Features::Business::AdvancedSecurity.new(this_business).feature_available_for_user_repositories?
    payload[:capabilities][:advancedSecurity] = {
      bundled: this_business.advanced_security_products_bundled?,
      metered: this_business.advanced_security_products_metered?,
      purchased: this_business.advanced_security_purchased? ||
        this_business.code_security_purchased? ||
        this_business.secret_protection_purchased?,
      codeSecurityPurchased: this_business.code_security_purchased?,
      secretProtectionPurchased: this_business.secret_protection_purchased?,
      codeSecurityEnablementLocked: this_business.code_security_metered_usage_locked?,
      secretProtectionEnablementLocked: this_business.secret_protection_metered_usage_locked?,
      advancedSecurityEnablementLocked: this_business.advanced_security_metered_usage_locked?,
    }

    payload.merge({
      renderContext: "enterprise",
      enterprise: { id: this_business.id, slug: this_business.slug, name: this_business.name },
      changesInProgress: changes_in_progress,
      helperUrls: {
        suggestedBypassReviewersUrl: suggestions_secret_scanning_push_protection_delegated_bypass_reviewers_path(this_business.display_login),
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

  def org_failures
    enterprise_config_ids = SecurityConfiguration \
      .where(target: this_business)
      .or(SecurityConfiguration.where(target_type: "global", target_id: 0))
      .ids

    # Query failures without filtering by org IDs to avoid loading all org IDs into memory,
    # which can be very slow for enterprises with tens of thousands of orgs.
    # Instead, we query failures first (small result set), then verify org membership.
    all_failed_configs = RepositorySecurityConfiguration.where(
      security_configuration_id: enterprise_config_ids,
      state: :failed,
    ).group(:organization_id).count

    return {} if all_failed_configs.blank?

    # Verify which failed orgs belong to this business and fetch logins for the response
    # "name" field. Cross-cluster constraint: RepositorySecurityConfiguration (Notify) and
    # Organization (Users) can't be joined, so we use two queries joined in Ruby.
    failed_orgs = this_business.organizations.where(id: all_failed_configs.keys).pluck(:id, :login).to_h

    failed_configs = all_failed_configs.select { |org_id, _| failed_orgs.key?(org_id) }

    return {} if failed_configs.blank?

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
