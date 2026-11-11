# typed: true
# frozen_string_literal: true

# This configurable determines whether repository admins (that are not org owners) can directly install GitHub Apps
# to org repos they're an admin of. The default behavior is to allow installation.
module Configurable
  module DisableGitHubAppInstallationByNonOrgOwnerRepoAdmins
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    KEY = T.let("disable_github_app_installation_by_non_org_owner_repo_admins", String)

    def disallow_github_app_installation_by_non_org_owner_repo_admins(actor:)
      changed = config.enable!(KEY, actor, false)

      return unless changed
      self.instrument("github_app_installation_by_non_org_owner_repo_admins_disable", {
        actor: actor,
      })
    end

    def allow_github_app_installation_by_non_org_owner_repo_admins(actor:)
      changed = config.disable!(KEY, actor, true)

      return unless changed
      self.instrument("github_app_installation_by_non_org_owner_repo_admins_enable", {
        actor: actor,
      })
    end

    def denies_github_app_installation_by_non_org_owner_repo_admins?
      config.enabled?(KEY)
    end

    def allows_github_app_installation_by_non_org_owner_repo_admins?
      !denies_github_app_installation_by_non_org_owner_repo_admins?
    end
  end
end
