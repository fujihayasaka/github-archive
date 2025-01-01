# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class GateType < Platform::Enums::Base
      description "The possible gate types."

      value "MANUAL_APPROVAL", "The gate requires one or more manual approvals to be open.", value: "manual_approval"
      value "TIMEOUT",         "The gate is a timeout gate",                                 value: "timeout"
      value "BRANCH_POLICY",   "The gate is a branch policy gate",                           value: "branch_policy"
      value "CUSTOM",          "The gate is a custom gate",                                  value: "custom", visibility: :under_development
    end
  end
end
