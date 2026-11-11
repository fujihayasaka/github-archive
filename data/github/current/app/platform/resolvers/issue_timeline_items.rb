# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueTimelineItems < Resolvers::TimelineItems
      self.union_type = Unions::IssueTimelineItems
      type(define_connection(self.union_type), null: false)

      define_item_types_argument(self.union_type)
    end
  end
end
