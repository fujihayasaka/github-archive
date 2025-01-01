# typed: strict
# frozen_string_literal: true

# Manage whether SWE Agent is enabled for all repositories, selected repositories, or disabled owned by the configured
# entity.
# Currently included by Organization and User.
module Configurable
  module CopilotSweAgentAccess
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }
    requires_ancestor { GitHub::FlipperActor }
    requires_ancestor { GitHub::VexiActor }

    KEY = "copilot_swe_agent_access"

    class State < T::Enum
      enums do
        # Padawan is enabled for all repositories
        ALL_REPOS = new("all_repos")
        # Padawan is enabled for selected repositories
        SELECTED_REPOS = new("multiple")
        # Padawan is disabled
        DISABLED = new("no_repos")
      end
    end

    sig { returns(State) }
    def default_copilot_swe_agent_access_for_owner
      if self.feature_flag_enabled?(:copilot_swe_agent_enable_repos_by_default, default: false)
        State::ALL_REPOS
      else
        State::DISABLED
      end
    end

    sig { returns(State) }
    def copilot_swe_agent_access
      State.try_deserialize(config.get(KEY)) || default_copilot_swe_agent_access_for_owner
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def copilot_swe_agent_enabled_for?(repository)
      if GitHub.multi_tenant_enterprise?
        return false unless self.feature_flag_enabled_or_raise?(:coding_agent_in_proxima) || repository.feature_flag_enabled_or_raise?(:coding_agent_in_proxima) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return true if self.feature_flag_enabled_or_raise?(:coding_agent_in_proxima_always_enabled_test) || repository.feature_flag_enabled_or_raise?(:coding_agent_in_proxima_always_enabled_test) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      business = repository.async_business.sync
      return false unless business.nil? || business.swe_agent_repository_access_enabled?
      enablement = copilot_swe_agent_access
      case enablement
      when State::ALL_REPOS
        true
      when State::SELECTED_REPOS
        CopilotSweAgent::RepoEnablement.enabled_for_repository?(repository)
      when State::DISABLED
        false
      else T.absurd(enablement)
      end
    end

    sig { params(access: String, force: T::Boolean, actor: User).void }
    def update_copilot_swe_agent_access(access, force = false, actor:)
      new_access = State.deserialize(access)
      old_access = copilot_swe_agent_access

      changed = config.set!(KEY, access, actor, force)
      return unless changed

      owner = case self
      when Organization
        self
      when User
        self
      else
        raise ArgumentError, "Invalid owner type: #{self.class}"
      end

      Copilot::Instrumenter.instrument_swe_agent_enablement_updated(
        owner:,
        actor:,
        new_access: new_access.serialize,
        old_access: old_access.serialize
      )
    end
  end
end
