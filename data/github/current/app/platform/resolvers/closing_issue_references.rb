# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ClosingIssueReferences < Resolvers::Base
      type Connections.define(Objects::Issue), null: true

      argument :user_linked_only, Boolean, "Return only manually linked Issues", required: false, default_value: false

      def resolve(user_linked_only: false, **arguments)
        @object.async_cap_filtered_close_issue_references_for(
          viewer: @context[:viewer],
          user_linked_only: user_linked_only,
          cap_filter: @context[:cap_filter]
        ).then do |accessible_issues|
          ArrayWrapper.new(accessible_issues.compact)
        end
      end
    end
  end
end
