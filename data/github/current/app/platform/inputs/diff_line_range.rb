# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DiffLineRange < Platform::Inputs::Base
      docs_category :commits
      graphql_name "DiffLineRange"
      description "A range of diff lines which defines a patch."
      required_capabilities [:mobile_only_schema_mask, :access_pull_request_diff_graphql_api]

      argument :start, Int, "The line number where the range starts.", required: true
      argument :end, Int, "The line number where the range ends.", required: true
    end
  end
end
