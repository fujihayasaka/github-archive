# typed: true
# frozen_string_literal: true
module Platform
  module Resolvers
    class IssueTimelineItems < Resolvers::TimelineItems
      type(define_connection(Unions::IssueTimelineItems), null: false)

      define_item_types_argument(Unions::IssueTimelineItems)
    end
  end
end
