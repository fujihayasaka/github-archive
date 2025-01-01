# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeploymentProtectionRuleType < Platform::Enums::Base
      description "The possible protection rule types."

      value "REQUIRED_REVIEWERS", "Required reviewers", value: "manual_approval"
      value "WAIT_TIMER",         "Wait timer",         value: "timeout"
      value "BRANCH_POLICY",      "Branch policy",      value: "branch_policy"
    end
  end
end
