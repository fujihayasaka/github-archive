# typed: strict
# frozen_string_literal: true

# This class represents a JSON response that we can return from our internal API endpoints to the Projects web
# client.
#
# Instances of this class should be created via the `build` factory method. That method will execute the query it is
# given against Elasticsearch, and then return an instance of this class, which wraps the Elasticsearch response with
# pagination information that is styled after GraphQL: https://graphql.org/learn/pagination/. That instance of this
# class can then be serialized to JSON with the `to_hash` method.
#
# EXAMPLE:
#
#   response = Search::Responses::GroupedMemexItemsApiResponse.build(query:, serializer:)
#   render(json: response.to_hash)
module Search
  module Responses
    class GroupedMemexItemsApiResponse < T::Struct
      include SharedMemexProjectItemApiResponseHelpers

      # Internal class that represents the paginated memex project items (nodes) within a group when grouping is applied.
      class GroupItems < T::Struct

        const :group_id, String
        const :secondary_group_id, T.nilable(String)
        const :nodes, T::Array[T::Hash[T.untyped, T.untyped]]
        const :page_info, Search::Responses::PageInfo

        sig do
          params(
            grouped_items: MemexProjectColumn::Interface::Groupable::GroupedItems,
            nodes: T::Array[T::Hash[T.untyped, T.untyped]],
          )
          .returns(GroupItems)
        end
        def self.build(grouped_items, nodes)
          new(
            group_id: grouped_items.group_id,
            secondary_group_id: grouped_items.secondary_group_id,
            nodes: nodes,
            page_info: grouped_items.page_info,
          )
        end

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def to_hash
          {
            groupId: group_id,
            secondaryGroupId: secondary_group_id,
            nodes: nodes,
            pageInfo: page_info.to_hash,
          }.compact
        end
      end

      # A serialized page of groups (without items)
      const :groups, MemexProjectColumn::Interface::Groupable::PaginatedGroups

      # A serialized page of secondary groups, nil if secondary grouping isn't applied
      const :secondary_groups, T.nilable(MemexProjectColumn::Interface::Groupable::PaginatedGroups)

      # The list of item arrays for each group and their corresponding group id and optional secondary group id.
      # When secondary grouping is not active, this list is 1:1 with primary groups.
      # When secondary grouping is active, this list aligns with the intersection of each primary/secondary pair.
      const :grouped_items, T::Array[GroupItems]

      # An non-serialized array of slice values (nil if slicing does not apply)
      const :slices, T.nilable(T::Array[MemexItemsApiResponse::Slice])

      # total number of items that match the query filtering, independent of page size
      const :total_count, Search::Responses::TotalCount

      # The ElastomerClient exception caught during query execution, if any
      const :exception, T.nilable(ElastomerClient::Client::Error)

      # Returns a Hash representation of this response that can be passed as the `json` key to
      # the `render` method of a Rails controller.
      # Memex project items are returned as an array of nodes that may be wrapped within groups.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          groups: groups.to_hash,
          secondary_groups: secondary_groups&.to_hash,
          grouped_items: grouped_items.map(&:to_hash),
          slices: slices&.map(&:to_hash),
          total_count: total_count.to_hash,
          exception: sanitize_exception(exception),
        }
        .deep_transform_keys { _1.to_s.camelize(:lower) }
        .compact
      end

      # Private factory method that returns an instance of this class as groups of project items
      sig do
        params(response: Search::Responses::GroupedMemexProjectItemResponse, serializer: MemexItemsApiResponse::SerializerProc)
        .returns(GroupedMemexItemsApiResponse)
      end
      def self.build(response, serializer)

        # get the redacted set of all item hashes
        all_items = serializer.call(response)

        # create a map of item ids to their group
        item_by_id = all_items.reduce({}) do |memo, item|
          memo[item[:id]] = item
          memo
        end

        primary_groups = response.primary_groups
        secondary_groups = response.secondary_groups

        grouped_items = response.grouped_items.map do |g|
          item_nodes = g.paginated_items.map do |i|
            id = i.dig("_source", "database_id")
            item_by_id[id]
          end
          item_nodes.compact!

          GroupItems.build(g, item_nodes)
        end

        new(
          slices: MemexItemsApiResponse.build_slices(response),
          groups: primary_groups,
          secondary_groups:,
          grouped_items:,
          # total_count represents the total number of items across all groups, regardless of group pagination.
          # We do not return a total group count.  For more info, see https://github.com/github/projects-platform/issues/1037.
          total_count: Search::Responses::TotalCount.new(value: response.total, is_approximate: response.total_is_approximate?),
          exception: response.elastomer_exception,
        )
      end
    end
  end
end
