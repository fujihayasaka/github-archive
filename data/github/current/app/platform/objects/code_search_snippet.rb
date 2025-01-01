# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchSnippet < Base
      description "A preview into the query results of a code search for a specific file"

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      mobile_only true

      # The underlying Blackbird API will also verify oauth scopes during its authz checks.
      scopeless_tokens_as_minimum

      field :end_position, Integer, description: "Ending character position", null: false

      field :ending_line_number, Integer, description: "Ending line number", null: false

      field :jump_to_line_number, Integer, description: "Beginning line number", null: false

      field :lines, [String], description: "Preview of matching lines", null: false

      field :match_count, Integer, description: "Number of matches within the snippet", null: false

      field :score, Float, description: "Matching score", null: false

      field :start_position, Integer, description: "Starting character position", null: false

      field :starting_line_number, Integer, description: "Starting line number", null: false

      field :type, Enums::CodeSearchSnippetType, description: "Rendered snippet format", null: false
    end
  end
end
