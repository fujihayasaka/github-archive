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
        # fetch timeline for the viewer, reject any non-known types to preserve response
        # and ensure we don't expose internal types

        # begin by batch-loading and caching objects that we're very likely to return.
        (object.is_a?(Issue) ? Promise.resolve(object) : object.async_issue).then do |issue|
          Promise.all([issue.async_comments, issue.async_events]).then do
            known_types = self.class.union_type.possible_types.reject do |type|
              context[:target] != :internal && type.visibility == :internal
            end.map(&:graphql_name)
            timeline = Platform::LoaderTracker.ignore_association_loads do # rubocop:disable GitHub/IgnoreAssociationLoads
              object.timeline_for(context[:viewer], since: since)
            end

            items = timeline.map do |item|
              if item.is_a?(Platform::Models::PullRequestCommit)
                item.commit.tap do |commit|
                  commit.repository = object.repository
                end
              else
                item
              end
            end.select do |item|
              type_name = Platform::Helpers::NodeIdentification.type_name_from_object(item)
              known_type = known_types.include?(type_name)
              GitHub.dogstats.increment("platform.types.missing_issue_events.count", tags: ["event:#{type_name.downcase}"]) unless known_type

              known_type
            end.freeze # dup above and re-freeze
            ArrayWrapper.new(items)
          end
        end
      end
    end
  end
end
