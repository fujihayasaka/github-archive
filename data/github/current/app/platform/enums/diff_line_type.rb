# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiffLineType < Platform::Enums::Base
      docs_category :commits
      description "The possible DiffLine types."
      required_capabilities [:mobile_only_schema_mask, :access_pull_request_diff_graphql_api]

      value "HUNK", "A diff hunk header line.", value: :hunk
      value "CONTEXT", "A diff context line.", value: :context
      value "ADDITION", "A diff addition line.", value: :addition
      value "DELETION", "A diff deletion line.", value: :deletion
      value "INJECTED_CONTEXT", "An injected diff context line.", value: :injected_context
    end
  end
end
