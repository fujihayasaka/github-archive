# typed: true
# frozen_string_literal: true

module Organization::DependabotDependency
  extend T::Helpers
  requires_ancestor { Kernel }
  requires_ancestor { Organization }

  # Is the given user allowed to access the repository access settings for this
  # organization?
  #
  # user - A User
  #
  # Returns a Boolean.
  def dependabot_repository_access_enabled_for?(user)
    T.bind(self, ::Organization)

    return false unless GitHub.dependabot_enabled?
    return false unless user.present?
    SecurityProduct::Permissions::OrgAuthz.new(self, actor: user).can_manage_org_security_products?
  end

  def dependabot_installed?
    return false unless GitHub.dependabot_enabled?
    return false unless GitHub.dependabot_github_app.present?
    IntegrationInstallation.exists?(integration_id: GitHub.dependabot_github_app.id, target: self)
  end

  # Returns true if innersource advisory alerting is enabled for this organization or its business.
  sig { returns(T::Boolean) }
  def innersource_advisory_alerting_enabled?
    T.bind(self, ::Organization)
    return false if GitHub.enterprise? # Innersource alerting is not supported for GHES

    FeatureFlag.vexi.enabled?(:innersource_alerting, business, self, default: false)
  end
end
