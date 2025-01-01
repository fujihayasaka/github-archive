# typed: true
# frozen_string_literal: true

module EnablementSettingsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer
  include SharedSecurityConfigurationsDependency

  requires_ancestor { Orgs::Controller }

  private

  sig { returns(Hash) }
  def default_payload
    payload = shared_default_payload
    payload[:capabilities][:enterpriseOwned] = current_organization.business.present?
    payload[:capabilities][:ghasPurchased] = current_organization.advanced_security_purchased?
    payload[:capabilities][:hasTeams] = current_organization.teams_for(current_organization).any?
    payload[:securityProducts][:code_scanning][:runnerLabels] = SecurityProductsEnablement::Actions::RunnerChecker.new(current_organization).labels
    payload.merge({
      renderContext: "organization",
      changesInProgress: changes_in_progress,
      channel: GitHub::WebSocket::Channels.signed_security_configurations_update(current_organization),
      newRepoDefaults: security_configuration_serializer.new_repo_defaults,
      organization: current_organization.display_login,
      enterprise: { slug: current_organization.business&.slug, name: current_organization.business&.name },
      enterpriseConfigsAvailable: enterprise_security_configurations?,
      enterpriseAdmin: current_organization.business&.owner?(current_user),
      helperUrls: {
        baseAvatarUrl: GitHub.alambic_avatar_url,
        bypassReviewersRoleUrl: settings_org_role_assignments_path(current_organization, query: "role:\"Push protection reviewers\""),
        suggestedBypassReviewersUrl: org_secret_scanning_bypass_reviewer_suggestions_path(current_organization.display_login),
      },
    })
  end

  sig { returns(T::Boolean) }
  def enterprise_security_configurations?
    return false unless current_organization.business
    SecurityProductsEnablement.enterprise_configs_enabled?(current_organization.business)
  end

  sig { returns(SecurityProductsEnablement::SecurityConfigurationSerializer) }
  memoize def security_configuration_serializer
    SecurityProductsEnablement::SecurityConfigurationSerializer.new(current_organization)
  end

  # before_action helper to return an HTTP 422 if the organization is currently applying or blocking configs.
  sig { void }
  def prevent_duplicate_enablement_events
    if current_organization.security_configurations_applying_or_blocked?
      render json: {
        error: "Another enablement event is in progress and your changes could not be saved. Please try again later."
      }, status: :unprocessable_entity
    end
  end

  sig { returns(SecurityConfiguration) }
  memoize def security_configuration
    targets = [current_organization, current_organization.business].compact
    find_security_configuration(targets)
  end

  def changes_in_progress
    if current_organization.jobs_in_progress?
      { inProgress: true, type: "applying_configuration" }
    elsif current_organization.security_configurations_blocked?
      { inProgress: true, type: "enablement_changes" }
    else
      { inProgress: false }
    end
  end
end
