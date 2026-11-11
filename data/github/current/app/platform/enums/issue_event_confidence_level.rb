# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueEventConfidenceLevel < Platform::Enums::Base
      docs_category :issues
      description "The confidence level associated with an agent's issue event action."
      feature_flag :update_issue_suggestions

      value "LOW", "Low confidence.", value: "LOW"
      value "MEDIUM", "Medium confidence.", value: "MEDIUM"
      value "HIGH", "High confidence.", value: "HIGH"
    end
  end
end
