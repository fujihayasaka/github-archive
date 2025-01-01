# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ForkPrWorkflowsPolicy
      include Platform::Interfaces::Base

      description "Represents the policy applied to running workflows from fork pull requests."
      visibility :internal

      field :fork_pr_workflows_policy, Enums::ForkPrWorkflowsPolicyValue, "Indicates the fork PR workflow policy for this object", method: :fork_pr_workflows_policy, null: false

      def fork_pr_workflows_policy
        @object.fork_pr_workflows_policy
      end
    end
  end
end
