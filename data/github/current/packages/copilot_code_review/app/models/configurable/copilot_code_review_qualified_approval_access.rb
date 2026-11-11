# typed: strict
# frozen_string_literal: true

# Manage whether Copilot code review approvals may count toward merge requirements for all repositories, selected
# repositories, or no repositories owned by the configured organization.
module Configurable
  module CopilotCodeReviewQualifiedApprovalAccess
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }
    requires_ancestor { GitHub::VexiActor }

    KEY = "copilot_code_review_qualified_approval_access"

    class State < T::Enum
      enums do
        ALL_REPOS = new("all_repos")
        NO_POLICY = new("no_policy")
        SELECTED_REPOS = new("multiple")
        DISABLED = new("no_repos")
      end
    end

    sig { returns(State) }
    def default_copilot_code_review_qualified_approval_access_for_owner
      State::DISABLED
    end

    sig { returns(State) }
    def copilot_code_review_qualified_approval_access
      raw_copilot_code_review_qualified_approval_access || default_copilot_code_review_qualified_approval_access_for_owner
    end

    sig { returns(T.nilable(State)) }
    def raw_copilot_code_review_qualified_approval_access
      State.try_deserialize(config.get(KEY))
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def copilot_code_review_qualified_approval_enabled_for?(repository)
      copilot_code_review_qualified_approval_policy_for(repository) == :enabled
    end

    sig { params(repository: Repository).returns(T::Boolean) }
    def copilot_code_review_qualified_approval_repo_configurable_for?(repository)
      copilot_code_review_qualified_approval_policy_for(repository) == :delegated
    end

    sig { params(repository: Repository).returns(Symbol) }
    def copilot_code_review_qualified_approval_policy_for(repository)
      enablement = copilot_code_review_qualified_approval_access

      case enablement
      when State::ALL_REPOS
        :enabled
      when State::NO_POLICY
        :delegated
      when State::SELECTED_REPOS
        if PullRequests::Copilot::RepoEnablement.enabled_for_repository?(repository, setting_type: :qualified_approval)
          :enabled
        else
          :disabled
        end
      when State::DISABLED
        :disabled
      else T.absurd(enablement)
      end
    end

    sig { params(access: String, force: T::Boolean, actor: User).void }
    def update_copilot_code_review_qualified_approval_access(access, force = false, actor:)
      raise ArgumentError, "copilot_code_review_qualified_approval_access can only be configured on an Organization" unless respond_to?(:organization?) && T.unsafe(self).organization?

      new_access = State.deserialize(access)
      old_access = copilot_code_review_qualified_approval_access

      changed = config.set!(KEY, access, actor, force)
      return unless changed

      GitHub.dogstats.increment("copilot_code_review_qualified_approval_access.updated")
      GitHub.instrument(
        "copilot_code_review_qualified_approval_access.updated",
        {
          actor: actor,
          organization: self,
          new_access: new_access.serialize,
          old_access: old_access.serialize,
        },
      )
    end
  end
end
