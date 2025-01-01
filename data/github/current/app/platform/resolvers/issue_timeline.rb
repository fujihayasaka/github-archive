# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueTimeline < Resolvers::Timeline
      self.union_type = Unions::IssueTimelineItem
      type(Connections.define(self.union_type, name: graphql_name), null: false)
    end
  end
end
