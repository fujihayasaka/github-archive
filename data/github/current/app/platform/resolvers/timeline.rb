# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Timeline < Resolvers::Base

      argument :since, Scalars::DateTime, "Allows filtering timeline events by a `since` timestamp.", required: false

      class << self
        attr_accessor :union_type
      end

      def resolve(since: nil)
        known_types = self.class.union_type.possible_types.reject do |type|
          context[:target] != :internal && type.visibility == :internal
        end

        known_types = ConnectionWrappers::Timeline.substitute_legacy_types(known_types)

        filter_options = {
          since: since,
          item_types: known_types,
          filter_closed_if_preceded_by_merged: !!object.try(:merged?),
          cap_filter: context[:cap_filter],
          show_project_events: context[:target] == :internal
        }

        timeline = if object.is_a?(Issue)
          ::Issues::Timeline::IssueTimeline.for(object, context[:viewer], filter_options)
        else
          ::PullRequests::Timeline::PullRequestTimeline.for(object, context[:viewer], filter_options)
        end

        # wrap the result to ensure we call the legacy connection wrapper
        Platform::Helpers::TimelineWrapper.new(timeline)
      end
    end
  end
end
