# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module PublicForkPrWorkflowsPolicy
      include Platform::Interfaces::Base

      description "Represents the policy applied to running workflows from public fork pull requests."
      visibility :internal

      field :public_fork_pr_workflows_policy, Enums::PublicForkPrWorkflowsPolicyValue, "Indicates the public fork PR workflow policy for this object", method: :public_fork_pr_workflows_policy, null: false

      def public_fork_pr_workflows_policy
        @object.public_fork_pr_workflows_policy
      end
    end
  end
end
