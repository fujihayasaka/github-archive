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
    payload[:capabilities][:hasTeams] = current_organization.teams.any?
    payload[:capabilities][:advancedSecurity] = advanced_security_capability(current_organization)

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
        bypassersRoleUrl: settings_org_role_assignments_path(current_organization, query: "role:\"Push protection reviewers\""),
        suggestedBypassersUrl: org_secret_scanning_bypasser_suggestions_path(current_organization.display_login),
      },
    })
  end

  sig { returns(T::Boolean) }
  def enterprise_security_configurations?
    current_organization.business.present?
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

  sig { params(blk: T.proc.void).void }
  def set_log_context(&blk)
    GitHub.logger.with_named_tags(
      "gh.enduser.id": current_user&.id,
      "gh.enduser.login": current_user&.display_login,
      "gh.org.id": current_organization&.id,
      "gh.org.login": current_organization&.display_login,
    ) do
      yield
    end
  end

  sig { params(config: SecurityConfiguration).void }
  def log_and_track_errors(config)
    log_tags = {
      "code.namespace": self.class.name,
      "code.function": action_name,
      "gh.security_configuration.errors": serialize_errors(config.errors),
    }
    log_tags["gh.security_configuration.id"] = config.id if config.persisted?

    GitHub.logger.info(**log_tags)

    unexpected = config.errors.attribute_names.reject { |k| k == :name || k == :description }
    return if unexpected.empty?

    GitHub.dogstats.increment(
      "security_products_enablement.configuration_save.unexpected_error",
      tags: [
        "controller:#{controller_name_with_namespace}",
        "action:#{action_name}",
        "error_fields:#{unexpected.sort.join(",")}",
      ],
    )
  end
end
