# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SubIssues < Platform::Resolvers::Base

      type Connections.define(Objects::Issue), null: false

      argument :order_by, Inputs::SubIssueOrder, "Ordering options for subissues returned from the connection",
        required: false,
        default_value: { field: "priority", direction: "DESC" }

      def resolve(**arguments)
        @object.async_filtered_prioritized_sub_issues(
          viewer: @context[:viewer],
          cap_filter: @context[:cap_filter],
        ).then do |accessible_issues|
          ArrayWrapper.new(accessible_issues.compact)
        end
      end
    end
  end
end
