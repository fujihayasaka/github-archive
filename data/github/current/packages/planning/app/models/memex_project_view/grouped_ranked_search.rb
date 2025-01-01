# typed: true
# frozen_string_literal: true

class MemexProjectView
  class GroupedRankedSearch
    include GitHub::Memoizer
    include Measurable

    LOG_STAT_PREFIX = "platform.memex.grouped_ranked_search"
    private_constant :LOG_STAT_PREFIX

    attr_reader :memex,
                :project_columns,
                :group_by,
                :sort_by,
                :prefilled_associations,
                :visible_fields,
                :viewer,
                :view

    # Note: This initializer allows for callers to disable the MemexProjectItemRedactor, meaning that items will be
    # returned without being converted to a RedactedItem type. Private metadata will still be available on the item, so we do
    # not recommend returning items directly to a viewer without redaction. This is only intended for use in the
    # ProjectV2 GraphQL API, where redaction already happens on a per-item basis.
    def initialize(memex:, view:, filter:, columns:, items:, viewer:, group_by: nil, sort_by: nil, visible_fields: [], use_redactor: true)
      @memex = memex
      @view  = view
      @filter = filter
      @project_columns = columns
      @viewer = viewer
      @items = items
      @group_by = group_by
      @sort_by = Array.wrap(sort_by)
      @visible_fields = visible_fields
      @use_redactor = use_redactor

      measure! if GitHub.flipper[:memex_grouped_ranked_search_measurements].enabled?(viewer) && !GitHub.enterprise?
    end

    # Public: Groups, sorts, ranks, filters and flattens items.
    #
    # Returns: { group => [{ item: item, ranking: 1 }, ...], ...}, where group is the string representation of
    # the item's value on the group_by column, or nil.
    def execute
      async_execute.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Public: Asychronously groups, sorts, ranks, filters and flattens items.
    #         Measurements will not occur and will not be logged unless the feature flag corresponding to the
    #         LOG_METRICS_FEATURE_FLAG constant is enabled.
    #
    # Returns: Promise<{ group => [{ item: item, ranking: 1 }, ...], ...}>, where group is the string representation of
    # the item's value on the group_by column, or nil.
    memoize def async_execute
      measurable_execute(:prefill_associations!)

      output = measurable_execute(:group_items)
      output = measurable_execute(:sort_groups, output)
      output = measurable_execute(:sort_grouped_items, output)
      output = measurable_execute(:rank_grouped_items, output)
      output = measurable_execute(:reverse_groups, output) if reverse_group_order?

      # We can try and defer as much loading as possible only if we are not measuring execution times.  If we are
      # then we have to have a higher level of control over the execution life-cycle.
      if filter.present? && measure?
        # since we are measuring then call filter synchronously and log after.
        output = measurable_execute(:filter_ranked_items, output)

        # Notice the log comes after the sync filter call.  That way the logged metrics will include the filter time.
        log_measurables(output)

        Promise.resolve(output)
      elsif filter.present?
        # cant log filtering, log first and return the async promise.
        log_measurables(output)

        async_filter_ranked_items(output)
      else
        # If we are not filtering then log metrics and return already materialized output.
        log_measurables(output)

        Promise.resolve(output)
      end
    end

    # Public: Groups items based on the text representation of their value on the group by column
    #
    # Returns: { group => [item1, item2, ...], ... }, where group is a string representation of
    # a value on the group by column, or nil.
    def group_items
      if group_by
        processed_items.group_by do |processed_item|
          if processed_item[:viewer_can_read]
            processed_item[:item].to_group(group_by, view, prefilled_associations:)
          else
            MemexProject::Group.new(column: group_by, view:)
          end
        end
      else
        {
          MemexProject::Group.new(view:) => processed_items
        }
      end.each_with_object({}) do |(group, items), hash|
        hash[group] = items.map { |item| item[:item] }
      end
    end

    # Public: Sorts groups based on their names or by how they're configured in the
    # project settings. Ungrouped items will be placed at the end.
    #
    # Returns: { group => [item1, item2, ...], ... }
    def sort_groups(grouped_items)
      group_by ? grouped_items.sort.to_h : grouped_items
    end

    # Public: Sorts items within their groups based on the sort by column, if it exists.
    #
    # Parameters:
    #   - grouped_items: a hash of the format { group => [item1, item2, ...], ... }, where group is the string
    #   representation of a value on the group by column, or nil.
    #
    # Returns: { group => [item1, item2, ...], ... }, where group is the string representation of a value on
    # the group by column, or nil.
    def sort_grouped_items(grouped_items)
      grouped_items.each_with_object({}) do |(group, items), hash|
        hash[group] = sort_items(items)
      end
    end

    # Public: Ranks a hash of sorted items.
    #
    # Parameters:
    #   - grouped_items: a hash of { group => [{ item: item, ranking: 1 }, ...], ... }, where group is the string
    #     representation of a value on the group by column, or nil.
    #
    # Returns: { group => [{ item: item, ranking: 1 }, ...], ... }, where group is the string representation
    # of a value on the group by column, or nil.
    def rank_grouped_items(grouped_items)
      index = 0

      grouped_items.each_with_object({}) do |(group, items), hash|
        ranked_items = items.map do |item|
          index += 1
          { item: item, ranking: index }
        end

        hash[group] = ranked_items
      end
    end

    # Public: Filters an array of ranked items.
    #
    # Parameters:
    #   - ranked_items: an hash of { group => [{ item: item, ranking: 1 }, ...], ... } where group is the string
    #   representation of a value on the group by column, or nil.
    #
    # Returns: { group => [{ item: item, ranking: 1 }, ...], ... }, containing items that match the view's filter.
    def filter_ranked_items(ranked_items)
      async_filter_ranked_items(ranked_items).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Public: Asynchronously filters an array of ranked items.
    #
    # Parameters:
    #   - ranked_items: an hash of { group => [{ item: item, ranking: 1 }, ...], ... }, where group is the string
    #   representation of a value on the group by column, or nil.
    #
    # Returns: Promise<{ group => [{ item: item, ranking: 1 }, ...], ... }>, containing items that match the view's filter.
    def async_filter_ranked_items(ranked_items)
      return Promise.resolve(ranked_items) unless filter.present?

      items = T.let(ranked_items.values.flatten.flat_map { |ranked_item| ranked_item[:item] }, T::Array[T.untyped])

      memex.async_filter_items(
        memex_items: items,
        filter: filter,
        prefilled_associations: @prefilled_associations,
        viewer: viewer
      ).then do |filtered_items|
        ranked_items.each_with_object({}) do |(group, items), hash|
          selected_items = items.select { |item| filtered_items.include?(item[:item]) }

          hash[group] = selected_items if selected_items.any?
        end
      end
    end

    # Public: Returns the values of the groups in the order they should be displayed.
    # Checks if the viewer can read the items to ensure that values on the group by column are not exposed if the user
    # does not have permission to read an item within that group.
    #
    # Returns: [group, ...], where group is a string representation of a value on the group by column, or nil.
    def groups
      async_groups.sync
    end

    # Public: Asynchronously returns the values of the groups in the order they should be displayed.
    # Checks if the viewer can read the items to ensure that values on the group by column are not exposed if the user
    # does not have permission to read an item within that group.
    #
    # Returns: Promise<[group, ...]>, where group is a string representation of a value on the group by column, or nil.
    memoize def async_groups
      async_execute.then do |output|
        output.keys
      end
    end

    private

    attr_reader :filter,
                :use_redactor

    def make_tag(item_count)
      count_text =
        if item_count < 100
          "less_than_100"
        elsif item_count <= 250
          "100_to_250"
        elsif item_count <= 500
          "251_to_500"
        elsif item_count <= 1000
          "501_to_1000"
        else
          "1001_to_max"
        end

      "with_#{count_text}_items"
    end

    # Private: If measure! was called then this method will send all metrics to dogstats.
    #
    # Returns: passed in argument is returned.
    def log_measurables(output)
      return unless measure?

      item_count = output.values.sum(&:length)
      tag        = make_tag(item_count)

      measurable_results_in_ms.each do |method_name, result_in_ms|
        GitHub.dogstats.distribution("#{LOG_STAT_PREFIX}.#{method_name}_in_ms", result_in_ms, tags: [tag])
      end

      GitHub.dogstats.distribution("#{LOG_STAT_PREFIX}.total_in_ms", measurable_total_in_ms, tags: [tag])
      output
    end

    # Private: Resolve a list of all columns needed to materialize the view.  This includes queried, grouped,
    #          sorted, and visible columns.
    #
    # Returns: [MemexProjectColumn]
    def columns_to_prefill
      query_filters     = memex.query_filters(filter: filter, columns: project_columns, viewer: @viewer)
      search_qualifiers = memex.parse_search_qualifiers(query_filters: query_filters)

      queried_columns = project_columns.select { |c| search_qualifiers.keys.include?(c.name_slug.to_sym) }
      queried_columns << group_by if group_by
      queried_columns.concat(sort_by.pluck(:column)) if sort_by.present?

      visible_columns = project_columns.select { |c| visible_fields.include?(c.id) }

      (queried_columns + visible_columns).uniq
    end

    # Private: Prefills associations for the group by, sort by, and queried columns.
    #
    # Returns: PrefilledAssociation
    def prefill_associations!
      @prefilled_associations = MemexProjectItemPrefiller.new(
        @items,
        columns: columns_to_prefill,
        title_column: project_columns.find(&:title?)
      ).prefill
    end

    def processed_items
      async_processed_items.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Private: Sorts items into their default display order based on descending priority, and redacts items
    # that the viewer is unable to see.
    #
    # When processing items to be used via the GraphQL API, this method does not use the MemexProjectItemRedactor.
    # We will perform lazy redaction by providing permissions metadata through `viewer_can_read`
    #
    # Otherwise, all other use cases will rely on the MemexProjectItemRedactor to redact items that the viewer
    # can't see. In this case, `viewer_can_read` will always be true after redaction.
    #
    # Returns: Promise<[{ item: MemexProjectItem, viewer_can_read: Boolean }, ...]>
    def async_processed_items
      prioritized_items = @items.sort_by(&:priority_value).reverse

      if use_redactor
        # Perform redaction: for non-GraphQL usages, this accepts an array of MemexProjectItems. For any items that the
        # viewer can't see, this will replace the item in-place with a redacted version. `redacted_items` can contain
        # a combination of MemexProjectItem or RedactedItem types.
        redacted_items = MemexProjectItemRedactor.new(
          viewer: @viewer,
          items: prioritized_items,
          columns: project_columns,
          prefilled_associations: @prefilled_associations
        ).items

        Promise.resolve(
          redacted_items.map do |item|
            { item: item, viewer_can_read: true }
          end
        )
      else
        # Perform lazy redaction: the GraphQL API requires non-redacted items to be provided to the resolver as
        # it'll handle visibility checks before resolving the query.
        Promise.all(
          prioritized_items.map { |item| item.async_readable_by_viewer?(@viewer) }
        ).then do |readable_by_viewer_results|
          prioritized_items.each_with_index.map do |item, index|
            { item: item, viewer_can_read: readable_by_viewer_results[index] }
          end
        end
      end
    end

    # Private: Sorts items in array by their values on the group by column.
    #
    # Parameters:
    #   - items: [MemexProjectItem]
    #
    # Returns: [MemexProjectItem]
    def sort_items(items)
      MemexProjectItem::SortableValuesDependency.sort_by_sortable_values(items, sort_by:, prefilled_associations:)
    end

    # Private: Used to change sort direction for item priorities
    #
    # Returns: Integer
    def direction
      descending_sort? ? 1 : -1
    end

    # Private: Reverses a hash of grouped items
    #
    # Parameters:
    #   - grouped_items: { group_1 => [...], ..., group_n => [...] }
    #
    # Returns: { group_n => [...], ..., group_1 => [...] }
    def reverse_groups(grouped_items)
      grouped_items.reverse_each.to_h
    end

    # Private: Used to reverse the display order of groups for an edge case
    #
    # Returns: Boolean
    def reverse_group_order?
      sort_by.present? &&
        group_by.present? &&
        sort_by.first[:column].id == group_by.id &&
        descending_sort?
    end

    # Private: Determines if the sort by direction is descending
    #
    # Returns: Boolean
    def descending_sort?
      sort_by.first[:direction] == "desc"
    end
  end
end
