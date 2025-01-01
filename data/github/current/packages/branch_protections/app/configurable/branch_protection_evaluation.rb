# typed: strict
# frozen_string_literal: true

module BranchProtectionEvaluation
  module Configurable
    extend ActiveSupport::Concern
    extend T::Sig
    extend T::Helpers

    include ::Configurable

    BRANCH_PROTECTION_DISABLED = "branch_protection_evaluation.disabled"

    requires_ancestor { BranchProtectionsConfig }

    sig { params(actor: Users::IUser).void }
    def disable_branch_protection(actor:)
      return if branch_protection_disabled?

      config.enable(BRANCH_PROTECTION_DISABLED, actor)
      GitHub.dogstats.increment("branch_protection_evaluation.disable")
      GitHub.logger.info(
        "Branch protection configuration for repository changed",
        "code.namespace": self.class.name,
        "code.function": "disable_branch_protection",
        "gh.repo.id": repository.id,
        "gh.repo.owner.id": repository.owner_id,
        "gh.repo.owner.type": repository.owner&.class&.name,
        "gh.user.id": actor.id
      )
      GitHub.instrument(
        "repository_branch_protection_evaluation.disable",
        instrumentation_payload_branch_protection_settings(actor, previous_value: :enabled, current_value: :disabled))
    end

    sig { params(actor: Users::IUser).void }
    def enable_branch_protection(actor:)
      return unless branch_protection_disabled?

      config.disable(BRANCH_PROTECTION_DISABLED, actor)
      GitHub.dogstats.increment("branch_protection_evaluation.enable")
      GitHub.logger.info(
        "Branch protection configuration for repository changed",
        "code.namespace": self.class.name,
        "code.function": "enable_branch_protection",
        "gh.repo.id": repository.id,
        "gh.repo.owner.id": repository.owner_id,
        "gh.repo.owner.type": repository.owner&.class&.name,
        "gh.user.id": actor.id
      )
      GitHub.instrument(
        "repository_branch_protection_evaluation.enable",
        instrumentation_payload_branch_protection_settings(actor, previous_value: :disabled, current_value: :enabled))
    end

    sig { returns(T::Boolean) }
    def branch_protection_disabled?
      config.enabled?(BRANCH_PROTECTION_DISABLED)
    end

    sig { params(actor: Users::IUser, previous_value: Symbol, current_value: Symbol).returns(T::Hash[Symbol, String]) }
    private def instrumentation_payload_branch_protection_settings(actor, previous_value:, current_value:)
      payload = {
        user: actor,
        setting: "branch_protection_evaluation",
        previous_value: previous_value,
        value: current_value,
      }
      owner = T.cast(repository.owner, T.nilable(User))
      payload[:repo] = repository.name_with_display_owner
      payload[:repo_id] = repository.id
      if repository.owner.is_a?(Organization)
        payload[:org] = owner&.display_login
        payload[:org_id] = repository.owner_id
      end
      if owner&.business
        payload[:business] = owner.business
        payload[:business_id] = owner.business_id
      end

      payload
    end
  end
end
