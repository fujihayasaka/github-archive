# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SubIssuesSummary < Platform::Objects::Base
      description "Summary of the state of an issue's sub-issues"

      # access to sub-issue completion is dependent on access to the parent object
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # access to sub-issue completion is dependent on access to the parent object
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :total, Integer, description: "Count of total number of sub-issues", null: false
      field :completed, Integer, description: "Count of completed sub-issues", null: false
      field :percent_completed, Integer, description: "Percent of sub-issues which are completed", null: false
    end
  end
end
