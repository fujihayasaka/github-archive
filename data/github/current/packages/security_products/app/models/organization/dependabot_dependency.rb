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
    SecurityProduct::Permissions::OrgAuthz.new(self, actor: user).can_manage_security_products?
  end

  def dependabot_installed?
    return false unless GitHub.dependabot_enabled?
    return false unless GitHub.dependabot_github_app.present?
    IntegrationInstallation.exists?(integration_id: GitHub.dependabot_github_app.id, target: self)
  end

  def grouped_security_updates_available?
    self.feature_enabled?(:dependabot_grouped_security_updates, memoize: false)
  end
end
