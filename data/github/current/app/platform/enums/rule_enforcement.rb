# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RuleEnforcement < Platform::Enums::Base
      description "The level of enforcement for a rule or ruleset."

      value "DISABLED", "Do not evaluate or enforce rules", value: "disabled"
      value "ACTIVE", "Rules will be enforced", value: "enabled"
      value "EVALUATE", "Allow admins to test rules before enforcing them. Admins can view insights on the Rule Insights page (`evaluate` is only available with GitHub Enterprise).", value: "evaluate"
    end
  end
end
