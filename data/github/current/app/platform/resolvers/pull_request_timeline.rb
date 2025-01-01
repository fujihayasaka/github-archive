# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PullRequestTimeline < Resolvers::Timeline
      self.union_type = Unions::PullRequestTimelineItem
      type(Connections.define(self.union_type, name: graphql_name), null: false)
    end
  end
end
