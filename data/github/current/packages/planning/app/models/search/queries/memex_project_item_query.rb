# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    # This class is used to query the Elasticsearch index that stores memex project items.
    #
    # USAGE:
    #
    #   query = Search::Queries::MemexProjectItemQuery.new(project:, query: "is:issue")
    #   query.execute # Returns `Search::Responses::MemexProjectItemResponse` or `Search::Responses::GroupedMemexProjectItemResponse`
    class MemexProjectItemQuery < ::Search::Query
      include GitHub::Memoizer
      include CursorPagination

      # Abbreviation to improve readability of types in this module.
      ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

      DEFAULT_PAGE_SIZE = 100
      MAX_PAGE_SIZE = 250

      sig do
        # Return only distinct values for a given field, omitting the actual items.
        #
        # @param project Only items that belong to this project will be returned in results.
        # @param viewer Optional User for whom results should be authorized. `nil`, the default, represents an
        #   anonymous user (e.g. viewing a public project when logged out).
        # @param field_id The field id for which distinct values are to be returned.
        # @param items_scope Only items that match the given scope will be returned in results.
        # @param cap_filter: Optional filter to satisfy conditional access policies for items referencing issues in SSO orgs.
        # @param include_metadata: Optionally include metadata about the value
        params(
          project: MemexProject,
          viewer: T.nilable(User),
          field_id: Integer,
          items_scope: Search::Memex::Context::MemexProjectItemsScope,
          cap_filter: T.nilable(ConditionalAccess::Filter),
          include_metadata: T::Boolean
        )
        .returns(MemexProjectItemQuery)
      end
      def self.distinct_values_query(
        project:,
        viewer:,
        field_id:,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
        cap_filter: nil,
        include_metadata: false
      )
        # Distinct values can be returned for a given field by specifying the field's id as the `slice_by`, and flagging
        # that slices_only should be returned.
        new(project:, viewer:, slice_by: field_id, slices_only: true, include_slice_metadata: include_metadata, items_scope:, source_fields: [], cap_filter:)
      end

      sig do
        # Initializes a search request with limited parameters applicable to public ProjectV2 GraphQL usage,
        # specifically for returning paginated ProjectV2Items.
        # See object schema at https://docs.github.com/en/graphql/reference/objects#projectv2
        # The request can later be issued with the `execute` method.
        # # @param project Only items that belong to this project will be returned in results.
        # @param viewer Optional User for whom results should be authorized. `nil`, the default, represents an
        #   anonymous user (e.g. viewing a public project when logged out).
        # @param items_scope Only items that match the given scope will be returned in results.
        # @param cap_filter: Optional filter to satisfy conditional access policies for items referencing issues in SSO orgs.
        # @param reverse_priority Whether to return paginated items in reversed priority order.
        #   `false`, the default, returns items as they would appear from top to bottom in an unsorted Memex table.
        #   `true` returns items in reverse order, from the bottom up.
        #   This supports GraphQL POSITION ordering.  See https://docs.github.com/en/graphql/reference/input-objects#projectv2itemorder
        # @param after Cursor that defines the first item to return when paginating forwards through results.
        # @param before cursor that defines the first item to return when paginating backwards through results.
        # @param first The number of results to return on a page when paginating forward through results.
        # @param last The number of results to return on a page when paginating backwards through results.
        params(
          project: MemexProject,
          viewer: T.nilable(User),
          items_scope: Search::Memex::Context::MemexProjectItemsScope,
          cap_filter: T.nilable(ConditionalAccess::Filter),
          reverse_priority: T::Boolean,
          after: T.nilable(String),
          before: T.nilable(String),
          first: T.nilable(Integer),
          last: T.nilable(Integer),
        ).returns(MemexProjectItemQuery)
      end
      def self.graphql_query(
        project:,
        viewer:,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
        cap_filter: nil,
        reverse_priority: false,
        after: nil,
        before: nil,
        first: nil,
        last: nil
      )
        new(
          project:,
          viewer:,
          items_scope:,
          cap_filter:,
          graphql_reverse_priority: reverse_priority,
          remove_spam: true,
          after:, before:, first:, last:
        )
      end

      # Initializes a search request for aggregated insights charts data per the specified chart_options.
      #
      # @param project Only items that belong to this project will be returned in results.
      # @param viewer Optional User for whom results should be authorized. `nil`, the default, represents an
      #   anonymous user (e.g. viewing a public project when logged out).
      # @param cap_filter: Optional filter to satisfy conditional access policies (CAP) for items referencing issues in SSO orgs.
      # @param include_project_item_owner_ids Optionally return all item owner ids in the project for org CAP checks to prompt users for SSO.
      # @param items_scope Only items that match the given scope will be returned in results.
      # @query The search query to execute.
      # @param source_fields The subset of fields from the document that was originally stored in Elasticsearch that
      #   should be included in the search results. Can also be specified as `true` to indicate that all field should
      #   be retrieved, or `false` to indicate that none of the fields should be retrieved.
      # @param chart_options Options for requesting aggregated Insights chart data instead of items, or `nil` if a chart is not requested.
      sig do
        params(
          project: MemexProject,
          viewer: T.nilable(User),
          cap_filter: T.nilable(ConditionalAccess::Filter),
          include_project_item_owner_ids: T.nilable(T::Boolean),
          items_scope: Search::Memex::Context::MemexProjectItemsScope,
          query: String,
          source_fields: T.any(T::Array[String], T::Boolean),
          chart_options: T.nilable(MemexProjectColumn::Interface::Chartable::Options)
        ).returns(MemexProjectItemQuery)
      end
      def self.insights_query(
          project:,
          viewer: nil,
          cap_filter: nil,
          include_project_item_owner_ids: nil,
          items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
          query: "",
          source_fields: ["database_id"],
          chart_options: nil
        )
        new(
          project:,
          viewer: nil,
          cap_filter:,
          include_project_item_owner_ids: nil,
          items_scope:,
          query:,
          source_fields:,
          chart_options:
        )
      end

      # Initializes a search request. That request can later be issued by with the `execute` method.
      #
      # @param project Only items that belong to this project will be returned in results.
      # @param viewer Optional User for whom results should be authorized. `nil`, the default, represents an
      #   anonymous user (e.g. viewing a public project when logged out).
      # @param cap_filter: Optional filter to satisfy conditional access policies (CAP) for items referencing issues in SSO orgs.
      # @param include_project_item_owner_ids Optionally return all item owner ids in the project for org CAP checks to prompt users for SSO.
      # @param items_scope Only items that match the given scope will be returned in results.
      # @query The search query to execute.
      # @param sort The Elasticsearch fragment to use for sorting the query.
      # @param sort_param The sort parameters to use for the query. Used for ensuring the grouped query is sorted by the correct field.
      # @param source_fields The subset of fields from the document that was originally stored in Elasticsearch that
      #   should be included in the search results. Can also be specified as `true` to indicate that all field should
      #   be retrieved, or `false` to indicate that none of the fields should be retrieved.
      # @param chart_options Options for requesting aggregated Insights chart data instead of items, or `nil` if a chart is not requested.
      # @param group_value_filters Used to add an additional filter to limit results to items within a specific group or groups.
      # @param grouping_options Options for grouping items in the query response, or `nil` if grouping is not requested.
      # @param slice_by The slice field Id if total item counts are desired for each slice field value.
      # @param slice_value The slice value when requesting a page of items with the specified value for the slice_by field.
      # @param slices_only Whether to return only distinct values for a given slice/field, omitting the actual items.
      #   Note that it is preferable to call the `distinct_values_query` class method rather than passing this in directly.
      # @param include_empty_slices for slices aggregation, include all slice field values in the project outside the query filter.
      # @param include_slice_metadata for slices aggregation, include metadata about the slice value
      # @param first The number of results to return on a page when paginating forward through results.
      #   This applies to project items in cases when they are not grouped or when requesting subsequent
      #   pages of items within a single group (i.e., when group_value is specified).
      # @param last The number of results to return on a page when paginating backwards through results.
      # @param after Cursor that defines the first item to return when paginating forwards through results.
      # @param before cursor that defines the first item to return when paginating backwards through results.
      # @param graphql_reverse_priority Whether to reverse the priority order of the resultset. `false`, the default,
      #  sorts the result set in descending order, otherwise in ascending order. This is used for GraphQL queries only!
      # @param remove_spam Remove spammy items from the page of results returned from this response. Note that if spam
      #   is atually present, the number of items in the returned page may be less than the number the caller
      #   requested with the `first` parameter.
      #   Note: Soon, spam will always be removed as part of the MemexProjectItemQueryRedactor behind feature flag memex_mwl_spam_redaction.
      #   When memex_mwl_spam_redaction if fully deployed, we can remove the remove_spam param and update consuming code.
      #
      # @raises Search::Queries::CursorPagination::Parameter when given an invalid combination of the `first`, `last`,
      #   `after` and `before` params.
      sig do
        params(
          project: MemexProject,
          viewer: T.nilable(User),
          cap_filter: T.nilable(ConditionalAccess::Filter),
          include_project_item_owner_ids: T.nilable(T::Boolean),
          items_scope: Search::Memex::Context::MemexProjectItemsScope,
          query: String,
          source_fields: T.any(T::Array[String], T::Boolean),
          chart_options: T.nilable(MemexProjectColumn::Interface::Chartable::Options),
          sort: CursorPagination::Sort,
          sort_params: MemexProjectColumn::Interface::Sortable::Params,
          group_value_filters: T.nilable(T::Array[MemexProjectColumn::Interface::Queryable::FieldValueFilter]),
          grouping_options: T.nilable(MemexProjectColumn::Interface::Groupable::Options),
          slice_by: T.nilable(Integer),
          slice_value: T.nilable(String),
          slices_only: T.nilable(T::Boolean),
          include_empty_slices: T.nilable(T::Boolean),
          include_slice_metadata: T::Boolean,
          first: T.nilable(Integer),
          last: T.nilable(Integer),
          after: T.nilable(String),
          before: T.nilable(String),
          graphql_reverse_priority: T.nilable(T::Boolean),
          remove_spam: T::Boolean,
          item_ids: T.nilable(T::Array[Integer])
        )
        .void
      end
      def initialize(
          project:,
          viewer: nil,
          cap_filter: nil,
          include_project_item_owner_ids: nil,
          items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
          query: "",
          source_fields: ["database_id"],
          chart_options: nil,
          sort: [],
          sort_params: [],
          group_value_filters: nil,
          grouping_options: nil,
          slice_by: nil,
          slice_value: nil,
          slices_only: false,
          include_empty_slices: nil,
          include_slice_metadata: false,
          first: nil,
          last: nil,
          after: nil,
          before: nil,
          graphql_reverse_priority: nil,
          remove_spam: false,
          item_ids: nil
        )
        @index = T.let(Elastomer::Indexes::MemexProjectItems.new, Elastomer::Indexes::MemexProjectItems)
        @memex_project = project
        @current_user = viewer
        @include_project_item_owner_ids = include_project_item_owner_ids
        @items_scope = items_scope
        @sort_params = sort_params

        slice_value_filter = if slice_by.present? && slice_value.present?
          MemexProjectColumn::Interface::Queryable::FieldValueFilter.new(field_object_or_id: slice_by, field_value: slice_value)
        end

        @chart_options = chart_options

        @grouping_options = grouping_options
        initialize_group_order(@grouping_options) if @grouping_options.present? && @sort_params.present?
        # The top-level Elasticsearch query is adjusted to include any default group filtering as if provided by the consumer.
        default_group_query = initialize_group_filters(query:) if @grouping_options.present?
        adjusted_query = [query, default_group_query].compact.join(" ").strip

        @query_string = T.let(resolve_query(adjusted_query, group_value_filters, slice_value_filter), String)

        @slice_by = slice_by
        @slices_only = slices_only
        slice_by_field&.include_empty_slices = slice_by.present? && include_empty_slices
        slice_by_field&.include_slice_metadata = include_slice_metadata

        @global_query_string = T.let(
          resolve_global_query(adjusted_query, group_value_filters, slice_value_filter),
          T.nilable(String)
        )
        @query_redactor = T.let(MemexProjectItemQueryRedactor.new(
          viewer: viewer,
          cap_filter: cap_filter
        ), MemexProjectItemQueryRedactor)
        @graphql_reverse_priority = graphql_reverse_priority
        @remove_spam = T.let(@query_redactor.memex_mwl_spam_redaction_enabled? ? false : remove_spam, T::Boolean)

        @item_ids = item_ids

        super({
          current_user:,
          first:,
          last:,
          after: exclude_items_from_results? ? nil : after,
          before:,
          sort:,
          source_fields:,
          aggregations: [grouping_options&.field&.id,  @slice_by.present? ? "slice_by" : nil, "repository_ids"].compact,
        })
      end

      # This provides the URL query params that are passed to the ES /_search endpoint.
      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_params
        { routing: @memex_project.id }
      end

      # This is the inner object that is set as the value of the `query` key
      # in the overall /_search endpoint payload built by `Search::Query#query_document`.
      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_doc
        build_filter_query(query: @query_string, context: build_context)
      end

      # overrides Search::Queries::CursorPagination#query_document
      #
      # This is the overall JSON body that gets passed to the ES /_search endpoint.
      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_document
        result = super
        # By default, searches containing an aggregation return both search hits and aggregation results.
        # To return only aggregation results, set size to 0
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html#return-only-agg-results
        exclude_items_from_results? ? result.merge({ size: 0 }) : result
      end

      # This is the inner object that is set as the value of the `aggregations` key
      # in the overall /_search endpoint payload built by `Search::Query#query_document`.
      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_aggregations
        aggregations = ElasticsearchRequest::Aggregation::Collection.new
        if !@check_redactions_in_global_slices && requires_redactor_aggregation?
          aggregations.concat(@query_redactor.redactions_aggregations)
        end
        if requires_global_aggregation?
          aggregations.push(build_global_aggregation)
        elsif slice_by_field
          aggregations.concat(T.must(slice_by_field).slice_by_fragment)
        end
        if grouped_query?
          options = T.must(@grouping_options)
          aggregations.concat(options.field.group_by_fragment(sort: @sort, source_fields:, options:))
        end
        if insights_query?
          options = T.must(@chart_options)
          aggregations.concat(options.x_axis_field.chart_fragment(options:))
        end
        aggregations.to_hash
      end

      # As part of building the MemexProjectItemResponse from the raw Elasticsearch response,
      # process and merge group and slice aggregation results into the options hash.
      sig do
        override
        .params(
          response_class: T.class_of(Search::Results),
          elasticsearch_response: T.nilable(T::Hash[String, T.untyped]),
          options: T::Hash[Symbol, T.untyped],
        )
        .returns(Search::Results[T.untyped])
      end
      def build_response(response_class, elasticsearch_response, options)
        if elasticsearch_response
          aggregation_results = elasticsearch_response.fetch("aggregations", {})

          # Unnest and merge global project and view filtered aggregations if a global aggregation was required
          global_aggregations = aggregation_results["global_aggregations"]
          if global_aggregations.present?
            project_aggregations = global_aggregations["project_filter"]
            view_aggregations = project_aggregations.present? ? project_aggregations["project_view_filter"] : global_aggregations["project_view_filter"]
            aggregation_results.merge!(view_aggregations) if view_aggregations.present?
            aggregation_results.merge!(project_aggregations) if project_aggregations.present?
          end

          # If include_project_item_owner_ids, determine all project item owners (for CAP SSO banner on Memex project UI)
          if @include_project_item_owner_ids && !@query_redactor.has_checked_for_redactions?
            project_repository_agg = aggregation_results["project_repository_ids"] || aggregation_results["repository_ids"]
            repo_buckets = project_repository_agg&.dig("buckets") || []
            repo_ids = repo_buckets&.map { |b| b.dig("key") }.compact
            repositories = Repository.where(id: repo_ids).to_a if repo_ids.present?
            @project_repositories = T.let(repositories, T.nilable(T::Array[Repository]))
            @project_item_owner_ids = T.let(@project_repositories&.map { |repo| repo.owner_id }&.uniq, T.nilable(T::Array[Integer]))
          end
          options.merge!({ project_item_owner_ids: @project_item_owner_ids }) if @include_project_item_owner_ids

          if grouped_query?
            grouping_options = T.must(@grouping_options)
            primary_groups = grouping_options.field.paginated_groups(aggregation_results:, options: grouping_options)
            options.merge!({ primary_groups: }) if primary_groups

            if secondary_grouped_query?
              secondary_options = T.must(@grouping_options&.secondary_grouping_options)
              secondary_groups = secondary_options.field.paginated_groups(aggregation_results:, options: secondary_options)
              options.merge!({ secondary_groups: }) if secondary_groups
            end

            grouped_items = grouping_options.field.grouped_items(aggregation_results:, options: grouping_options, primary_groups:, secondary_groups:)
            options.merge!({ grouped_items: }) if grouped_items
          end

          if slice_by_field
            is_es_8_response = elasticsearch_response.dig("hits", "total").is_a?(Hash)
            total_hits = is_es_8_response ? elasticsearch_response.dig("hits", "total", "value") : elasticsearch_response.dig("hits", "total").to_i
            slices = slice_by_field&.unnest_slices(aggregation_results:, total_hits:)
            options.merge!(slices) if slices
          end

          if insights_query?
            chart_options = T.must(@chart_options)
            chart_data = chart_options.x_axis_field.chart_data(aggregation_results:, options: chart_options)
            options.merge!({ chart_data: }) if chart_data
          end
        end

        options.merge!({ viewer: @current_user, remove_spam: @remove_spam })
        super(response_class, elasticsearch_response, options)
      end

      # Overrides base class `execute` method in order to instruct it to return our custom `results_class`
      # (Search::Responses::MemexProjectItemResponse).
      sig do
        override
        .params(skip_prune_results: T::Boolean, results_class: T.class_of(Search::Results))
        .returns(T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse))
      end
      def execute(skip_prune_results: false, results_class: Search::Responses::MemexProjectItemResponse)
        result_class = grouped_query? ? Search::Responses::GroupedMemexProjectItemResponse : results_class
        response = T.cast(super(skip_prune_results: skip_prune_results, results_class: result_class),
          T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse))
        if requires_requery_for_redactions?(response, prefilled_repositories: @project_repositories || [])
          execute
        else
          response.set_redactor_results(@query_redactor.results)
          response
        end
      end

      sig { override.params(opts: T::Hash[T.untyped, T.untyped]).returns(Sort) }
      def resolve_sort!(opts)
        # First prioritize sort parameters passed in via the `sort` option argument
        raw_sort = opts.fetch(:sort, [])
        return raw_sort if @slices_only

        raw_sort + [
          default_priority_sort_value,
          {
            # This is a tiebreaker sort value that's guaranteed to be unique for each item
            #
            # Tiebreakers are recommended when not querying with Point In Time
            # (PIT) queries add an implicit tie-breaker, but they can generate stale
            # results, so we've opted not to use them.
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
            database_id: "asc"
          }
        ]
      end

      sig { returns(T.any({ priority: String }, { virtual_priority: String })) }
      private def default_priority_sort_value
        # User-defined priority value
        { virtual_priority: @graphql_reverse_priority ? "asc" : "desc" }
      end

      sig { override.returns(Integer) }
      def max_page_size
        MAX_PAGE_SIZE
      end

      sig { override.returns(Integer) }
      def default_page_size
        DEFAULT_PAGE_SIZE
      end

      # Returns an updated query string that includes additional filtering constraints
      # on the group and/or slice fields with the value(s) specified for each.
      sig do
        params(
          query: String,
          group_value_filters: T.nilable(T::Array[MemexProjectColumn::Interface::Queryable::FieldValueFilter]),
          slice_value_filter: T.nilable(MemexProjectColumn::Interface::Queryable::FieldValueFilter)
        )
        .returns(String)
      end
      def resolve_query(query, group_value_filters, slice_value_filter)
        ([query] + [*group_value_filters, slice_value_filter].compact.map(&:filter_term)).join(" ")
      end

      # Returns the non-nil query string to be used in a global aggregation, if a global aggregation is required.
      sig do
        params(
          query: String,
          group_value_filters: T.nilable(T::Array[MemexProjectColumn::Interface::Queryable::FieldValueFilter]),
          slice_value_filter: T.nilable(MemexProjectColumn::Interface::Queryable::FieldValueFilter)
        )
        .returns(T.nilable(String))
      end
      def resolve_global_query(query, group_value_filters, slice_value_filter)
        requires_global_repositories = @include_project_item_owner_ids && @query_string.length > 0
        requires_global_slices = @slice_by.present? && (slice_value_filter.present? || group_value_filters.present? || fetch_empty_slices?)
        @check_redactions_in_global_slices = T.let(requires_global_slices, T.nilable(T::Boolean))
        query if requires_global_repositories || requires_global_slices
      end

      sig { returns(Search::Memex::Context) }
      def build_context
        Search::Memex::Context.new(
          memex_project: @memex_project,
          viewer: @current_user,
          items_scope: @items_scope,
        )
      end

      sig { returns(T::Boolean) }
      def grouped_query?
        @grouping_options.present?
      end

      sig { returns(T::Boolean) }
      def insights_query?
        @chart_options.present?
      end

      sig { returns(T::Boolean) }
      def secondary_grouped_query?
        grouped_query? && T.must(@grouping_options).has_secondary_grouping?
      end

      # The MemexProjectColumn::Field::Base for the requested slice_by parameter, if any.
      # This uses the same field Id key as for grouping.
      sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
      memoize def slice_by_field
        find_field_by_group_by_key(@slice_by)
      end

      sig do
        params(group_by: T.nilable(Integer))
        .returns(T.nilable(MemexProjectColumn::Field::Base))
      end
      def find_field_by_group_by_key(group_by)
        return unless group_by
        project_fields.find { |field| field.group_by_key == group_by }
      end

      sig { returns(T::Array[MemexProjectColumn::Field::Base]) }
      memoize def project_fields
        T.let(@memex_project.columns.map(&:to_field), T::Array[T.nilable(MemexProjectColumn::Field::Base)]).compact
      end

      # Returns true if a global aggregation is required for an aggregation outside the main query view filter
      sig { returns(T::Boolean) }
      def requires_global_aggregation?
        !@global_query_string.nil?
      end

      sig { returns(T.nilable(T::Boolean)) }
      def fetch_empty_slices?
        slice_by_field&.include_empty_slices && !slice_by_field&.known_slices?
      end

      # Returns the global aggregation fragment if needed for getting slice value counts.
      # This is required when a slice_value or group_value filter is applied to the main Elasticsearch query for project items.
      # The global aggregation uses a more general filter(s), and includes repository_ids for redactions.
      # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/search-aggregations-bucket-global-aggregation.html
      sig { returns(ElasticsearchRequest::Aggregation::Global) }
      def build_global_aggregation
        query = @global_query_string || ""
        requires_project_aggregation = query.length > 0 && (@include_project_item_owner_ids || fetch_empty_slices?)
        requires_view_aggregation = slice_by_field.present?
        nested_view_aggregation = view_filter_aggregation(query:, is_nested: true) if requires_project_aggregation && requires_view_aggregation
        global_subaggregations = ElasticsearchRequest::Aggregation::Collection.new

        if nested_view_aggregation.present?
          global_subaggregations.push(project_filter_aggregation(nested_view_aggregation))
        elsif requires_view_aggregation
          global_subaggregations.push(T.must(view_filter_aggregation(query:)))
        else
          global_subaggregations.push(project_filter_aggregation)
        end

        ElasticsearchRequest::Aggregation::Global.new(
          slug: :global_aggregations,
          aggs: global_subaggregations
        )
      end

      sig { returns(T::Boolean) }
      private def exclude_items_from_results?
        return true if grouped_query? || @slices_only || @chart_options
        false
      end

      # Returns a view filter aggregation fragment used as part of a global aggregation.
      # If this is intended to be nested within a project_filter_aggregation,
      # then it could return nil because of an invalid, ignored field filter such as "xxx:yyy".
      sig { params(query: String, is_nested: T::Boolean).returns(T.nilable(ElasticsearchRequest::Aggregation::Filter)) }
      def view_filter_aggregation(query:, is_nested: false)
        context = build_context
        context.options.skip_project_scope = is_nested
        context.options.skip_items_scope = is_nested
        filter = build_filter_query(query:, context:, include_redactor_filter: !is_nested)
        return if is_nested && filter.blank?

        aggs = slice_by_field&.slice_by_fragment || ElasticsearchRequest::Aggregation::Collection.new
        aggs.concat(@query_redactor.redactions_aggregations) if requires_redactor_aggregation?
        ElasticsearchRequest::Aggregation::Filter.new(
          slug: :project_view_filter,
          filter:,
          aggs:
        )
      end

      # Returns a project filter aggregation fragment used as part of a global aggregation.
      sig do
        params(nested_view_filter_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Filter))
        .returns(ElasticsearchRequest::Aggregation::Filter)
      end
      def project_filter_aggregation(nested_view_filter_aggregation = nil)
        project_aggs = ElasticsearchRequest::Aggregation::Collection.new
        if fetch_empty_slices?
          project_aggs.concat(T.must(slice_by_field).slice_by_fragment(key_prefix: "project_"))
          project_aggs.concat(@query_redactor.redactions_aggregations) if requires_redactor_aggregation?
        elsif @include_project_item_owner_ids && requires_redactor_aggregation?
          project_aggs.concat(@query_redactor.redactions_aggregations(key_prefix: "project_"))
        end
        project_aggs.push(nested_view_filter_aggregation) if nested_view_filter_aggregation.present?
        ElasticsearchRequest::Aggregation::Filter.new(
          slug: :project_filter,
          filter: build_filter_query(query: "", context: build_context),
          aggs: project_aggs
        )
      end

      sig do
        params(
          query: String,
          context: Search::Memex::Context,
          include_redactor_filter: T::Boolean
        )
        .returns(T::Hash[T.untyped, T.untyped])
      end
      def build_filter_query(query:, context:, include_redactor_filter: true)
        filter = Search::Memex::AST.parse(query).compile(context)
        # Apply the same redacted repositories filter to the outer global aggregation filter to avoid leaking sliced values/counts data.
        if include_redactor_filter && @query_redactor.has_redactions?
          filter.dig(:bool, :filter)&.concat(@query_redactor.redactions_query_fragment)
        end

        if @item_ids.present?
          filter.dig(:bool, :filter)&.push({ terms: { database_id: @item_ids } })
        end

        filter
      end

      sig { returns(T::Boolean) }
      private def requires_redactor_aggregation?
        !@query_redactor.has_checked_for_redactions?
      end

      sig do
        params(
          response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse),
          prefilled_repositories: T::Array[Repository]
        ).returns(T::Boolean)
      end
      private def requires_requery_for_redactions?(response, prefilled_repositories:)
        return false if @query_redactor.has_checked_for_redactions?
        @query_redactor.check_for_redactions(response, prefilled_repositories:)
        @query_redactor.has_redactions?
      end

      # Initializes grouping options passed in from the caller with additional context provided from other arguments if needed.
      # For example, adds sort order from the sort_params argument to the grouping options
      # Returns the modified grouping ooptions
      sig { params(options: MemexProjectColumn::Interface::Groupable::Options).returns(MemexProjectColumn::Interface::Groupable::Options) }
      def initialize_group_order(options)
        grouped_field_id = options.field.id
        return options if @sort_params.empty?
        sort_param_for_group_by_field = @sort_params.find { |s| s.column_id == grouped_field_id }
        return options unless sort_param_for_group_by_field
        options.set_sort_direction(sort_param_for_group_by_field.direction)
        options
      end

      # Initializes group filtering from the provided query param, if applicable.
      # Returns a default group query string to be appended to the main Elasticsearch query, if applicable.
      #
      # This would typically be used for limiting empty static groups (i.e., Single-Select and Iteration fields).
      # For example, an Iteration field with no other filtering may default to "-Iteration:<@current-3".
      sig { params(query: T.nilable(String)).returns(T.nilable(String)) }
      def initialize_group_filters(query:)
        all_groups_options = [@grouping_options, @grouping_options&.secondary_grouping_options].compact
        all_default_groups_queries = T.let(Set.new, T::Set[String])

        all_groups_options.each do |options|
          group_filters = Search::Memex::AST.parse(query).find_nodes_by_query_slug(options.field.query_slug).presence if query.present?
          if group_filters.present?
            # Set the group filter if the main query includes any filtering on the grouped field.
            options.set_group_filters(group_filters)
          else
            # If the main query does not include any filtering on the grouped field, then check if the group field provides a default query.
            default_group_query = options.field.default_group_query(options:)
            if default_group_query.present?
              default_filter = Search::Memex::AST.parse(default_group_query).find_nodes_by_query_slug(options.field.query_slug).presence
              options.set_group_filters(default_filter)
              all_default_groups_queries.add(default_group_query)
            end
          end
        end

        all_default_groups_queries.join(" ").presence
      end
    end
  end
end
