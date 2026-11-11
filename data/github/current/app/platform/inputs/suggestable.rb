# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    # Shared `rationale` + `suggest` arguments for input objects that mirror the
    # REST "suggestion" shape: an optional rationale describing why a value was
    # selected, plus a `suggest` flag that routes the value through the
    # pending-suggestion path instead of applying it directly.
    #
    # Both arguments are gated per-argument by the `:update_issue_suggestions`
    # feature flag, so the host input remains visible to callers without the
    # flag (important for inputs that are also used in create-shaped paths
    # where suggestions don't apply). Inputs dedicated solely to the
    # suggestion path may add their own class-level `feature_flag` declaration.
    module Suggestable
      def self.included(base)
        base.argument :rationale, GraphQL::Types::String, "Optional rationale describing why this value was selected.", required: false, feature_flag: :update_issue_suggestions
        base.argument :suggest, GraphQL::Types::Boolean, "If true, the value is stored as a pending suggestion for human review rather than being applied directly.", required: false, feature_flag: :update_issue_suggestions
        base.argument :confidence, Enums::IssueEventConfidenceLevel, "The confidence level the agent had when selecting this value.", required: false, feature_flag: :update_issue_suggestions
      end
    end
  end
end
