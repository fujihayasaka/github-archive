# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable


  # Encapsulates options for querying and processing grouped results from Elasticsearch via MemexProjectItemQuery.
  #
  # Consumer specified options are set as part of the constructor.
  # Internal attributes used to support desired consumer options are set separately via set_* methods.
  class Options

    # Capped by Elasticsearch via index.max_inner_result_window which defaults to 100.
    # We cap at one less to allow for a lookahead to determine if there is a next page.
    MAX_GROUPED_ITEMS_PAGE_SIZE = 99

    # Ths sum of items across all requested groups must not exceed this value.
    TOTAL_ITEM_LIMIT = Search::Queries::MemexProjectItemQuery::MAX_PAGE_SIZE

    # The database ID of the MemexProjectColumn::Field::Base object that we would like to group by.
    sig { returns(MemexProjectColumn::Field::Base) }
    attr_reader :field

    # The cursor that identifies the start of a page of groups. The particular item identified by this cursor is
    # omitted (we return the first one after it).
    sig { returns(T.nilable(PaginatedGroups::AfterKey)) }
    attr_reader :cursor

    sig { returns(MissingValueGroupOrder) }
    attr_reader :missing_value_group_order

    # The maximum number of groups to return in paged results
    sig { returns(Integer) }
    attr_reader :groups_page_size

    # The maximum number of paged items to return within each group
    # When secondary grouping is specified, the primary group's grouped_items_page_size is used.
    sig { returns(Integer) }
    attr_reader :grouped_items_page_size

    # Whether or not to return groups that do not contain any items
    sig { returns(T::Boolean) }
    attr_reader :include_empty_groups

    # Whether or not to include metadata about each group
    sig { returns(T::Boolean) }
    attr_reader :include_group_metadata

    # Whether or not to ignore grouping sort option (for board view)
    sig { returns(T::Boolean) }
    attr_reader :ignore_group_sort

    # Optional options when specifying secondary grouping
    sig { returns(T.nilable(Options)) }
    attr_reader :secondary_grouping_options

    # Whether or not this represents options for secondary grouping (internally set)
    sig { returns(T::Boolean) }
    attr_reader :is_secondary

    # Sort direction for the groups
    sig { returns(T.nilable(String)) }
    attr_reader :sort_direction

    # Optional filtering to apply, typically for limiting empty static groups (internally set)
    sig { returns(T.nilable(T::Array[Search::Memex::Nodes::Qualifier])) }
    attr_reader :group_filters

    sig do
      params(
        field_object_or_id: T.any(Integer, MemexProjectColumn::Field::Base),
        cursor: T.nilable(String),
        missing_value_group_order: MissingValueGroupOrder,
        groups_page_size: T.nilable(Integer),
        grouped_items_page_size: T.nilable(Integer),
        include_empty_groups: T::Boolean,
        include_group_metadata: T::Boolean,
        ignore_group_sort: T::Boolean,
        secondary_grouping_options: T.nilable(Options)
      )
      .void
    end
    def initialize(
      field_object_or_id:,
      cursor: nil,
      missing_value_group_order: MissingValueGroupOrder::Last,
      groups_page_size: nil,
      grouped_items_page_size: nil,
      include_empty_groups: false,
      include_group_metadata: false,
      ignore_group_sort: false,
      secondary_grouping_options: nil
    )
      field = field_object_or_id
      unless field.is_a?(MemexProjectColumn::Field::Base)
        field = MemexProjectColumn.find_by(id: field_object_or_id)&.to_field
      end
      raise ArgumentError, "Could not retrieve field with ID #{field_object_or_id}" unless field.present?

      @field = T.let(field, MemexProjectColumn::Field::Base)
      @missing_value_group_order = missing_value_group_order
      @include_empty_groups = include_empty_groups
      @include_group_metadata = include_group_metadata
      @is_secondary = T.let(false, T::Boolean)
      @ignore_group_sort = T.let(ignore_group_sort, T::Boolean)
      @group_filters = T.let(nil, T.nilable(T::Array[Search::Memex::Nodes::Qualifier]))
      @sort_direction = T.let(nil, T.nilable(String))

      @secondary_grouping_options = secondary_grouping_options
      if @secondary_grouping_options.present?
        if @secondary_grouping_options.has_secondary_grouping?
          raise(ArgumentError, "Only two levels of grouping options are supported")
        end
        unless @field.static_groups?
          raise(ArgumentError, "Primary group field must have static values when secondary grouping is used (example: single-select and iteration fields)")
        end
        @secondary_grouping_options.set_is_secondary(true)
      end

      begin
        resolved_cursor = T.cast(Search::Responses::PropertyEncoder.resolve(cursor), T.nilable(PaginatedGroups::AfterKey))
      rescue Platform::Errors::Cursor, TypeError
        raise Search::Queries::CursorPagination::ParameterError, "#{cursor} does not appear to be a valid group cursor"
      end
      @cursor = T.let(resolved_cursor, T.nilable(PaginatedGroups::AfterKey))

      @groups_page_size = T.let(
        compute_groups_page_size(field:, groups_page_size:),
        Integer
      )

      @grouped_items_page_size = T.let(
        compute_grouped_items_page_size(groups_page_size: @groups_page_size, grouped_items_page_size:),
        Integer
      )

      # Throw if we're accidentally requesting too many items at once from Elasticsearch (groups x items per group)
      total_items_requested = @groups_page_size * @grouped_items_page_size
      if total_items_requested > TOTAL_ITEM_LIMIT
        raise(
          ArgumentError,
          "groups_page_size (#{@groups_page_size}) * grouped_items_page_size (#{@grouped_items_page_size}) must be " +
          "<= #{TOTAL_ITEM_LIMIT}"
        )
      end
    end

    # The Symbol group aggregation key, prefixed by "primary_" or "secondary_" if secondary grouping is used.
    sig { returns(Symbol) }
    def group_by_key_symbol
      "#{key_prefix}#{field.group_by_key}".to_sym
    end

    # The no_group_value aggregation key, prefixed by "primary_" or "secondary_" if secondary grouping is used.
    sig { returns(Symbol) }
    def no_group_value_key
      "#{key_prefix}no_group_value".to_sym
    end

    # Returns true only if these options represent a primary group with non-nil secondary group options
    sig { returns(T::Boolean) }
    def has_secondary_grouping?
      secondary_grouping_options.present?
    end

    sig { returns(T::Boolean) }
    def add_group_metadata?
      @include_group_metadata && field.has_group_metadata?
    end

    # Whether or not this represents options for secondary grouping.
    # Consumers of MemexProjectItemQuery do not need to set this,
    # as it is implied by providing a secondary_grouping_options param.
    sig { params(value: T::Boolean).void }
    def set_is_secondary(value)
      @is_secondary = value
    end

    # Optional filtering to apply, typically for limiting empty static groups.
    # Consumers of MemexProjectItemQuery do not need to set this,
    # as it is derived from the general query provided for Elasticsearch.
    sig { params(value: T.nilable(T::Array[Search::Memex::Nodes::Qualifier])).void }
    def set_group_filters(value)
      @group_filters = value
    end

    # Optional group sort order to apply.
    # Consumers of MemexProjectItemQuery do not need to set this,
    # as it is derived from the sort_params provided to MemexProjectItemQuery.
    sig { params(value: String).void }
    def set_sort_direction(value)
      @sort_direction = value
    end

    sig do
      params(
        field: MemexProjectColumn::Field::Base,
        groups_page_size: T.nilable(Integer),
      )
      .returns(Integer)
    end
    private def compute_groups_page_size(field:, groups_page_size:)
      if groups_page_size.present?
        groups_page_size
      else
        DEFAULT_GROUPS_PAGE_SIZE
      end
    end

    sig { params(groups_page_size: Integer, grouped_items_page_size: T.nilable(Integer)).returns(Integer) }
    private def compute_grouped_items_page_size(groups_page_size:, grouped_items_page_size:)
      result = if groups_page_size == 0 && grouped_items_page_size.nil?
        0
      elsif grouped_items_page_size.nil?
        optimal_page_size = [(Search::Queries::MemexProjectItemQuery::MAX_PAGE_SIZE / groups_page_size).floor, 1].max
        [MAX_GROUPED_ITEMS_PAGE_SIZE, optimal_page_size].min
      else
        grouped_items_page_size
      end

      if result > MAX_GROUPED_ITEMS_PAGE_SIZE
        raise(
          ArgumentError,
          "grouped_items_page_size (#{result}) must be <= #{MAX_GROUPED_ITEMS_PAGE_SIZE}"
        )
      end

      result
    end

    sig { returns(String) }
    private def key_prefix
      return "primary_" if has_secondary_grouping?
      return "secondary_" if is_secondary
      ""
    end
  end
end
