# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PublicForkPrWorkflowsPolicyValue < Platform::Enums::Base
      description "The possible public fork PR workflows policies."
      visibility :internal

      value Configurable::PublicForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::PublicForkPrWorkflowsPolicy::INVALID),
      "Invalid policy", value: Configurable::PublicForkPrWorkflowsPolicy::INVALID

      value Configurable::PublicForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::PublicForkPrWorkflowsPolicy::RUN_WORKFLOWS),
        "Fork PR workflows are enabled.", value: Configurable::PublicForkPrWorkflowsPolicy::RUN_WORKFLOWS

      value Configurable::PublicForkPrWorkflowsPolicy::POLICY_NAMES.fetch(Configurable::PublicForkPrWorkflowsPolicy::RUN_WITH_VARIABLES),
        "Fork PR workflows are enabled, and variables are provided.", value: Configurable::PublicForkPrWorkflowsPolicy::RUN_WITH_VARIABLES
    end
  end
end
