# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class DependencyGraphComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || is_restricted_by_public_repo? || enabled_at_instance_level? || restricted_by_security_configuration?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # Careful readers will note that we are not checking if the user is an admin here.
      # That's because the user's admin status is checked when `data.dependabot_alerts_blocked_by_policy`
      # is computed. Long term that should probably move into here.
      dependabot_alerts_blocked_by_policy = T.cast(data.dependabot_alerts_blocked_by_policy, T::Boolean)

      # The public repo restriction overrides any enterprise policy
      if is_restricted_by_public_repo?
        false
      # DG can't be disabled if it's needed for alerts and alert disabling is blocked by policy
      else
        dependabot_alerts_blocked_by_policy && repository.vulnerability_alerts_enabled?
      end
    end

    sig { returns(T::Boolean) }
    def enabled_at_instance_level?
      GitHub.enterprise?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      return false if is_restricted_by_public_repo?
      return false unless has_enforced_security_configuration?

      repository.security_configuration!.dependency_graph != "not_set"
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.dependency_graph_enabled
    end

    sig { returns(T::Boolean) }
    def is_restricted_by_public_repo?
      data.dependency_graph_always_enabled_for_public_repos
    end

    sig { returns(String) }
    def dependency_graph_enterprise_link_action
      "#{is_currently_enabled? ? "dis" : "en"}able Dependency Graph"
    end

    sig { returns(String) }
    def dependency_graph_enterprise_link_url
      "#{GitHub.enterprise_admin_help_url(skip_version: true)}/configuration/enabling-alerts-for-vulnerable-dependencies-on-github-enterprise-server"
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if is_restricted_by_public_repo? || has_mixed_restrictions?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end
  end
end
