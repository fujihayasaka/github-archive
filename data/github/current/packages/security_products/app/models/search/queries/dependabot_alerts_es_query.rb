# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class DependabotAlertsEsQuery < ::Search::Query
      include CursorPagination

      DEFAULT_PAGE_SIZE = 25
      MAX_PAGE_SIZE = 100

      # The full set of search filters that can be included in a search query.
      SEARCH_FILTER_FIELDS = T.let([
        *SecurityCenter::DependabotAlertsQuery::QUALIFIERS,
        *SecurityCenter::DependabotAlertsQuery::API_QUALIFIERS,
        # TODO: Push SecurityCenter::DependabotAlertsQuery::QUALIFIER_STATE into API_QUALIFIERS
        # and remove from this list after migration of dependabot alerts searching from elasticsearch
        # is complete.
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_STATE,
        SEARCH_IN_FIELD,
      ].uniq.freeze, T::Array[T.any(Symbol, Regexp)])

      # The set of filters where the filter key can only be specified once per query.
      UNIQUE_SEARCH_FILTER_FIELDS = T.let((SEARCH_FILTER_FIELDS - SecurityCenter::DependabotAlertsQuery::ALLOWED_DUPLICATE_QUALIFIERS).freeze, T::Array[T.any(Symbol, Regexp)])

      IS_VALUES = {
        state: %w[open closed],
      }.freeze

      # Fields that have a custom default sort direction when not specified by the user.
      # These may differ from the default descending sort direction or may be called
      # out explicitly to be clear about intent.
      CUSTOM_DEFAULT_SORT_DIRECTIONS = {
        # Sorts that default to ascending rather than the default descending
        "oldest" => "asc",
        "manifest_path" => "asc",
        "package_name" => "asc",
        "repository_id" => "asc",
        "repo_id" => "asc",

        # Include these even though these map to the default sort direction
        # to be explicit about intent since these aren't fields that exist
        # in the index and are mapped in SORT_MAPPINGS
        "newest" => "desc",
        "most_important" => "desc",
      }.freeze

      SORT_MAPPINGS = {
        # some user sort values map to a different field name in the search index
        "newest" => "created_at",
        "oldest" => "created_at", # mapping to the "asc" direction is handled via CUSTOM_DEFAULT_SORT_DIRECTIONS
        "created" => "created_at",
        "updated" => "updated_at",
        "severity" => "severity_score",
        "manifest_path" => "manifest_path.keyword", # use the keyword subfield because sorting is not supported on text fields
        "repo_id" => "repository_id",
        "most_important" => "_score",

        # and some field names need to be specified so that build_sort_section
        # doesn't filter them out :/
        "last_state_change_at" => "last_state_change_at",
        "repository_id" => "repository_id",
        "epss_percentage" => "epss_percentage",
        "package_name" => "package_name",
      }.freeze

      MAP_TO_UNDERSCORE_FIELDS = [
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_SEVERITY,
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_RESOLUTION,
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_RELATIONSHIP,
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_SCOPE,
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_HAS,
        SecurityCenter::DependabotAlertsQuery::QUALIFIER_STATE,
      ].freeze

      ECOSYSTEM_MAPPING = T.let(::AdvisoryDB::Ecosystems.database_enum.index_by { |e| e.to_s.downcase }.freeze, T::Hash[String, String])

      # The set of fields that will be transformed into filters when performing an alerts query:
      # https://www.elastic.co/docs/explore-analyze/query-filter/languages/querydsl#query-filter-context
      sig { override.returns(T::Array[Symbol]) }
      def self.field_list
        # TODO: Fix the parent class's signature to accept Regexp as well as Symbol. That is a bigger change, so for
        # now using T.unsafe and then enforcing the actual T::Array[T.any(Symbol, Regexp)]) on the SEARCH_FILTER_FIELDS constant.
        T.unsafe(SEARCH_FILTER_FIELDS)
      end

      # A set of terms that have mutually exclusive values.
      sig { override.returns(T::Array[Symbol]) }
      def self.unique_field_list
        # TODO: Fix the parent class's signature to accept Regexp as well as Symbol. That is a bigger change, so for
        # now using T.unsafe and then enforcing the actual T::Array[T.any(Symbol, Regexp)]) on the UNIQUE_SEARCH_FILTER_FIELDS constant.
        T.unsafe(UNIQUE_SEARCH_FILTER_FIELDS)
      end

      # Enable memex-style 'or' search for certain Dependabot alert fields. This value gets passed to `Search::ParsedQuery.new`,
      # `Search::ParsedQuery.parse`, and `Search::Queries.coerce`. This overrides the class method in Search::Query
      sig { override.params(current_user: User).returns(T::Array[T.any(Symbol, Regexp)]) }
      def self.enumerable_terms(current_user:)
        SEARCH_FILTER_FIELDS
      end

      sig { override.returns(Integer) }
      def self.max_offset_default
        10_000
      end

      # Scope can be a Repository, Organization, or Business
      # Sorbet has limitations with flow-sensitive typing on method calls, so that's why it's untyped.
      # sig { returns(T.any(Repository, Organization, Business)) }
      sig { returns(T.untyped) }
      attr_reader :scope

      sig { returns(T.nilable(ConditionalAccess::Filter)) }
      attr_reader :cap_filter

      sig { params(opts: T::Hash[T.untyped, T.untyped], block: T.nilable(T.proc.params(query: Search::Query).void)).void }
      def initialize(opts = {}, &block)
        @scope = opts.fetch(:scope)
        @cap_filter = opts.fetch(:cap_filter, nil)

        before = opts.fetch(:before, nil)
        if before.present?
          # normalize opts to use :last if any of the page size options are set
          opts[:last] ||= opts.delete(:per_page) || opts.delete(:first) || default_page_size
        end
        super(opts, &block)

        @index = opts.fetch(:index, ::Elastomer::Indexes::DependabotAlerts.searcher)
      end

      sig { override.returns(T::Array[T.any(Symbol, Regexp)]) }
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      sig { override.returns(T::Array[Symbol]) }
      def aggregation_fields
        [:state]
      end

      sig { override.returns(Integer) }
      def max_page_size
        MAX_PAGE_SIZE
      end

      sig { override.returns(Integer) }
      def default_page_size
        DEFAULT_PAGE_SIZE
      end

      sig { returns(T::Array[String]) }
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "summary"; @query_fields << "summary"
          when "description"; @query_fields << "description"
          # Filtering on "manifest:path/to/manifest" only supports exact matches...
          # Partial matches such as prefix, suffix, fuzzy etc are all handled through search: "in:manifest_path some_term"
          when "manifest_path"; @query_fields << "manifest_path"
          end
        end

        @query_fields = %w[summary description manifest_path] if @query_fields.empty?

        @query_fields
      end

      # Generate a query routing string from the repository IDs:
      # https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/mapping-routing-field
      sig { returns(T.nilable(String)) }
      def routing
        return scope.id.to_s if scope.is_a?(Repository)

        # At the business scope we don't filter by repo ids, and so we don't know which repos are involved in the query
        return nil unless scope.is_a?(Organization)

        routing_repo_ids = filter_hash[:repo_ids_from_filters]&.bool_collection&.must
        # This happens when there are no repo_id filters applied, e.g., searching across all repos in the org.
        # The DB query to enumerate all repositories within the organization is likely more expensive than skipping the routing hint altogether.
        return nil if routing_repo_ids.blank?
        repo_ids_excluded_by_filters = filter_hash[:repo_ids_from_filters]&.bool_collection&.must_not || []
        routing_repo_ids -= repo_ids_excluded_by_filters

        # Is the list of repos short enough to improve routing efficiency?
        # With 32 shards, queries against 100 repos will hit 85% of the shards 97% of the time.
        routing_repo_ids&.length <= 100 ? routing_repo_ids.to_a.join(",") : nil
      end

      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_params
        routing.present? ? { routing: routing } : {}
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
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
      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def build_query
        qd = super

        # Validating changes to the importance score algorithm can be difficult because ES results for _score are not stable.
        # Use the ES Explain API to validate the score is calculating as expected: https://www.elastic.co/search-labs/blog/elasticsearch-scoring-and-explain-api
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

      # resolve_sort! contains all the sorting logic. It's called from the CursorPagination mixin.
      # Although subclasses of ::Search::Query are supposed to implement a #build_sort, instead we rely on CursorPagination#build_sort
      #
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

        # Normalize sort values
        # 1. Enforce all sort values in underscore formatting
        # 2. Assign a custom default sort direction if defined and a direction is not provided
        normalize_qualifier(:sort) do |value|
          matches = PARSE_SORT_REGEXP.match(value.downcase)
          next nil unless matches

          field, direction = matches.captures
          field = field.underscore # map all field names to underscore format

          next "#{field}-#{direction}" if direction.present?
          next "#{field}-#{CUSTOM_DEFAULT_SORT_DIRECTIONS[field]}" if CUSTOM_DEFAULT_SORT_DIRECTIONS.key?(field)

          field
        end

        sort_method_output = sort
        if sort_method_output.present?
          # Use build_sort_section to map Array tuple input (["updated", "desc"]) to mapped output Hash ({ "pushed_at" => "desc" })
          built_sort = build_sort_section(sort_method_output, SORT_MAPPINGS)
          sort_output.concat(built_sort) if built_sort.present?
        end

        if epss_sort = sort_output.find { |s| s.is_a?(Hash) && s.key?("epss_percentage") }
          # When sorting by epss_percentage, fields missing an epss percentage should always be last
          direction = epss_sort["epss_percentage"]
          epss_sort["epss_percentage"] = {
            "order" => direction,
            "missing" => "_last",
          }
        end

        # Global secondary sorts. These should be applied last.
        if sort_output.none? { |s| s.is_a?(Hash) && s.key?("_score") }
          # All searches should include sorting by the relevance score. We tune this
          # with custom signals and market it to customers as our custom "importance score".
          sort_output.push({ "_score" => "desc" })
        end

        if sort_output.none? { |s| s.is_a?(Hash) && s.key?("id") }
          # `id` is a tiebreaker sort value that's guaranteed to be unique for each item
          # so should always be present in a search's sort ordering to ensure stable results.
          #
          # Tiebreakers are recommended when not querying with Point In Time
          # (PIT) queries add an implicit tie-breaker, but they can generate stale
          # results, so we've opted not to use them.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/paginate-search-results.html#search-after
          sort_output.push({ "id" => "desc" })
        end

        sort_output.compact.flatten
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def filter_hash
        @filter_hash ||= begin
          filters = {
            updated_at: builder.date_range_filter(:updated_at, :updated),
            created_at: builder.date_range_filter(:created_at, :created),
            state: builder.term_filter(:state),
            scope: builder.term_filter(:dependency_scope, :scope),
            repo_ids_from_filters: builder.term_filter(:repository_id),
            owner_ids_from_filters: builder.term_filter(:owner_id),
            severity: builder.term_filter(:severity),
            ecosystem: builder.term_filter(:ecosystem),
            package_name: builder.term_filter(:package_name, :package),
            relationship: builder.term_filter(:relationship),
            resolution: builder.term_filter(:resolution),
            epss_percentage: builder.range_filter(:epss_percentage),
            manifest: builder.term_filter(:"manifest_path.keyword", :manifest),
            has_patch: builder.term_filter(:has_patch),
          }

          filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

          filters
        end
      end

      sig { returns(Search::Filters::DependabotAlertsAclFilter) }
      def access_filter
        @access_filter ||= Search::Filters::DependabotAlertsAclFilter.new(scope:, current_user:, cap_filter:)
      end

      sig { returns(T::Array[T.any(String, [Symbol, T.any(String, T::Array[String]), T.nilable(T::Boolean)])]) }
      def parsed_query
        @parsed_query ||= self.class.parse(user_query)
      end

      sig { override.params(value: T.untyped).void }
      def qualifiers=(value)
        super(value)

        @filter_hash = nil

        # Normalize all keys to underscore format.
        qualifiers.keys.each do |key|
          # Do not modify custom property names
          next if SecurityCenter::DependabotAlertsQuery::QUALIFIER_CUSTOM_PROPERTY.match?(key.to_s)
          next unless key.to_s.underscore != key.to_s

          qualifiers[key.to_s.underscore.to_sym] = qualifiers.delete(key)
        end

        # The default parsing of enumerable terms translates e.g. `severity:high,low`
        # into an "and_should" value like ["high", "low"].  The array value is correct,
        # but we need the value to be a "must" instead of an "and_should" to get the
        # correct behavior of a must: { terms: { severity: ["high", "low"] } } ES filter.
        self.class.enumerable_terms(current_user:).each do |enumerable_term|
          # Skip normalizing enumerated qualifiers for custom properties since they are passed
          # directly into a RepoQuery and should retain their original structure.
          next if enumerable_term == SecurityCenter::DependabotAlertsQuery::QUALIFIER_CUSTOM_PROPERTY
          next unless qualifiers.key?(enumerable_term) && qualifiers[enumerable_term].and_should?

          qualifiers[enumerable_term].and_should.each do |value|
            qualifiers[enumerable_term].must(value)
          end
          qualifiers[enumerable_term].and_should.clear
        end

        # some fields store enumerated values that are stored with underscores but exposed in the UI with dashes
        MAP_TO_UNDERSCORE_FIELDS.each do |field|
          normalize_qualifier(field) { |v| v.underscore }
        end

        # Map any casing of a valid ecosystem name to the correct casing we store
        # in the search index, e.g. both "NPM" and "Npm" become "npm"
        normalize_qualifier(:ecosystem) { |v| ECOSYSTEM_MAPPING[v.downcase] }

        # Map any casing of a valid severity value to the correct casing we store
        # in the search index, and map "medium" to "moderate"
        normalize_qualifier(:severity) { |v| SecurityCenter::DependabotAlertsQuery::SEVERITY_MAPPING[v.downcase] }

        # specifying is:open or is:closed overrides any state: qualifiers
        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "open"
              qualifiers[:state].clear.must("open")
            when "closed"
              # This is clearing any existing state: qualifiers and replacing them with
              # a must_not("open") qualifier, which effectively means "any state other than open".
              qualifiers[:state].clear.must_not("open")
            end
          end
          qualifiers[:is].clear
        end

        # state:closed is a shortcut for any state other than "open"
        if qualifiers.key?(:state) && qualifiers[:state].must?
          if qualifiers[:state].must.include?("closed")
            # Don't use must_not("open") here because it would conflict in a query like
            # "state:closed,open" which should return all alerts. That's a little nonsensical,
            # but we should still handle it gracefully.
            qualifiers[:state].must(RepositoryVulnerabilityAlert.states.keys - ["open"])
            qualifiers[:state].must.delete("closed")
          end
        end

        if qualifiers.key?(:has)
          if qualifiers[:has].must?
            qualifiers[:has].must.each do |value|
              qualifiers[:"has_#{value}"].clear.must(true)
            end
          end

          if qualifiers[:has].must_not?
            qualifiers[:has].must_not.each do |value|
              qualifiers[:"has_#{value}"].clear.must_not(true)
            end
          end
          qualifiers[:has].clear
        end

        # Map filters that limit or exclude repositories and repository owners
        # into qualifiers that can be used to build term filters on those
        # fields.
        qualifiers[:repository_id] = repo_ids_from_filters_qualifier
        qualifiers[:owner_id] = owner_ids_from_filters_qualifier
      end

      # Run a block against all qualifier values for a given field if the field is present in the qualifiers hash.
      sig { params(field: Symbol, block: T.proc.params(arg0: T.untyped).returns(T.untyped)).void }
      def normalize_qualifier(field, &block)
        return unless qualifiers.key?(field)
        qualifiers[field].map_all!(&block)
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      sig { override.params(results: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # This not only prunes the results, it also hydrates with the actual alerts data from MySQL (surprise!)
      # The naming of this method is non-intuitive, but kept this way for consistency with other query classes across GitHub.
      sig { override.params(results: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
      def prune_results(results)
        repository_vulnerability_alert_ids = results.map { |h| h["_id"].to_i }

        repository_vulnerability_alerts = Instrumentation.track_time("search.dist.time", tags: ["index:#{index.name}", "action:prune_results_rvas_lookup"]) do
          RepositoryVulnerabilityAlert.
            # Join on associations that include normalized alert data.
            # These DB rows must exist for an alert to be renderable.
            joins(:vulnerable_version_range, :vulnerability).
            where(id: repository_vulnerability_alert_ids).
            annotate("cross-schema-domain-query-exempted").
            index_by(&:id)
        end

        # Preload information that will always be needed on an alert to avoid N+1's
        GitHub::PrefillAssociations.prefill_associations(repository_vulnerability_alerts.values, [
          { repository: :owner }, # repo and repo owner are used to build alert permalinks
          :vulnerable_version_range,
          :vulnerability,
        ])

        results.delete_if do |h|
          doc_id = h["_id"].to_i
          prune_repository_vulnerability_alert(h, repository_vulnerability_alerts[doc_id])
        end
      end

      # Returns true if an alert was not loaded from the DB, either because they no longer exist
      # or one of the joined associations is missing (e.g. the vulnerability was deleted). If so,
      # a job is also queued to remove the alert from the search index.
      # For future readers - this minimal check only ensures that an alert can be rendered
      # in the UI or serialized for the API, but not whether it should. Updating Elasticsearch when
      # alerts become unsearchable (e.g. due to disabling vulnerability alerts) is handled asynchronously.
      # This can lead to small windows of time where alerts can be unexpectedly returned from searches
      # even though the alert should not be searchable.  We choose eventual consistency to avoid a costly
      # check in the query hot path.
      sig { params(doc: T::Hash[String, T.untyped], repository_vulnerability_alert: T.nilable(RepositoryVulnerabilityAlert)).returns(T::Boolean) }
      def prune_repository_vulnerability_alert(doc, repository_vulnerability_alert)
        if repository_vulnerability_alert.nil?
          unless Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("dependabot_alert", doc["_id"], doc["_routing"])
          end

          return true
        end

        doc["_model"] = repository_vulnerability_alert
        false
      end

      private

      sig { returns(ParsedQuery::BoolCollection) }
      def owner_ids_from_filters_qualifier
        bool_collection = ParsedQuery::BoolCollection.new

        must_not_match_owner_ids = negative_owner_ids_from_filters
        bool_collection.must_not(must_not_match_owner_ids) unless must_not_match_owner_ids.nil?

        # if we don't need to filter on specific owner ids, we can skip adding more constraints
        must_match_owner_ids = owner_ids_from_filters
        return bool_collection if must_match_owner_ids.nil?

        if must_match_owner_ids.empty?
          # force an empty result set if there are no matching owner ids to the provided user filters
          bool_collection.must(::Search::Filter::MISSING)
        else
          bool_collection.must(must_match_owner_ids)
        end

        bool_collection
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def owner_ids_from_filters
        [
          owner_ids_for_org_names(qualifiers[:org]&.must), # e.g. "org:example_org"
          owner_ids_for_acl,
        ].compact.reduce(:&) # since these are `must` qualifiers we use set intersection
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def negative_owner_ids_from_filters
        [
          # currently artifact registries or registry urls are only tied to repos, not orgs/owners
          owner_ids_for_org_names(qualifiers[:org]&.must_not),
        ].compact.reduce(:|) # since these are `must_not` qualifiers we use set union
      end

      sig { params(org_names: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def owner_ids_for_org_names(org_names = nil)
        return nil unless org_names.present?
        return nil unless scope.is_a?(Business)

        # This also limits the returned owner_ids to only the orgs that the user can access.
        scoped_organizations.where(login: org_names).pluck(:id)
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def owner_ids_for_acl
        # access_filter sometimes returns values for the `repository_id` field, so we can only restrict when it's explicitly Org IDs.
        access_filter.field == Search::Filters::DependabotAlertsAclFilter::ORG_FIELD ? access_filter.values : nil
      end

      sig { returns(ParsedQuery::BoolCollection) }
      def repo_ids_from_filters_qualifier
        bool_collection = ParsedQuery::BoolCollection.new

        must_not_match_repo_ids = negative_repo_ids_from_filters
        bool_collection.must_not(must_not_match_repo_ids) unless must_not_match_repo_ids.nil?

        # if we don't need to filter on specific repo ids, we can skip adding more constraints
        must_match_repo_ids = repo_ids_from_filters
        return bool_collection if must_match_repo_ids.nil?

        if must_match_repo_ids.empty?
          # force an empty result set if there are no matching repo ids to the provided user filters
          bool_collection.must(::Search::Filter::MISSING)
        else
          bool_collection.must(must_match_repo_ids)
        end

        bool_collection
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def repo_ids_from_filters
        [
          repo_ids_for_team_slugs(qualifiers[:team]&.must),
          repo_ids_for_artifact_registries(qualifiers[SecurityCenter::DependabotAlertsQuery::QUALIFIER_ARTIFACT_REGISTRY]&.must),
          repo_ids_for_artifact_registry_urls(qualifiers[SecurityCenter::DependabotAlertsQuery::QUALIFIER_ARTIFACT_REGISTRY_URL]&.must),
          repo_ids_for_custom_properties,
          repo_ids_for_repo_names(qualifiers[:repo]&.must),
          repo_ids_for_repo_topics(qualifiers[:topic]&.must),
          repo_ids_for_runtime_risks(qualifiers[:runtime_risk]&.must),
          repo_ids_with_deployments(qualifiers[:has_deployment]&.must&.any?),
          repo_ids_for_acl,
        ].compact.reduce(:&) # since these are `must` qualifiers we use set intersection
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def negative_repo_ids_from_filters
        [
          repo_ids_for_team_slugs(qualifiers[:team]&.must_not),
          repo_ids_for_artifact_registries(qualifiers[SecurityCenter::DependabotAlertsQuery::QUALIFIER_ARTIFACT_REGISTRY]&.must_not),
          repo_ids_for_artifact_registry_urls(qualifiers[SecurityCenter::DependabotAlertsQuery::QUALIFIER_ARTIFACT_REGISTRY_URL]&.must_not),
          repo_ids_for_repo_names(qualifiers[:repo]&.must_not),
          repo_ids_for_repo_topics(qualifiers[:topic]&.must_not),
          repo_ids_for_runtime_risks(qualifiers[:runtime_risk]&.must_not),
          repo_ids_with_deployments(qualifiers[:has_deployment]&.must_not&.any?),
        ].compact.reduce(:|) # since these are `must_not` qualifiers we use set union
      end

      sig { params(team_slugs: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_team_slugs(team_slugs = nil)
        return nil unless team_slugs.present?
        return nil unless scope.is_a?(Organization) || scope.is_a?(Business)

        teams = []
        if scope.is_a?(Business)
          # At the enterprise level, per-org teams are queried as <org>/<team>
          org_prefixed_team_slugs, team_slugs_without_org = team_slugs.partition { |slug| slug.include?("/") }

          teams_by_org = {}
          org_prefixed_team_slugs.each do |slug|
            org_name, team_slug = slug.split("/", 2)
            teams_by_org[org_name&.downcase] ||= []
            teams_by_org[org_name&.downcase] << team_slug
          end

          teams = scoped_organizations.flat_map do |organization|
            team_list = team_slugs_without_org + (teams_by_org[organization.display_login&.downcase] || [])
            organization.visible_teams_for(current_user).where(slug: team_list)
          end
        else
          teams = scope.visible_teams_for(current_user).where(slug: team_slugs)
        end

        # Alerts are only visible in repos where the team has write or admin access, read access is not enough
        required_permissions = [:admin, :write]

        teams.flat_map { |team| team.direct_or_inherited_repo_ids(action: required_permissions) }.uniq
      end

      sig { params(artifact_registries: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_artifact_registries(artifact_registries = nil)
        return nil unless scope.is_a?(Organization)
        return nil unless artifact_registries

        ArtifactStorageRecord.repository_ids_for_owner_and_artifact_registries(owner_id: scope.id, artifact_registries:)
      end

      sig { params(registry_urls: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_artifact_registry_urls(registry_urls = nil)
        return nil unless scope.is_a?(Organization)
        return nil unless registry_urls

        ArtifactStorageRecord.repository_ids_for_owner_and_registries(owner_id: scope.id, registry_urls:)
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_custom_properties
        return nil unless scope.is_a?(Organization)

        custom_qualifiers = custom_property_qualifiers
        return nil if custom_qualifiers.blank?

        # set an org qualifier for the repo query
        custom_qualifiers[:org].must(scope.display_login)

        Search::Queries::RepoQuery.new(
          binary_fork_filter: true,
          include_forks: true,
          normalizer: lambda { |hits| hits.map { |hit| hit.fetch("_source").fetch("repo_id") } },
          page: 1,
          per_page: 10_000,
          qualifiers: custom_qualifiers,
          sort: %w(updated desc),
          source_fields: ["repo_id"],
          skip_permission_check: true,
        ).execute(skip_prune_results: true).results
      end

      # Returns a hash of custom property qualifiers extracted from the full set of qualifiers.
      # Accessing fields in this hash will create new BoolCollection objects as needed similar to
      # accessing the qualifiers hash
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def custom_property_qualifiers
        # `keep_if` mutates in-place so is used instead of the non-mutating `select` to preserve this default hash initializer:
        # https://github.com/github/github/blob/3188a52588a89c72180b64a7f9fa086859cc22dc/packages/search/app/models/search/parsed_query.rb#L282
        qualifiers.dup.keep_if { |key, _| SecurityCenter::DependabotAlertsQuery::QUALIFIER_CUSTOM_PROPERTY.match?(key.to_s) }
      end

      sig { params(repository_names: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_repo_names(repository_names = nil)
        return nil unless repository_names

        case scope
        when Business
          Repository.with_names_with_owners(repository_names).where(owner_id: scoped_organizations.pluck(:id)).pluck(:id)
        when Organization
          Repository.where(owner_id: scope.id, name: repository_names).pluck(:id)
        else
          nil
        end
      end

      sig { params(topic_names: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_repo_topics(topic_names = nil)
        return nil unless topic_names.present?
        return nil unless scope.is_a?(Organization) || scope.is_a?(Business)

        topic_ids = Topic.where(name: topic_names).pluck(:id)
        topics_scope = RepositoryTopic.applied.joins(:repository).where(topic_id: topic_ids)

        case scope
        when Organization
          topics_scope = topics_scope.where(repositories: { owner_id: scope.id })
        when Business
          topics_scope = topics_scope.where(repositories: { owner_id: scoped_organizations.pluck(:id) })
        end

        topics_scope.distinct.pluck(:repository_id)
      end

      sig { params(runtime_risks: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_runtime_risks(runtime_risks = nil)
        return nil unless runtime_risks.present?
        return nil unless scope.is_a?(Organization)

        ArtifactDeploymentRecord.repository_ids_for_owner_and_runtime_risks(owner_id: scope.id, runtime_risks: runtime_risks)
      end

      sig { params(find_repos_with_deployments: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
      def repo_ids_with_deployments(find_repos_with_deployments = false)
        return nil unless find_repos_with_deployments
        return nil unless scope.is_a?(Organization)

        ArtifactDeploymentRecord.repository_ids_for_owner(scope.id)
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def repo_ids_for_acl
        # access_filter sometimes returns values for the `owner_id` (org ID) field, so we can only restrict when it's explicitly repo IDs.
        access_filter.field == Search::Filters::DependabotAlertsAclFilter::REPO_FIELD ? access_filter.values : nil
      end

      sig { returns(ActiveRecord::Relation) }
      def scoped_organizations
        return Organization.none unless scope.is_a?(Business)
        return Organization.none unless access_filter.field == Search::Filters::DependabotAlertsAclFilter::ORG_FIELD &&
                                        access_filter.values.present?
        scope.organizations.where(id: access_filter.values)
      end

      sig { override.returns(Integer) }
      def aggregations_size
        15
      end
    end
  end
end
