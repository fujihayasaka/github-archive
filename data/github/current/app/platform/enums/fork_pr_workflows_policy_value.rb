# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ForkPrWorkflowsPolicyValue < Platform::Enums::Base
      description "The possible fork PR workflows policies."
      visibility :internal

      value Configurable::ForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::ForkPrWorkflowsPolicy::DISABLED),
        "Fork PR workflows are disabled.", value: Configurable::ForkPrWorkflowsPolicy::DISABLED

      value Configurable::ForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS),
        "Fork PR workflows are enabled.", value: Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS

      value Configurable::ForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS),
        "Fork PR workflows are enabled, and write tokens are provided.", value: Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS

      value Configurable::ForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::ForkPrWorkflowsPolicy::RUN_WITH_SECRETS),
        "Fork PR workflows are enabled, and secrets are provided.", value: Configurable::ForkPrWorkflowsPolicy::RUN_WITH_SECRETS

      value Configurable::ForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS_AND_SECRETS),
        "Fork PR workflows are enabled, and write tokens and secrets are provided.", value: Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS_AND_SECRETS
    end
  end
end
