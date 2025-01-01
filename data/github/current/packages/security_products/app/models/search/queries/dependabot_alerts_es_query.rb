# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class DependabotAlertsEsQuery < ::Search::Query
      include CursorPagination

      DEFAULT_PAGE_SIZE = 25
      MAX_PAGE_SIZE = 25

      def max_page_size
        MAX_PAGE_SIZE
      end

      def default_page_size
        DEFAULT_PAGE_SIZE
      end

      # Examples:
      #
      #   resolve_sort!( { phrase: "sort:updated" } )
      #   #=> [{'pushed_at' => 'desc'}, {'repo_id' => 'asc'}]
      #
      #   resolve_sort!( { phrase: "sort:updated sort:name-asc" } )
      #   #=> [{'pushed_at' => 'desc'}, {'name_sort' => 'asc'}, {'repo_id' => 'asc'}]
      sig { override.params(opts: T::Hash[Symbol, String]).returns(Sort) }
      def resolve_sort!(opts)
        sort_output = []

        sort_method_output = sort
        if sort_method_output.present?
          # Use build_sort_section to map Array tuple input (["updated", "desc"])
          #   to mapped output Hash ({ "pushed_at" => "desc" })
          built_sort = build_sort_section(sort_method_output, SORT_MAPPINGS)
          built_sort = handle_unidirectional_sorts(built_sort)
          sort_output.push(built_sort)
        end

        sort_output.push(
          # Any searches without an explicit sort should default to sorting by the relevance score. We tune this
          # with custom signals and market it to customers as our custom "importance score".
          { "_score" => "desc" },
          # `id` is a tiebreaker sort value that's guaranteed to be unique for each item
          #
          # Tiebreakers are recommended when not querying with Point In Time
          # (PIT) queries add an implicit tie-breaker, but they can generate stale
          # results, so we've opted not to use them.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
          { "id" => "asc" },
        )
        sort_output.compact.flatten
      end

      # The set of fields that will be transformed into filters when performing an alerts query:
      # https://www.elastic.co/docs/explore-analyze/query-filter/languages/querydsl#query-filter-context
      def self.field_list
        [
          :is, :state, :severity, :repo, :sort, :package, :ecosystem, :has, :resolution, :relationship, :"epss-percentage", :scope,
        ].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [
          :sort, :state, :severity, :relationship, :has, :ecosystem
        ]
      end

      # Enable memex-style 'or' search for certain Dependabot alert fields. This value gets passed to `Search::ParsedQuery.new`,
      # `Search::ParsedQuery.parse`, and `Search::Queries.coerce`. This overrides the class method in Search::Query
      def self.enumerable_terms(current_user:)
        [:severity, :ecosystem, :"package-name", :relationship, :resolution]
      end

      IS_VALUES = {
        state: %w[open closed],
      }

      SORT_MAPPINGS = {
        "created" => "created_at",
        "updated" => "updated_at",
        "severity" => "severity",
        "vulnerable-manifest-path" => "vulnerable_manifest_path",
        "affects" => "affects",
        "last-state-change-at" => "last_state_change_at",
        "repo-id" => "repo_id",
        "epss-percentage" => "epss_percentage",
      }.freeze

      ASCENDING_ONLY_FIELDS = %w[
        vulnerable_manifest_path
        affects
        repo_id
      ].freeze

      def self.max_offset_default
        10_000
      end

      attr_reader :scope

      def initialize(opts = {}, &block)
        @scope = opts.fetch(:scope, nil)
        before = opts.fetch(:before, nil)
        if before.present?
          opts = opts.merge({ last: default_page_size })
        end
        super(opts, &block)

        @index = opts.fetch(:index, ::Elastomer::Indexes::DependabotAlerts.searcher)
      end

      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:state]
      end

      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "description"; @query_fields << "description"
          when "title"; @query_fields << "title"
          end
        end

        @query_fields = %w[description title] if @query_fields.empty?

        @query_fields
      end

      def query_doc
        return if escaped_query.empty?

        doc = {
          query_string: {
            query: escaped_query,
            fields: query_fields,
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          },
        }
      end

      # Wrap the superclass build_query generated query with our custom importance scoring formula
      def build_query
        qd = super

        # When making changes to the importance score algorithm, rather than assuming new scores are correct, I recommend
        # hand-validating the scoring results using the ES Explain API: https://www.elastic.co/search-labs/blog/elasticsearch-scoring-and-explain-api
        importance_score_qd = { function_score: {
            query: qd,
            functions: [
              { field_value_factor: { field: "epss_percentage", factor: 0.25 * 100, missing: 0 } }, # Multiply by 100 since it starts as a percentage
              { field_value_factor: { field: "severity_score", factor: 0.25, missing: 0 } },
            ],
            score_mode: "sum",
          },
        }
      end

      def build_sort
        # If CursorPagination has set up @sort, use its build_sort implementation
        if defined?(@sort) && @sort.present?
          return super
        end

        return if sort.blank?

        ary = build_sort_section(sort, "_score", SORT_MAPPINGS)
        ary = handle_unidirectional_sorts(ary)
        ary
      end

      def filter_hash
        @filter_hash ||= begin
          filters = {
            updated_at: builder.date_range_filter(:updated_at, :updated),
            created_at: builder.date_range_filter(:created_at, :created),
            state: builder.term_filter(:state),
            scope: builder.term_filter(:scope),
            repo_id: builder.repository_filter(current_user, repo_id_from_scope, field: :repository_id),
            severity: builder.enumerated_term_filter(:severity),
            ecosystem: builder.enumerated_term_filter(:ecosystem),
            package_name: builder.enumerated_term_filter(:package_name, :"package-name"),
            relationship: builder.enumerated_term_filter(:relationship),
            resolution: builder.enumerated_term_filter(:resolution),
            epss_percentage: builder.range_filter(:epss_percentage, :"epss-percentage"),
          }

          filters
        end
      end

      def parsed_query
        @parsed_query ||= self.class.parse(user_query)
      end

      def qualifiers=(value)
        super(value)

        @filter_hash = nil

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "open"
              qualifiers[:state].clear.must("open")
            when "closed"
              qualifiers[:state].clear.must("closed")
            end
          end
          qualifiers[:is].clear
        end

        if qualifiers.key?(:"has") && qualifiers[:"has"].must?
          qualifiers[:"has"].must.each do |value|
            qualifiers[:"has_#{value}"].clear.must(true)
          end
          qualifiers[:"has"].clear
        end

        case scope
        when Organization
          qualifiers[:org].must(scope.display_login)
        end
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      def prune_results(results)
        repository_vulnerability_alert_ids = results.map { |h| h["_id"].to_i }

        repository_vulnerability_alerts = Instrumentation.track_time("search.dist.time", tags: ["index:#{index.name}", "action:prune_results_rvas_lookup"]) do
          RepositoryVulnerabilityAlert.
            includes(*repository_vulnerability_alert_includes).
            where(id: repository_vulnerability_alert_ids).
            index_by(&:id)
        end

        results.delete_if do |h|
          doc_id = h["_id"].to_i
          prune_repository_vulnerability_alert(h, repository_vulnerability_alerts[doc_id])
        end
      end

      def prune_repository_vulnerability_alert(doc, repository_vulnerability_alert)
        if repository_vulnerability_alert.nil?
          unless Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("repository_vulnerability_alert", doc["_id"], doc["_routing"])
          end

          return true
        end

        doc["_model"] = repository_vulnerability_alert
        false
      end

      private

      # Private: The set of associations to preload when loading RepositoryVulnerabilityAlert records
      def repository_vulnerability_alert_includes
        [
          { repository: :owner },
          :vulnerability,
          :vulnerable_version_range,
          { repository_dependency_updates: { pull_request: { repository: :owner } } }
        ]
      end

      def repo_id_from_scope
        scope.id if scope.is_a?(Repository)
      end

      def handle_unidirectional_sorts(sort_array)
        Array(sort_array).map do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          direction = item[key]

          if ASCENDING_ONLY_FIELDS.include?(key)
            { key => {
              "order" => "asc",
              "unmapped_type" => "keyword"
            } }
          # define a default sort for epss
          elsif key == "epss_percentage"
            { key => {
              "order" => direction,
              "missing" => direction == "desc" ? "_first" : "_last",
              "unmapped_type" => "float"
            } }
          else
            item
          end
        end
      end

      def aggregations_size
        15
      end
    end
  end
end
