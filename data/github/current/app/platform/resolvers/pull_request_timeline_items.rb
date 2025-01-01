# typed: true
# frozen_string_literal: true
module Platform
  module Resolvers
    class PullRequestTimelineItems < Resolvers::TimelineItems
      type(define_connection(Unions::PullRequestTimelineItems), null: false)

      define_item_types_argument(Unions::PullRequestTimelineItems)
    end
  end
end
