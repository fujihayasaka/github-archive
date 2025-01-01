# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class TimelineItems < Resolvers::Base
      class << self
        attr_accessor :union_type
      end

      argument :since, Scalars::DateTime, "Filter timeline items by a `since` timestamp.", required: false

      # NOTE: Before publishing the `timelineItems` connections, the plan is to replace this
      # argument by a list of requested timeline item types.
      argument :visible_events_only, Boolean, "Only return events visible in GitHub's UI.", required: false, visibility: :internal

      argument :include_issue_type_events, Boolean, "Include issue type events.", required: false, default_value: false, visibility: :internal

      argument :skip, Integer, "Skips the first _n_ elements in the list.", required: false

      argument :focus, ID, "ID of element to focus on.", required: false, required_capabilities: [:mobile_only_schema_mask]

      # this is very similar to the focus argument but it is required to work with database ids to support urls with a focus hash
      # eg.: https://github.com/github/accessibility/issues/3950#issuecomment-1652555077
      argument :focus_text, String, "Text (type plus db id eg. issuecomment-1234123, event-10397922786) of element to focus on.", required: false, required_capabilities: [:mobile_only_schema_mask]

      argument :focus_neighbor_count, Integer, "Number of items to return before and after the focused item.", required: false, required_capabilities: [:mobile_only_schema_mask]

      def self.define_connection(type)
        conn_name = self.graphql_name

        Class.new(Platform::Connections::Base) do
          edge_type(type.edge_type, node_type: type)
          graphql_name "#{conn_name}Connection"

          total_count_field

          field :filtered_count, Integer, null: false,
            description: "Identifies the count of items after applying `before` and `after` filters."

          field :page_count, Integer, null: false,
            description: "Identifies the count of items after applying `before`/`after` filters and `first`/`last`/`skip` slicing."

          field :before_focus_count, Integer, null: false,
            description: "Identifies the count of items before the focused item (`focus`).",
            required_capabilities: [:mobile_only_schema_mask]

          field :after_focus_count, Integer, null: false,
            description: "Identifies the count of items after the focused item (`focus`).",
            required_capabilities: [:mobile_only_schema_mask]

          field :updated_at, Scalars::DateTime, null: false,
            description: "Identifies the date and time when the timeline was last updated.",
            method: :async_updated_at
        end
      end

      def self.define_item_type_enum(union_type)
        conn_name = self.graphql_name

        Class.new(Platform::Enums::Base) do
          graphql_name "#{conn_name}ItemType"
          description "The possible item types found in a timeline."

          union_type.possible_types.each do |type|
            value_options = {
              value: type,
              required_capabilities: type.required_capabilities
            }

            unless type.default_visibility?
              value_options[:visibility] = type.environment_visibilities.each_with_object({}) do |(env, visibilities), result|

                # The stored `environment_visibilities` for the type have
                # been normalised, so that `:public` implies `:internal` as
                # well. Unfortunately if we pass `[:public, :internal]` as
                # the visibility for an Enum value only the last (`:internal`)
                # will apply, so we have to undo the normalisation here before
                # we can copy the visibility configuration from the type to
                # the corresponding enum value.
                visibility = if visibilities.length == 1
                  visibilities.first
                elsif visibilities.sort == [:internal, :public]
                  :public
                end

                if visibility
                  result[visibility] ||= { environments: [] }
                  result[visibility][:environments] << env
                end
              end
            end

            value(
              type.graphql_name.underscore.upcase,
              type.description,
              **value_options
            )
          end
        end
      end

      def self.define_item_types_argument(union_type)
        argument :item_types, [define_item_type_enum(union_type)], "Filter timeline items by type.", required: false
      end

      def resolve(**arguments)
        visible_events_only = !!arguments[:visible_events_only]
        include_issue_type_events = !!arguments[:include_issue_type_events]

        item_types = arguments[:item_types]

        if GitHub.flipper[:ensure_issue_timeline_event_type_visibility].enabled?(context[:viewer]) # rubocop:disable GitHub/UseActorFeatureEnabled - viewer may be nil
          possible_types = self.class.union_type.possible_types

          # Remove any types that are not visible in the current environment
          visible_types = possible_types.select do |type|
            type.visibility.include?(context[:target])
          end

          # If item_types was provided, filter it down to only the visible types, otherwise use all known types.
          item_types = item_types.is_a?(Array) ? item_types & visible_types : visible_types
        end

        filter_options = {
          since: arguments[:since],
          item_types:,
          visible_events_only:,
          filter_closed_if_preceded_by_merged: visible_events_only && !!object.try(:merged?),
          cap_filter: context[:cap_filter],
          show_project_events: context[:target] == :internal,
          include_issue_type_events:,
        }

        if object.is_a?(Issue)
          ::Issues::Timeline::IssueTimeline.for(object, context[:viewer], filter_options)
        else
          ::PullRequests::Timeline::PullRequestTimeline.for(object, context[:viewer], filter_options)
        end
      end
    end
  end
end
