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
      extend T::Sig

      # Internal class that represents the paginated memex project items (nodes) within a group when grouping is applied.
      class GroupItems < T::Struct
        extend T::Sig

        const :group_id, String
        const :secondary_group_id, T.nilable(String)
        const :nodes, T::Array[T::Hash[T.untyped, T.untyped]]
        const :page_info, Search::Responses::PageInfo

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

      # A serialized page of grouped items (nil if returning non-grouped items)
      const :groups, T.nilable(MemexProjectColumn::Groupable::PaginatedGroups)

      # A serialized page of secondary grouped items (nil if returning secondary non-grouped items)
      const :secondary_groups, T.nilable(MemexProjectColumn::Groupable::PaginatedGroups)

      # A serialized page of grouped items (nil if returning non-grouped items)
      const :grouped_items, T.nilable(T::Array[GroupItems])

      # An non-serialized array of slice values (nil if slicing does not apply)
      const :slices, T.nilable(T::Array[MemexItemsApiResponse::Slice])

      # total number of items that match the query filtering, independent of page size
      const :total_count, T.nilable(MemexItemsApiResponse::TotalCount)

      SerializerProc = T.type_alias do
        T.proc.params(models: T::Array[MemexProjectItem]).returns(T::Array[T::Hash[T.untyped, T.untyped]])
      end

      # Returns a Hash representation of this response that can be passed as the `json` key to
      # the `render` method of a Rails controller.
      # Memex project items are returned as an array of nodes that may be wrapped within groups.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          groups: groups&.to_hash,
          secondary_groups: secondary_groups&.to_hash,
          grouped_items: grouped_items&.map(&:to_hash),
          slices: slices&.map(&:to_hash),
          total_count: total_count&.to_hash,
        }
        .deep_transform_keys { _1.to_s.camelize(:lower) }
        .compact
      end

      # Private factory method that returns an instance of this class as groups of project items
      sig do
        params(response: Search::Responses::GroupedMemexProjectItemResponse, serializer: SerializerProc)
        .returns(GroupedMemexItemsApiResponse)
      end
      def self.build(response, serializer)

        # get the redacted set of all item hashes
        all_items = serializer.call(response.models)

        # create a map of item ids to their group
        item_by_id = all_items.reduce({}) do |memo, item|
          memo[item[:id]] = item
          memo
        end

        primary_groups = response.primary_groups
        secondary_groups = response.secondary_groups

        # build the grouped response
        response_grouped_items = T.let(
          secondary_groups.present? ? T.must(response.grouped_items) : response.primary_groups.nodes,
          T.any(T::Array[MemexProjectColumn::Groupable::Group], T::Array[MemexProjectColumn::Groupable::GroupedItems])
        )

        grouped_items = response_grouped_items.map do |g|
          item_group = g.paginated_items.map do |i|
            id = i.dig("_source", "database_id")
            item_by_id[id]
          end
          item_group.compact!

          GroupItems.new(
            group_id: g.group_id,
            secondary_group_id: g.secondary_group_id,
            nodes: item_group,
            page_info: Search::Responses::PageInfo.new(
              start_cursor: g.start_cursor,
              end_cursor: g.end_cursor,
              has_previous_page: g.has_previous_page,
              has_next_page: g.has_next_page,
            )
          )
        end

        new(
          slices: MemexItemsApiResponse.build_slices(response),
          groups: primary_groups,
          secondary_groups:,
          grouped_items:,
          # total_count represents the total number of items across all groups, regardless of group pagination.
          # We do not return a total group count.  For more info, see https://github.com/github/projects-platform/issues/1037.
          total_count: MemexItemsApiResponse::TotalCount.new(value: response.total, is_approximate: response.total_is_approximate?),
        )
      end
    end
  end
end
