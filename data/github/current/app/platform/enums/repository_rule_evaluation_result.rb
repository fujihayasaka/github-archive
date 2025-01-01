# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRuleEvaluationResult < Platform::Enums::Base
      description "The evaluation result of a rule"
      feature_flag :pull_request_merge_requirements_api

      value "PASSED", "Indicates the rule passed.", value: "passed"
      value "FAILED", "Indicates the rule failed", value: "failed"
    end
  end
end
