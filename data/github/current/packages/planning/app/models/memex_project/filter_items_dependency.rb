# typed: true
# frozen_string_literal: true

class MemexProject
  module FilterItemsDependency
    extend T::Helpers

    requires_ancestor { MemexProject }

    # Memex-style search terms that need to be mapped to internal column names.
    REPLACEMENT_SLUGS = {
      assignee: :assignees,
      label: :labels,
      repo: :repository,
    }.freeze

    module SearchTerms
      ABSENCE = :no
      IS      = :is
    end

    ALLOWED_SEARCH_TERMS = SearchTerms.constants.map { |c| SearchTerms.const_get(c) }.freeze

    # Returns a list of matching memex items for a given filter string.
    #
    # Parameters:
    #   - memex_items: an array of MemexProjectItems to filter
    #   - filter: a string containing memex-style search qualifiers
    #             e.g. "status:done,\"In Progress\" -label:bug"
    #             (TODO: support filtering by keywords like "foo")
    #   - viewer: the user who is filtering the items
    #             (TODO: use to replace "@me" in search qualifiers)
    #   - prefilled_associations: the prefilled associations for the items (optional)
    #   - visible_fields: array of column IDs that are visible to the viewer
    #
    # Returns: [MemexProjectItem]
    def filter_items(memex_items:, filter:, viewer: nil, prefilled_associations: nil, visible_fields: [])
      async_filter_items(
        memex_items: memex_items,
        filter: filter,
        viewer: viewer,
        prefilled_associations: prefilled_associations,
        visible_fields: visible_fields
      ).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Returns a promise for a list of matching memex items for a given filter string.
    #
    # Parameters:
    #   - memex_items: an array of MemexProjectItems to filter
    #   - filter: a string containing memex-style search qualifiers
    #             e.g. "status:done,\"In Progress\" -label:bug"
    #             (TODO: support filtering by keywords like "foo")
    #   - viewer: the user who is filtering the items
    #             (TODO: use to replace "@me" in search qualifiers)
    #   - prefilled_associations: the prefilled associations for the items (optional)
    #   - visible_fields: array of column IDs that are visible to the viewer
    #
    # Returns: Promise<[MemexProjectItem]>
    def async_filter_items(memex_items:, filter:, viewer: nil, prefilled_associations: nil, visible_fields: [])
      raise ArgumentError, "filter cannot be blank" if filter.blank?

      async_memex_project_columns.then do |columns|
        # Parse the query terms into a hash of column names + values to filter on
        query_filters = query_filters(filter: filter, columns: columns, viewer: viewer)
        search_qualifiers = parse_search_qualifiers(query_filters: query_filters)

        queried_columns = columns.select { |c| search_qualifiers.keys.include?(c.name_slug.to_sym) }
        visible_columns = columns.select { |c| visible_fields.include?(c.id) }

        # NOTE: We are declaring this as T.untyped here because Sorbet was complaining that we are
        # changing the type from nil to T.untyped, which doesn't quite make sense since this was
        # T.untyped to begin with. So we are redeclaring that type here to continue propagating T.untyped.
        prefilled_associations ||= T.let(MemexProjectItemPrefiller.new(
            memex_items,
            columns: (visible_columns + queried_columns).uniq,
            title_column: columns.find(&:title?)
          ).prefill, T.untyped)

        # Collect an array of column values to filter on
        filter = Filter.new(queried_columns, search_qualifiers)

        Promise.all(memex_items.map { |i| async_item_metadata(i) }).then do |item_metadatas|
          # Combine both the memex_items and the item_metadatas arrays into a single array.  This new array
          # will be a two-dimensional array, where each element is an array of the form [memex_item, item_metadata].
          items_and_metadatas = memex_items.zip(item_metadatas)

          filtered_items = items_and_metadatas.each_with_object([]) do |(item, metadata), memo|
            # For an item, retrieve the values of all columns that are being searched on
            item_values = item.column_values(
              columns: queried_columns,
              prefilled_associations: prefilled_associations
            )

            item_values << {
              memexProjectColumnId: ItemMetadata.name,
              value: metadata
            }

            # Select this item if all of the item values match the expected column values
            memo << item if filter.matches?(item_values)
          end

          Array.wrap(filtered_items)
        end
      end
    end

    # Translates Search::ParsedQuery#parse results into a hash of column names to filter values on
    #
    # Supports the following search terms:
    #   - Regular search query w/ 1 term (e.g. "label:foo")
    #   - Regular search query w/ array of terms (e.g. "label:foo,bar,baz")
    #   - Negation (i.e. -label:"done")
    #   - Absence (i.e. no:label)
    #   - TODO: Regular keyword search terms (i.e. "foobar")
    def parse_search_qualifiers(query_filters: [])
      # Unpacks the query filters into variables
      # Example input: [:label, ["foo", "bar"]]
      #   term = :label, value = ["foo", "bar"], negated = nil
      #
      # Example input (negated): [:status, "done", true]
      #   term = :status, value = "done", negated = true
      query_filters&.each_with_object({}) do |(term, value, negated), qualifiers|
        next unless value.present?

        if term == SearchTerms::ABSENCE
          term = value.to_sym
          data = { value: [], negated: !!negated, absence: true }
        else
          data = { value: value, negated: !!negated, absence: false }
        end

        key = REPLACEMENT_SLUGS[term] || term

        # If the column is already being filtered on, append the new value to the existing array
        # Used to properly support edge case queries such as "-no:status status:done"
        if qualifiers.key?(key)
          qualifiers[key] << data
        else
          qualifiers[key] = Array.wrap(data)
        end
      end
    end

    # Public: Parse the string of filters into an array of query terms/values
    #
    # Parameters:
    #   - filter: a string containing memex-style search qualifiers
    #
    # Returns:
    #   - An array of parsed query terms/values
    #
    # Example: "label:foo,\"bar baz\" -status:done" => [[:label, ["foo", "bar baz"]], [:status, "done", true]]
    def query_filters(filter: "", columns: [], viewer: nil)
      column_slugs = columns.map { |c| c.name_slug.to_sym }
      valid_search_terms = ALLOWED_SEARCH_TERMS + column_slugs + REPLACEMENT_SLUGS.keys

      Search::ParsedQuery.parse(filter, terms: valid_search_terms, viewer: viewer, enumerable_terms: valid_search_terms, replace_me: viewer.present?, escape_terms: true, replace_today: true)
    end

    # Public: Pass in an array of MemexProjectItems and get a Promise that will resolve an array of corresponding
    #         ItemMetadata objects.  These ItemMetadata objects are used to filter on the item's metadata.
    #         Item metadata is considered "data that is not defined in columns directly by the user", such as
    #         item type and state.  Note that in order to go from a MemexProjectItem to an ItemMetadata, we need
    #         to resolve all item MemexProjectItem#content values and then PullRequest#issue_state for
    #         MemexProjectItems that are pull requests..
    #
    # Parameters:
    #   - An array of MemexProjectItems.
    #
    # Returns:
    #   - A Promise that will ultimately resolve to an array of ItemMetadata objects.
    def async_item_metadata(memex_item)
      memex_item.async_content.then do |content|
        content_type = content.class.name # PullRequest | Issue | DraftIssue
        is_draft = content_type == DraftIssue.name || (content_type == PullRequest.name && content.draft?)

        if content_type == PullRequest.name
          content.async_issue_state.then do |issue_state|
            ItemMetadata.new(
              content_type: content_type,
              is_draft: is_draft,
              state: issue_state
            )
          end
        else
          state =
            case content_type
            when DraftIssue.name
              "open" # draft issues cannot be currently closed
            when Issue.name
              content.state
            else
              raise ArgumentError, "Unknown content type: #{content_type}"
            end

          item_metadata = ItemMetadata.new(
            content_type: content_type,
            is_draft: is_draft,
            state: state
          )

          Promise.resolve(item_metadata)
        end
      end
    end
  end
end
