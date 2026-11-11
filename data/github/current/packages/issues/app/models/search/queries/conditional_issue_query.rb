# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueQuery < ::Search::Queries::IssueQuery
      include GitHub::Memoizer

      def self.field_list
        super + [:"milestone-number", :"blocked-by", :blocking, :blocked, :field, :"min-score", :"lexical-boost", :"semantic-boost", :"knn-k", :"knn-candidates", :"rank-window-size", :"similarity-threshold"]
      end

      # These are fields that support the "no:<field>" and the "has:<field>" syntax. This is passed to the parser so it knows to look for
      # this syntax and set the appropriate values in the BoolCollection for that field.
      #
      # See IssueQuery#qualifiers= for where this list of fields comes from
      PRESENCE_VALUE_FIELDS = {
        label: :label,
        labels: :label,
        milestone: :milestone,
        milestones: :milestone,
        "milestone-number": :"milestone-number",
        project: :project,
        assignee: :assignee,
        type: :issue_type,
        "review-requested": :"review-requested",
        "reviewed-by": :"reviewed-by",
        "parent-issue": :"parent-issue",
        "sub-issue": :"sub-issue",
        "blocking": :blocking,
        "blocked-by": :"blocked-by",
        "blocked": :"blocked-by",
        "field": :field,
      }

      QUERY_DEPTH_LIMIT = 5
      QUERY_DEPTH_ERROR_MESSAGE = "Query clause limit exceeded"

      OWNERSHIP_FILTERS_LIMIT = 16
      OWNERSHIP_FILTERS_ERROR_MESSAGE = "Ownership filters limit of #{OWNERSHIP_FILTERS_LIMIT} exceeded"

      OR_BOOL_TYPE = :or
      AND_BOOL_TYPE = :and

      # The qualifier "is:<field>" is a special case where we need to map the value to the correct field and value
      # before setting it in the BoolCollection. This is a map of the fields and values we need to map to.
      #
      # ParsletQuery#process_attribute also contains a special condition for a feature flagged case.
      # See IssueQuery#qualifiers= for where this list of fields comes from
      IS_QUALIFIER_MAP = {
        issue: { field: :type, value: "issue" },
        pr: { field: :type, value: "pull-request" },
        "pull-request": { field: :type, value: "pull-request" },
        open: { field: :state, value: "open" },
        closed: { field: :state, value: "closed" },
        locked: { field: :locked, value: true },
        unlocked: { field: :locked, value: false },
        merged: { field: :merged_state, value: true },
        unmerged: { field: :merged_state, value: false },
        queued: { field: :queued, value: true },
        public: { field: :public, value: true },
        private: { field: :public, value: false },
        blocked: { field: :open_blocked_by_count, value: ">0" },
        blocking: { field: :open_blocking_count, value: ">0" },
      }

      # These are qualifiers that are interpreted by the parser to be at the top level no matter which level
      # we find them in. They're also removed from the list of qualifiers before we start building the query.
      TOP_LEVEL_TERMS = [:sort, :"min-score", :"lexical-boost", :"semantic-boost", :"knn-k", :"knn-candidates", :"rank-window-size", :"similarity-threshold"]

      OWNERSHIP_TERMS = [:repo, :org, :user, :owner]

      # terms that support <field_name>:*
      WILDCARDABLE_TERMS = [:assignee, :milestone, :"milestone-number"]

      AGGREGATION_FIELDS = [:language_id, :state]

      # phrase slop limits how far phrase text terms can be apart from each other, making the overall
      # query more efficient for long documents
      DEFAULT_PHRASE_SLOP_VALUE = 10

      # Fake field ID used for no-match conditions when field doesn't exist or user has no access
      # Field IDs are incrementing integers starting from 1, so this will never exist
      FAKE_FIELD_ID = "field.999999999"

      sig { returns(ParsletQuery::BoolQualifier) }
      attr_accessor :conditional_qualifiers

      sig { returns(T::Array[ParsletQuery::Qualifier]) }
      attr_accessor :top_level_qualifiers

      sig { returns(T::Array[ParsletQuery::Qualifier]) }
      attr_accessor :ownership_qualifiers

      sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
      attr_accessor :aggregation_qualifiers

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_accessor :field_types

      def initialize(opts = {})
        super(opts)
      end

      sig { params(value: String).void }
      def phrase=(value)
        @phrase = value.to_s

        pq = GitHub.dogstats.distribution_time("search.advanced_search.new_parslet_query") do
          ParsletQuery.new(@phrase, qualifier_fields,
            current_user: @current_user,
            presence_value_fields: PRESENCE_VALUE_FIELDS,
            is_qualifier_map: IS_QUALIFIER_MAP,
            enumerable_terms: self.class.enumerable_terms,
            wildcardable_terms: WILDCARDABLE_TERMS,
            top_level_terms: TOP_LEVEL_TERMS,
            ownership_terms: OWNERSHIP_TERMS,
            aggregation_fields: aggregations.present? ? AGGREGATION_FIELDS : []
          )
        end
        @orgs_scoped = if pq.qualifiers[:org].present? && pq.qualifiers[:org].must.present? && pq.qualifiers[:org].must_not.blank?
          pq.qualifiers[:org].must
        else
          nil
        end
        @is_valid = pq.valid_query?
        unless @is_valid
          @invalid_reason = pq.invalid_reason
        end
        self.query = pq.query
        @has_any_ownership_qualifier = pq.has_any_ownership_qualifier
        @has_balanced_ownership_qualifiers = pq.has_balanced_ownership_qualifiers
        GitHub.dogstats.distribution_time("search.advanced_search.set_qualifiers") do
          self.qualifiers = pq.qualifiers
          self.conditional_qualifiers = pq.conditional_qualifiers
          self.top_level_qualifiers = pq.top_level_qualifiers
          self.ownership_qualifiers = pq.ownership_qualifiers
          self.aggregation_qualifiers = pq.aggregation_qualifiers
        end
        @qualifier_count = pq.qualifier_count
        @has_text_terms = pq.has_text_terms?
        @complex = pq.complex?
        @index_type = pq.index_type
        @repo_filter = nil
        @valid_filters = true
        @query_depth = 0
        @field_types = {}
      end

      sig { override.returns(T.nilable(T::Boolean)) }
      private def complex?
        @complex
      end

      # The fields that are enumerable with commas.
      # This overrides the method in IssueQuery.
      # We cannot add onto the method in IssueQuery because it uses different parsing.
      sig { params(current_user: T.anything).returns(T::Array[Symbol]) }
      def self.enumerable_terms(current_user: nil)
        [:type, :label, :"parent-issue", :"sub-issue", :blocking, :"blocked-by", :lang, :language, :field]
      end

      # Enumerable terms that have the same behavior regardless of the filter value used.
      # - the :type filter has to be handled differently if it's used to define an Issue or PR filter
      memoize private def simple_enumerable_terms
        self.class.enumerable_terms - [:type]
      end

      def repository_filter
        build_query if @repo_filter.nil?

        @repo_filter
      end

      def valid_query?
        GitHub.dogstats.distribution_time("search.advanced_search.validate_query", tags: datadog_tags) do
          return false unless @is_valid
          return false if repository_filter.nil?

          unless @valid_filters
            GitHub.dogstats.increment("search.advanced_search.invalid_query", tags: custom_tags(["invalid_reason:invalid_filters"]))
            return false
          end

          if @query_depth >= QUERY_DEPTH_LIMIT
            @invalid_reason = QUERY_DEPTH_ERROR_MESSAGE

            GitHub.dogstats.increment("search.advanced_search.invalid_query",
              tags: custom_tags(["invalid_reason:query_depth", "depth_level:#{@query_depth}"])
            )

            return false
          end

          unless valid_ownership_filters_limit?
            @invalid_reason = OWNERSHIP_FILTERS_ERROR_MESSAGE

            GitHub.dogstats.increment("search.advanced_search.invalid_query",
              tags: custom_tags(["invalid_reason:ownership_filters_limit_exceeded"])
            )

            return false
          end

          unless repository_filter.valid?
            @invalid_reason = repository_filter.invalid_reason
            return false
          end

          true
        end
      end

      sig { returns(T::Boolean) }
      private def valid_ownership_filters_limit?
        limited_ownership_filters_count = ownership_qualifiers.count do |qualifier|
          qualifier.field != :repo && OWNERSHIP_TERMS.include?(qualifier.field)
        end

        limited_ownership_filters_count < OWNERSHIP_FILTERS_LIMIT
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_query
        GitHub.dogstats.distribution_time("search.advanced_search.build_query_filter", tags: datadog_tags) do
          build_query_filter || {}
        end
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_query_filter
        return @query_filter if defined?(@query_filter)
        return unless @is_valid

        filtered_query = map_to_filters(self.conditional_qualifiers)

        if use_candidate_repo_search?
          candidate_private_repo_ids = load_candidate_private_repo_ids(filtered_query)
        else
          candidate_private_repo_ids = nil
        end

        try_add_current_user_ownership_filter

        # Fast path: when pre-resolved repo IDs are provided (e.g., from the
        # lexical component of a hybrid search), skip the expensive
        # RepositoryFilter construction entirely. These IDs have already been
        # through full authz/CAP/ProgrammaticActor filtering.
        if !@pre_resolved_repo_ids.nil?
          @repo_filter = ::Search::Filters::RepositoryFilter.from_authorized_ids(@pre_resolved_repo_ids)
        else
          # The global repository filter builder is still used in advanced search to ensure that the query
          # will only access allowed repo ids, regardless of the ownership filters used in the query.
          @repo_filter = build_repository_filter(candidate_private_repo_ids: candidate_private_repo_ids)
        end

        repo_filter_fragment = try_include_public_repos_to_main_repo_filter(@repo_filter)
        # Combining the global repository filter with a MUST to enforce only accessible repository ids or public items
        @query_filter = {
          bool: {
            must: filtered_query.nil? ? repo_filter_fragment : [repo_filter_fragment, filtered_query]
          }
        }
      end

      # This is a copy of the function from IssueQuery. We need to copy it here so we can pass in our pre-built query
      # instead of a list of filters. This will execute our query with an additional "public: false" argument and
      # return the list of repository IDs that match it. This is done so we can pass this list to the repository
      # filter. The repository filter will narrow down this list based on which ones the current user has access to.
      sig { params(candidate_query: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(T::Array[Integer])) }
      def load_candidate_private_repo_ids(candidate_query)
        return @candidate_private_repo_ids if defined?(@candidate_private_repo_ids)

        @index = index_for_type_param
        query = ConditionalQueryCandidatePrivateRepoQuery.new(candidate_query, index: @index)

        response = query.execute
        repo_id_buckets = response.aggregations.dig("repo_ids", "buckets")
        if repo_id_buckets&.any?
          @candidate_private_repo_ids = repo_id_buckets.map { |h| h["key"] }
        else
          @candidate_private_repo_ids = nil
        end
      end

      # This method adds the current user to the base qualifiers of global search queries.
      # This has to be done if the query has ownership terms present in some conditional groups
      # and not in others. (i.e.: unbalanced ownership qualifiers)
      # E.g.: (repo:monalisa/monorepo AND test in:title) OR (label:bug-report)
      #       \___________________(A)__________________/    \______(B)_______/
      # A -> has :repo ownership term
      # B -> no ownership term (other branch of an OR)
      #
      # Since the main repo_ids fragment is still being generated by RepositoryFilter,
      # the whole query above would be restricted to the ownership term (:repo), found in conditional group A.
      # By adding the current user before generating the main repo_ids fragment,
      # repositories owned by the current user can be matched against conditional group B.
      #
      # Note: once the ConditionalRepositoryFilter is approved by a security review,
      # this method can be refactored to use a more specific filter that generates the same set of ids
      # that are currently generated by RepositoryFilter when no ownership qualifiers are present.
      # Avoiding the need to add public repos or the current user to the non-conditional qualifiers.
      sig  { void }
      def try_add_current_user_ownership_filter
        return if @repo_id
        return if @has_balanced_ownership_qualifiers
        return unless current_user

        current_user_qualifier = ::Search::ParsedQuery::BoolCollection.new(:user)
        current_user_qualifier.must(current_user.display_login)
        if self.qualifiers.key?(:user)
          self.qualifiers[:user].merge!(current_user_qualifier)
        else
          self.qualifiers[:user] = current_user_qualifier
        end
      end

      # When there are ownership terms in a global query, if any of the conditional groups doesn't include
      # an ownership, it's necessary to expand the main repo filter to include public repos, similarly
      # to the fragment generated by RepositoryFilter when no ownership filters are used in a global query.
      sig do
        params(
          repo_filter: ::Search::Filters::RepositoryFilter
        ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def try_include_public_repos_to_main_repo_filter(repo_filter)
        repo_filter_fragment = repo_filter.must

        # if public repos are already included, there's nothing else do be done here
        return repo_filter_fragment if repo_filter.global?
        return nil unless repo_filter_fragment

        return repo_filter_fragment if @repo_id
        return repo_filter_fragment if @has_balanced_ownership_qualifiers
        return repo_filter_fragment unless current_user
        # When limit_to_repo_ids is set, we want strict restriction to those repos only,
        # not allowing public results from outside those repositories.
        return repo_filter_fragment if @limit_to_repo_ids.present?
        # When pre_resolved_repo_ids is set (dedup path), the filter already contains
        # exactly the authorized repos — do not widen with a public-repos OR clause.
        return repo_filter_fragment if !@pre_resolved_repo_ids.nil?

        {
          bool: {
            should: [
              { term: { public: true } },
              repo_filter_fragment,
            ]
          }
        }
      end

      sig { params(qualifier: T.nilable(ParsletQuery::BoolQualifier), query_depth: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def map_to_filters(qualifier, query_depth: 1)
        return unless qualifier

        @query_depth = query_depth if query_depth > @query_depth

        query_qualifiers = qualifier.qualifiers.select { |q| q.is_a?(ParsletQuery::QueryQualifier) }
        filter_qualifiers = T.cast(qualifier.qualifiers.select { |q| q.is_a?(ParsletQuery::Qualifier) }, T::Array[ParsletQuery::Qualifier])
        bool_qualifiers = qualifier.qualifiers.select { |q| q.is_a?(ParsletQuery::BoolQualifier) }

        search_in = T.let([], T::Array[T.untyped])
        filter_qualifiers.select { |q| q.field == SEARCH_IN_FIELD }.each do |q|
          search_in = Array(q.collection.must)
          search_in.map! { |str| str.split(/[,\s]/) }
          search_in.flatten!
          search_in.map! { |str| str.downcase }
        end

        # when working with negative filters (must_not) and the terms are OR'ed together, it's necessary
        # to wrap the resulting document fragment in a :should, since elastic search doesn't have a :should_not.
        # The following array will hold must_not qualifiers to avoid filters of the same type from ending
        # up in the same collection while processing the qualifiers.
        # e.g.:
        #   label:a OR -label:b
        #     -> would generate a single collection under the :label key containing :and_should and :must_not
        #   possibly resulting in:
        #     :must { should: a, must_not: b}
        #   but the desired fragment has to follow the structure for correct results:
        #     -> :should { should/must: a, must_not: b}
        #   and that can be achieved by spliting the collection into two parts of the OR operation
        must_not_filter_qualifiers = []
        if filter_qualifiers.size
          if qualifier.type == OR_BOOL_TYPE
            must_not_filter_qualifiers = filter_qualifiers.select do |q|
              q.collection.must_not.present? ||
              q.collection.must == [::Search::Filter::MISSING] ||
              q.collection.must == [::Search::Filter::EXISTS]
            end
          elsif qualifier.type == AND_BOOL_TYPE
            # The presence filters (has:<x> and no:<x>) have to be treated separately when AND'ed together
            # because term filter will generate a search fragment for either a value or one of the presence filters.
            # With AND we need to be able to generate multiple fragments for the same field even if the resulting query
            # just returns no results.
            must_not_filter_qualifiers = filter_qualifiers.select do |q|
              q.collection.must == [::Search::Filter::MISSING] ||
              q.collection.must == [::Search::Filter::EXISTS]
            end
          end

          filter_qualifiers -= must_not_filter_qualifiers
        end

        valid_terms = []
        valid_terms += query_qualifiers.map { |q| qualifier_to_query(T.cast(q, ParsletQuery::QueryQualifier), search_in) }.compact
        valid_terms += [qualifiers_to_filters(qualifier.type, T.cast(filter_qualifiers, T::Array[ParsletQuery::Qualifier]))].compact
        valid_terms += [qualifiers_to_filters(qualifier.type, T.cast(must_not_filter_qualifiers, T::Array[ParsletQuery::Qualifier]))].compact
        valid_terms += bool_qualifiers.map { |q| map_to_filters(T.cast(q, ParsletQuery::BoolQualifier), query_depth: query_depth + 1) }.compact

        return if valid_terms.length == 0
        return valid_terms[0] if valid_terms.length == 1

        {
          bool: {
            (qualifier.type == OR_BOOL_TYPE ? :should : :must) => valid_terms
          }
        }
      end

      # Override the `build_filter` method which gets called
      # in the `query_document` of the grandparent Query class
      # to generate the `post_filter` term
      def build_filter
        return unless aggregations.present?

        builder = ::Search::FilterBuilder.new(@aggregation_qualifiers)
        filters = {}
        filters[:state] = builder.term_filter(:state)
        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language, :lang)
        filter = Search::Filters::BoolFilter.new(filters)

        filter.build
      end

      # Returns the fields to be checked against text terms.
      sig { params(search_in_fields: T::Array[String]).returns(T::Array[String]) }
      def query_fields_to_search(search_in_fields)
        query_fields = T.let([], T::Array[String])

        search_in_fields.each do |field|
          case field
          when "title";    query_fields += title_field
          when "body";     query_fields << "body"
          when "comments"; query_fields << "comments.body^0.8"
          end
        end

        query_fields = title_field.concat(%w[body comments.body^0.8]) if query_fields.empty?
        query_fields
      end

      # Converts text_terms into its query fragment.
      sig { params(qualifier: ParsletQuery::QueryQualifier, search_in_fields: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifier_to_query(qualifier, search_in_fields)
        escaped_query = escape_query(qualifier.query)

        has_quoted_text_term = escaped_query.include?('"')

        # phrase_slop of zero means that the tokens in a matching document have to appear in the exact order
        # of the terms in an ElasticSearch phrase (characters surrrounded by double quotes) in the query input
        phrase_slop = has_quoted_text_term ? 0 : DEFAULT_PHRASE_SLOP_VALUE

        # "texty" analyzer has to be used for exact queries because some characters can produce a different set of tokens
        # when processed by "texty_search"
        analyzer = has_quoted_text_term ? "texty" : "texty_search"

        query = {
          function_score: {
            query: {
              query_string: {
                query: escaped_query,
                fields: query_fields_to_search(search_in_fields),
                phrase_slop: phrase_slop,
                default_operator: "AND",
                analyzer: analyzer,
              }
            },
            score_mode: "sum",
            functions: [
              {
                exp: {
                  created_at: {
                    scale: "42d",
                    decay: 0.5,
                  }
                }
              },
              {
                exp: {
                  updated_at: {
                    scale: "84d",
                    decay: 0.5,
                  }
                }
              },
              {
                filter: { term: { state: "open" } },
                weight: 2,
              },
            ],
          }
        }

        # when the user query doesn't specify an `in` qualifier we look for potential commit SHAs and issue numbers
        # if we find them then we add clauses to look for those explicitly
        # if escape_wildcards parameter is false we need to strip the query off wildcards
        # before trying to match it with commit SHA or issue number
        query_without_wildcards = @escape_wildcards ? escape_query(qualifier.query) : qualifier.query.gsub(/[\*\?]/, "")

        commit_sha_clauses = search_in_fields.empty? ? commit_sha(query_without_wildcards) : []
        number_clauses = search_in_fields.empty? || @force_issue_number_terms || search_in_fields.include?("number") ? issue_number(query_without_wildcards) : []
        more_clauses = commit_sha_clauses + number_clauses

        if more_clauses.any?
          more_clauses.unshift query
          query = { bool: { should: more_clauses } }
        end

        query
      end

      # Helper method to create a field qualifier hash
      sig { params(field_name: Symbol, collection: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def create_field_qualifier(field_name, collection)
        {
          qualifier: ParsletQuery::Qualifier.new(
            field: field_name,
            collection: collection
          ),
          is_field: true
        }
      end

      # This method takes a list of qualifiers and turns them into the actual filters in the elasticsearch query
      # doc. It's important that we check each filter for each group of qualifiers because some filters check
      # multiple qualifier values. For example the repository filter checks `repo`, `user`, `org`, `is`, and others.
      #
      # The repository filter is also the primary security filter. It checks the current user's access and the qualifiers
      # to make sure the query contains the appropriate filters to make sure the user only sees responses they have
      # access to see. It's important that this is called every time we build a query.
      #
      sig { params(bool_type: Symbol, filter_qualifiers: T::Array[ParsletQuery::Qualifier]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifiers_to_filters(bool_type, filter_qualifiers)
        collections = {}

        # First pass: transform field qualifiers and group those that map to the same transformed field
        transformed_qualifiers = []
        field_qualifiers_by_transformed_name = {}

        filter_qualifiers.each do |qualifier|
          # Remember if this was originally a field qualifier before transformation
          is_field_qualifier = qualifier.field.to_s.start_with?("field.") && issue_fields_enabled?

          # Transform field qualifiers before processing them like normal qualifiers
          if is_field_qualifier
            transformed_collection = transform_field_qualifier(qualifier)
            next unless transformed_collection
            if !is_global_search
              # Track the transformed field name and group qualifiers by it
              transformed_field_name = transformed_collection.name.to_sym
              field_qualifiers_by_transformed_name[transformed_field_name] ||= []
              field_qualifiers_by_transformed_name[transformed_field_name] << transformed_collection
              # Don't add to transformed_qualifiers yet - we'll combine them later
            elsif is_global_search && transformed_collection.should.present?
              # Global search for fields
              # The should collection will have multiple BoolCollection entries, one for each org field that was found
              # e.g. field:123 OR field:456 (where 123 and 456 are field IDs for field.field_name in different organizations)
              collections[:field_global] ||= {}
              collections[:field_global][qualifier.field.to_sym] = transformed_collection
            end
          else
            transformed_qualifiers << { qualifier: qualifier, is_field: false }
          end
        end

        # For field qualifiers in OR context with multiple same transformed fields,
        # combine them into a single qualifier with all values in one and_should array
        # BUT ONLY for text and single_select fields (which use EnumeratedTermFilter)
        # Number and date fields use range filters which need separate processing
        field_qualifiers_by_transformed_name.each do |transformed_field_name, field_collections|
          if bool_type == OR_BOOL_TYPE && field_collections.length > 1
            # Check the field type to determine how to combine multiple values
            # @field_types is populated during transform_field_qualifier calls (in the first pass above)
            # by build_field_bool_collection which sets field_id => field.data_type
            field_type = @field_types[transformed_field_name]
            uses_enumerated_filter = field_type != "number" && field_type != "date"

            if uses_enumerated_filter
              # Combine all values from multiple field qualifiers into one collection
              # This is needed for single_select and text fields which use EnumeratedTermFilter
              combined_collection = ::Search::ParsedQuery::BoolCollection.new(transformed_field_name)
              all_values = field_collections.flat_map { |col| col.must || [] }.compact
              combined_collection.and_should(all_values) unless all_values.empty?

              transformed_qualifiers << create_field_qualifier(transformed_field_name, combined_collection)
            else
              # For number and date fields, add each qualifier separately
              # They will be merged later and use range filter logic
              field_collections.each do |collection|
                transformed_qualifiers << create_field_qualifier(transformed_field_name, collection)
              end
            end
          else
            # Single field qualifier or not in OR context - process normally
            field_collections.each do |collection|
              transformed_qualifiers << create_field_qualifier(transformed_field_name, collection)
            end
          end
        end

        # Second pass: apply OR logic to the transformed qualifiers
        transformed_qualifiers.each do |item|
          qualifier = item[:qualifier]
          is_field_qualifier = item[:is_field]

          if bool_type == OR_BOOL_TYPE && filter_qualifiers.count > 1
            field_type = is_field_qualifier ? @field_types[qualifier.field] : nil
            uses_enumerated_filter = field_type && field_type != "number" && field_type != "date"

            if simple_enumerable_terms.include?(qualifier.field) ||
              (qualifier.field == :type && !type_issue_or_pr(qualifier.collection)) ||
              uses_enumerated_filter
              # Use and_should for enumerated terms and field qualifiers that use EnumeratedTermFilter
              qualifier.collection.and_should(qualifier.collection.must&.dup) if qualifier.collection.must.present?
            else
              # Use should for regular OR operations and for number/date field qualifiers
              qualifier.collection.should(qualifier.collection.must&.dup) if qualifier.collection.must.present?
            end
            qualifier.collection.must&.clear
          end

          if qualifier.field == :type && !type_issue_or_pr(qualifier.collection)
            # if the type is not "issue" or "pr", we need to add issue_type to the collection
            # to search for other types like Task, Epic, etc.
            if collections.key?(:issue_type)
              collections[:issue_type].merge!(qualifier.collection)
            else
              collections[:issue_type] = qualifier.collection
            end
          # if the key exists, then merge to the existing collection
          elsif collections.key?(qualifier.field)
            collections[qualifier.field].merge!(qualifier.collection)
          elsif !(is_field_qualifier && is_global_search)
            collections[qualifier.field] = qualifier.collection.dup
          end
        end

        # Remove fields that are marked as mutually incompatible with each other.
        # We reverse the field list because if we see both we want to keep the last one in the list.
        ::Search::Queries::IssueQuery::INCOMPATIBLE_FIELDS.each do |label, fields|
          incompatible_seen = Set.new
          fields.reverse_each do |field|
            if collections.key?(field)
              if incompatible_seen.include?(label)
                collections.delete(field)
              else
                incompatible_seen.add(label)
              end
            end
          end
        end

        builder = ::Search::FilterBuilder.new(collections)
        has_repo_qualifier = qualifiers[:repo]&.must&.any?
        exclude_private_profiles = @repo_id.nil? && !has_repo_qualifier

        filters = T.let({}, T::Hash[Symbol, ::Search::Filter])
        filters[:labels] = builder.label_filter(:labels, :label, execution: bool_type, missing: :none)
        # Skip state filter in main query if it should be applied as post_filter
        filters[:state] = builder.term_filter(:state, execution: bool_type) unless state_in_post_filter?
        filters[:status] = builder.term_filter(:status, execution: bool_type)
        filters[:merged] = builder.term_filter(:merged, :merged_state, execution: bool_type)

        filters[:head_ref] = builder.prefix_filter(:head_ref, :head, execution: bool_type) { |ref| ref.downcase }
        filters[:base_ref] = builder.prefix_filter(:base_ref, :base, execution: bool_type) { |ref| ref.downcase }

        filters[:draft] = builder.term_filter(:draft, execution: bool_type) do |value|
          case value
          when /true/i; true
          when true; true
          else false
          end
        end
        filters[:public] = builder.term_filter(:public, execution: bool_type)
        filters[:locked] = builder.term_filter(:locked, execution: bool_type)
        filters[:queued] = builder.term_filter(:queued, execution: bool_type)
        filters[:reviewable_state] = builder.term_filter(:reviewable_state, :"reviewable-state", execution: bool_type)
        filters[:author_id] = builder.user_filter(:author_id, :author, current_user: current_user, exclude_private_profiles: exclude_private_profiles, execution: bool_type)
        filters[:assignee_id] = builder.user_filter(:assignee_id, :assignee, missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles, execution: bool_type)
        filters[:project_ids] = builder.issue_project_and_memex_project_filter(:project, current_user: current_user, execution: bool_type)

        filters[:milestone_number] = builder.presence_term_filter(:milestone_num, :"milestone-number", execution: bool_type)
        filters[:milestone] = builder.presence_term_filter(:milestone_title, :milestone, execution: bool_type) do |value|
          value.downcase
        end

        filters[:mentioned_users] = builder.user_filter(:mentioned_user_ids, :mentions, current_user: current_user, exclude_private_profiles: exclude_private_profiles, execution: bool_type)
        filters[:mentioned_teams] = builder.team_filter(current_user, :mentioned_team_ids, :team, execution: bool_type)
        filters[:commenter] = builder.user_filter("comments.author_id", :commenter, current_user: current_user, exclude_private_profiles: exclude_private_profiles, execution: bool_type)

        filters[:created_at] = builder.date_range_filter(:created_at, :created, execution: bool_type)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated, execution: bool_type)
        filters[:merged_at]  = builder.date_range_filter(:merged_at,  :merged, execution: bool_type)
        filters[:closed_at]  = builder.date_range_filter(:closed_at,  :closed, execution: bool_type)

        filters[:num_comments]  = builder.range_filter(:num_comments, :comments, execution: bool_type)
        filters[:num_reactions] = builder.range_filter(:num_reactions, :reactions, execution: bool_type)
        filters[:num_interactions] = builder.range_filter(:num_interactions, :interactions, execution: bool_type)

        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language, :lang, execution: bool_type)
        filters[:involves] = builder.involves_filter(
          [:author_id, :assignee_id, :mentioned_user_ids, :requested_reviewer_ids, :reviewer_ids, "comments.author_id"],
          :involves,
          current_user: current_user,
          exclude_private_profiles: exclude_private_profiles,
          execution: bool_type
        )
        filters[:review_status] = builder.term_filter(:review_status, :review)
        filters[:reviewer_ids] = builder.user_filter(:reviewer_ids, :"reviewed-by", missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:requested_reviewer_ids] = builder.review_request_filter(:requested_reviewer_ids, :"review-requested", missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:requested_reviewer_user_ids] = builder.user_review_request_filter(:requested_reviewer_user_ids, :"user-review-requested", current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:"team-review-requested"] = builder.team_filter(current_user, :requested_reviewer_team_ids, :"team-review-requested")
        if FeatureFlag.vexi.enabled?(:team_review_requested_by_user_filter, current_user, default: false)
          filters[:team_review_requested_by_user] = builder.team_review_requested_by_user_filter(:requested_reviewer_team_ids, :"team-review-requested-user", current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        end
        filters[:issue_type_name] = builder.issue_type_name_filter(:issue_type, execution: bool_type)

        filters[:parent_issue] = builder.enumerated_term_filter(:parent_issue, :"parent-issue", execution: bool_type, missing: :none)
        filters[:parent_issue]&.map_bool_collection { |v| v.downcase }
        filters[:sub_issue] = builder.enumerated_term_filter(:sub_issue, :"sub-issue", execution: bool_type, missing: :none)
        filters[:sub_issue]&.map_bool_collection { |v| v.downcase }

        filters[:open_blocked_by_count] = builder.range_filter(:open_blocked_by_count, execution: bool_type)
        filters[:open_blocking_count] = builder.range_filter(:open_blocking_count, execution: bool_type)

        filters[:blocking] = builder.enumerated_term_filter(:blocking, :blocking, execution: bool_type, missing: :none)
        filters[:blocking]&.map_bool_collection { |v| v.downcase }
        filters[:blocked_by] = builder.enumerated_term_filter(:blocked_by, :"blocked-by", execution: bool_type, missing: :none)
        filters[:blocked_by]&.map_bool_collection { |v| v.downcase }

        filters[:type] = builder.prefix_filter(:_index, :type, execution: bool_type) do |value|
          #if the type is "issue" or "pr" we need to map it to the field "_index"
          case value
          when "pr"; "pull-requests"
          when "pull-request"; "pull-requests"
          when "issue"; "issues"
          else
            value
          end
        end

        filters[:archived] = builder.term_filter(:archived, singular: true, execution: bool_type) do |value|
          case value
          when /true/i; true
          when true; true
          else false
          end
        end

        filters[:state_reason] = builder.state_reason_filter(:reason, accept_multiple_reasons: true, execution: bool_type)

        filters[:has_closing_reference] = builder.term_filter(:has_closing_reference, :linked, singular: true) do |value|
          case value
          when /issue/i; true
          when /pull-request/i; true
          when /pr/i; true
          else nil
          end
        end

        # These values are taken from Search::Queries::IssueQuery#build_repository_filter
        resource = "issues"
        if collections.include?(:type) && (collections[:type].must == ["pull-request"] || collections[:type].must == ["pr"])
          resource = "pull_requests"
        end

        filters[:repo_id] = builder.conditional_repository_filter(
          current_user,
          @repo_id,
          user_session: user_session,
          ip: remote_ip,
          execution: bool_type,
          resource: resource,
          limit_to_repo_ids: @limit_to_repo_ids,
          pre_resolved_repo_ids: @pre_resolved_repo_ids
        )
        field_filters = {}
        if qualifiers.keys.any? { |k| k.to_s =~ /\Afield(\.|$)/ } && issue_fields_enabled?
          field_filters = builder.issue_fields_filter(
            :field,
            /^field\.\d+$/,
            execution: bool_type,
            field_types: @field_types,
            orgs_size:  query_scoped_org_ids&.size || 0
          )
          if !is_global_search
            # otherwise we add it later, after we build the BoolCollection for the filters;
            # the global field filter is not standard sowe handle it separately
            filters.merge!(field_filters)
          end
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        filters.each_value do |filter|
          unless filter.valid?
            @valid_filters = false
            @invalid_reason = filter.invalid_reason
          end
        end

        bool_collection = ::Search::Filters::BoolFilter.new(filters)

        # merge the field filters in should if possible
        query_fragment = bool_collection.build

        # Add field.global filter to :must, handling array, nil, and single value cases
        if field_filters.key?(:field_global)
          field_global_hash = field_filters[:field_global]
          # Collect all bool fragments from the hash values, filtering out invalid ones
          # (those with nil or empty should clauses)
          bools = field_global_hash.values.compact.select do |bool_fragment|
            bool_fragment.is_a?(Hash) &&
            bool_fragment[:bool].is_a?(Hash) &&
            !bool_fragment[:bool][:should].nil? &&
            (bool_fragment[:bool][:should].is_a?(Array) ? !bool_fragment[:bool][:should].empty? : true)
          end

          if !query_fragment.nil? && query_fragment[:bool]
            must = query_fragment[:bool][:must]
            if must.is_a?(Array)
              must.concat(bools)
            elsif must.nil?
              query_fragment[:bool][:must] = bools
            else
              query_fragment[:bool][:must] = [must, *bools].compact
            end
          elsif !bools.empty?
            # If there's no query_fragment yet (only field qualifiers), create one
            query_fragment = { bool: { must: bools } }
          end
        end

        if !query_fragment.nil? && query_fragment[:bool]

          if bool_type == OR_BOOL_TYPE && query_fragment[:bool] && query_fragment[:bool][:must_not]
            # Multiple negated OR filters need to behave as AND to return the correct results.
            # The query "-label:bug OR -label:epic" should return all issues exept the one that has both labels bug and epic.
            # To handle this, we wrap the multiple negated must_not's in a bool query with a must clause.
            # Example: { bool: { must_not: { bool: { must: [{ term: { labels: "bug" } }, { term: { labels: "epic" } }] } } } }
            query_fragment[:bool][:must_not] = {
              bool: {
                must: query_fragment[:bool][:must_not]
              }
            }
          end

          if query_fragment[:bool][:must]
            if filters.values.all?(&:valid?)
              query_fragment[:bool][:must] = add_open_state_to_query(query_fragment[:bool][:must])
            end
          end

          if query_fragment[:bool][:should]
            query_fragment[:bool][:minimum_should_match] = 1
          end
        end

        query_fragment
      end

      # Check if a clause contains blocking or blocked-by dependency queries
      sig { params(clause: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      private def has_issue_dependencies?(clause)
        clause[:range].present? && (
          clause[:range][:open_blocked_by_count].present? ||
          clause[:range][:open_blocking_count].present?
        )
      end

      # Issues that are blocked or blocking can only be open.
      # This method adds state:open when blocked/blocking queries are present.
      sig do
        params(
          query_clause: T.any(
            T::Hash[Symbol, T.untyped],
            T::Array[T::Hash[Symbol, T.untyped]]
          )
        ).returns(T.any(
          T::Hash[Symbol, T.untyped],
          T::Array[T::Hash[Symbol, T.untyped]]
        ))
      end
      def add_open_state_to_query(query_clause)
        if query_clause.is_a?(Array) && query_clause.any? { |clause| has_issue_dependencies?(clause) }
          return query_clause.dup << { term: { state: "open" } }
        elsif query_clause.is_a?(Hash) && has_issue_dependencies?(query_clause)
          return [query_clause, { term: { state: "open" } }]
        end
        query_clause
      end

      # This is overridden from IssueQuery#use_candidate_repo_search?
      # The base implementation checks the presence of :user, :org, and :owner keys on `qualifiers`. However
      # qualifiers is defined in ParsedQueries as a hash that defaults its values to instances of BoolCollection.
      # Because we depend on calling `qualifiers_to_filters` multiple times and there are code paths that access
      # these keys it's possible for this to be called multiple times and get a different response each time. So
      # we don't check for the presence of these particular keys, we check if they have any value.
      def use_candidate_repo_search?
        return false if @repo_id.present?
        return false if current_user.blank?
        return false if @limit_to_repo_ids.present?
        return false if !@pre_resolved_repo_ids.nil?
        return false unless qualifiers[:user].blank?
        return false unless qualifiers[:org].blank?
        return false unless qualifiers[:owner].blank?
        return false if qualifiers[:public].must == [true]

        qualifiers.keys.any? { |qualifier| CANDIDATE_REPO_SEARCH_QUALIFIERS.include?(qualifier) }
      end

      def escape_query(value)
        q = Search.escape_characters(value).tr("<>", " ")
        (q =~ /\A["\s\\]*\z/ ? "" : q)
      end

      def index_name_for_type_param
        case @index_type
        when Search::ParsletQuery::IndexType::Issue
          "issues"
        when Search::ParsletQuery::IndexType::PullRequest
          "pull-requests"
        else
          "issues-search"
        end
      end

      # Returns the correct index for the type of search.
      def index_for_type_param
        index_name = index_name_for_type_param

        if index_name == "issues-search"
          @index # return the default index from parent class (issues-search) which contains both issues and prs.
        else
          Elastomer::Indexes::Issues.searcher(index_name + Elastomer.env.postfix.to_s)
        end
      end

      # Internal: Returns a searcher for the dedicated PRs experiment index when
      # routing conditions are met, or nil otherwise. Called by semantic/hybrid
      # subclass overrides of index_for_type_param so the check only runs for
      # semantic-intent queries.
      def dedicated_prs_index_searcher
        index_name = index_name_for_type_param
        return nil if index_name == "issues"
        return nil unless should_use_dedicated_prs_index?

        dedicated_index = GitHub.es_semantic_experiment_prs_index_name
        if index_name == "pull-requests"
          Elastomer::Indexes::Issues.searcher(dedicated_index)
        else
          # Combined query: search issues index + dedicated PRs index.
          # Resolve the cluster from the known issues index name because
          # the comma-separated combined name is not in the router's index
          # map and would raise Elastomer::UnknownIndex in multi-cluster
          # environments.
          issues_index_name = "issues#{Elastomer.env.postfix}"
          cluster = ::Elastomer.router.cluster_for_index(issues_index_name)
          Elastomer::Indexes::Issues.searcher("#{issues_index_name},#{dedicated_index}", cluster)
        end
      end

      # Internal: Determines whether queries should be routed to the dedicated PRs index.
      # Returns true when the dedicated PRs index name is configured.
      def should_use_dedicated_prs_index?
        GitHub.es_semantic_experiment_prs_index_name.present?
      end

      # check if the collection includes issue or pr
      sig { params(collection: ::Search::ParsedQuery::BoolCollection).returns(T::Boolean) }
      def type_issue_or_pr(collection)
        must_value          = collection.must ? collection.must : []
        should_value        = collection.should ? collection.should : []
        must_not_value      = collection.must_not ? collection.must_not : []
        and_should_value    = collection.and_should ? collection.and_should.flatten : []
        includes_type_issue = (must_value + should_value + must_not_value + and_should_value).any? { |search| %w(issue issues).include?(search) }
        includes_type_pr    = (must_value + should_value + must_not_value + and_should_value).any? { |search| %w(pr pull-request).include?(search) }

        includes_type_issue || includes_type_pr
      end

      sig { override.params(exception: T.nilable(Exception)).returns(T::Array[String]) }
      def datadog_tags(exception = nil)
        super.tap do |tags|
          depth = @query_depth.to_i
          if depth > 4
            tags << "query_depth:5+"
          elsif depth > 0
            tags << "query_depth:#{depth}"
          end

          tags << "complexity:#{query_complexity_level}"
          tags << query_text_tag
          tags << "query_scope:#{query_scope_tag}"
        end
      end

      sig { returns(String) }
      def query_scope_tag
        if @repo_id || qualifiers.fetch(:repo, nil)&.must?
          "repo"
        elsif qualifiers.fetch(:org, nil)&.must?
          "org"
        elsif qualifiers.fetch(:user, nil)&.must?
          "user"
        elsif qualifiers.fetch(:owner, nil)&.must?
          "owner"
        else
          "unscoped"
        end
      end

      sig { params(custom_tags: T::Array[String]).returns(T::Array[String]) }
      def custom_tags(custom_tags = [""])
        tags = datadog_tags

        custom_tags.each do |custom_tag|
          tags << custom_tag if custom_tag.present?
        end

        tags
      end

      # Transform field.{name}:{value} qualifiers into field.{id}:{option_id} format
      sig { params(qualifier: ParsletQuery::Qualifier).returns(T.nilable(::Search::ParsedQuery::BoolCollection)) }
      def transform_field_qualifier(qualifier)
        field_key = qualifier.field.to_s
        # Handle plain "field" qualifier for checking absence/presence of any field values
        if field_key == "field"
          transformed_collection = ::Search::ParsedQuery::BoolCollection.new("field")

          # Handle the special case of :missing for no:field queries (issues without any field values)
          if qualifier.collection.must.include?(:missing)
            transformed_collection.must(:missing)
          end

          # Handle the special case of :exists for has:field queries (issues with any field values)
          if qualifier.collection.must.include?(:exists)
            transformed_collection.must(:exists)
          end

          return transformed_collection.blank? ? nil : transformed_collection
        end

        return unless field_key.start_with?("field.")

        # Extract field name from field.{name}
        field_name = field_key.sub(/^field\./, "")

        # Find the field by name_slug, scoped to the repository's organization
        repo = Repository.find_by(id: @repo_id) if @repo_id
        if repo && repo.owner&.organization?
          field = ::Issues::Domain::IssueFields.issue_field_by_name_slug_and_repo_owner(field_name, repo)
          return create_field_no_match_collection(FAKE_FIELD_ID, "field_#{field_name}") unless field
          # Ensure the current user has visibility access to this field
          return create_field_no_match_collection("field.#{field.id}", field.id.to_s) unless field.viewable_by?(viewer: current_user)
          build_field_bool_collection(field, qualifier)
        elsif !@repo_id && current_user && current_user.feature_flag_enabled?(IssueFieldsFeature::ISSUE_FIELDS_USER_FLAG, default: false)
          # For global searches, we need to find fields across organizations
          # Return no-match collection if: user has no orgs, field doesn't exist, or all values are invalid
          return create_field_no_match_collection(FAKE_FIELD_ID, "field_#{field_name}", wrap_in_should: true) if query_scoped_org_ids.blank?

          fields = ::Issues::Domain::IssueFields.issue_fields_by_name_slug_and_owner_ids(field_name, query_scoped_org_ids)
          return create_field_no_match_collection(FAKE_FIELD_ID, "field_#{field_name}", wrap_in_should: true) if fields.blank?

          # Filter to only fields the current user can see based on visibility settings
          visible_fields = fields.select { |f| f.viewable_by?(viewer: current_user) }
          return create_field_no_match_collection(FAKE_FIELD_ID, "field_#{field_name}", wrap_in_should: true) if visible_fields.empty?

          should_collections = visible_fields.filter_map { |field| build_field_bool_collection(field, qualifier) }
          return create_field_no_match_collection(FAKE_FIELD_ID, "field_#{field_name}", wrap_in_should: true) if should_collections.empty?

          combined_collection = ::Search::ParsedQuery::BoolCollection.new(nil)
          should_collections.each { |col| combined_collection.should(col) }

          combined_collection
        end
      end

      private

      # Returns true if state filter should be applied as post_filter instead of in the main query.
      # Subclasses can override this to implement custom logic.
      # By default, state is always included in the main query.
      def state_in_post_filter?
        false
      end

      # Helper method to create a no-match collection for field queries.
      # This ensures that invalid or inaccessible field queries return zero results
      # instead of being dropped from the query entirely.
      sig { params(field_identifier: String, match_key: String, wrap_in_should: T::Boolean).returns(::Search::ParsedQuery::BoolCollection) }
      def create_field_no_match_collection(field_identifier, match_key, wrap_in_should: false)
        @field_types[field_identifier.to_sym] = "text" # Treat as text field
        no_match_inner = ::Search::ParsedQuery::BoolCollection.new(field_identifier)
        no_match_inner.must("__no_match_#{match_key}__")

        if wrap_in_should
          no_match_collection = ::Search::ParsedQuery::BoolCollection.new(field_identifier)
          no_match_collection.should(no_match_inner)
          no_match_collection
        else
          no_match_inner
        end
      end

      # Memoized access to current user's organization IDs to prevent N+1 queries
      # during field qualifier processing. Limits to first 100 organizations for performance.
      memoize def query_scoped_org_ids
        result = if @repo_id && repository&.owner&.organization?
          T.must(T.must(repository).owner).id
        elsif @orgs_scoped
          Organization.where(login: @orgs_scoped).pluck(:id)
        else
          org_ids = current_user&.organization_ids || []
          if org_ids.count > ::Issues::Domain::IssueFields::ORGANIZATION_LIMIT
            org_ids.first(::Issues::Domain::IssueFields::ORGANIZATION_LIMIT)
          else
            org_ids
          end
        end
        result
      end

      def build_field_bool_collection(field, qualifier)
        field_id = "field.#{field.id}"
        transformed_collection = ::Search::ParsedQuery::BoolCollection.new(field_id)

        # Save field type
        @field_types[field_id.to_sym] = field.data_type

        # Handle the special case of :missing values for no:field.{name} queries
        if qualifier.collection.must&.include?(:missing)
          transformed_collection.must(:missing)
        end

        # Handle the special case of :exists values for has:field.{name} queries
        if qualifier.collection.must&.include?(:exists)
          transformed_collection.must(:exists)
        end

        # Track if any regular (non-special) values were requested
        has_regular_values = [
          qualifier.collection.must,
          qualifier.collection.and_should,
          qualifier.collection.should,
          qualifier.collection.must_not
        ].any? { |values| values && !values.empty? && values.any? { |v| v != :missing && v != :exists } }

        # Process each collection type using the helper method
        # The :and_should collection contains enumerated, comma-separated values (e.g., "field.priority:high,urgent").
        # These should remain as :and_should when passed to EnumeratedTermFilter, because EnumeratedTermFilter
        # expects to receive all values together and will create proper ElasticSearch bool queries where each
        # comma-separated group becomes a terms query that must match (AND-semantics for multiple groups).
        # This differs from :should collections which would create OR-semantics across the values.
        process_field_collection_values(qualifier.collection.must, field, transformed_collection, :must)
        process_field_collection_values(qualifier.collection.and_should, field, transformed_collection, :and_should)
        process_field_collection_values(qualifier.collection.should, field, transformed_collection, :should)
        process_field_collection_values(qualifier.collection.must_not, field, transformed_collection, :must_not)

        # If the user explicitly searched for field values but none were valid (e.g., nonexistent options),
        # we should return a collection that matches nothing rather than nil which would drop the filter.
        # This ensures the search returns 0 results instead of ignoring the invalid field filter.
        if transformed_collection.blank? && has_regular_values
          # Create a collection with an impossible-to-match condition
          return create_field_no_match_collection(field_id, field.id.to_s)
        end

        transformed_collection.blank? ? nil : transformed_collection
      end

      # Helper method to process field collection values and transform them appropriately
      sig { params(values: T.untyped, field: IssueField, collection: ::Search::ParsedQuery::BoolCollection, collection_type: Symbol).void }
      def process_field_collection_values(values, field, collection, collection_type)
        return unless values

        normalized_values = values.is_a?(Array) ? values.flatten : [values]

        # Separate special values from regular values
        special_values = normalized_values.select { |v| v == :missing || v == :exists }
        regular_values = normalized_values.reject { |v| v == :missing || v == :exists }

        # Handle special values (:missing and :exists) individually.
        # These special values indicate the absence or presence of a field, respectively.
        # They will be transformed into proper ElasticSearch exists queries by the TermFilter,
        # so we add them to the collection as-is without field value transformation.
        special_values.each do |value|
          if value == :missing
            collection.must(:missing) if collection_type == :must
          elsif value == :exists
            collection.must(:exists) if collection_type == :must
          end
        end

        # Transform regular values
        transformed_values = regular_values.map { |value| transform_field_value(field, value) }.compact

        return if transformed_values.empty?

        # Add transformed values to the collection
        # For single values in and_should, we need to wrap in array due to BoolCollection interface requirements
        values_to_add = if transformed_values.size == 1 && collection_type == :and_should
          [transformed_values.first]
        else
          transformed_values
        end

        case collection_type
        when :must
          collection.must(values_to_add)
        when :should
          collection.should(values_to_add)
        when :and_should
          collection.and_should(values_to_add)
        when :must_not
          collection.must_not(values_to_add)
        end
      end

      # Transform a single field value based on the field's data type
      sig { params(field: IssueField, value: T.untyped).returns(T.nilable(String)) }
      def transform_field_value(field, value)
        case field.data_type
        when "single_select"
          # Find the option by name and use its ID
          option = field.options.find_by(name: value)
          option&.id&.to_s
        when "text"
          # Text fields are stored lowercased in ElasticSearch (see IssueFieldTextValue#elasticsearch_value)
          # so we need to lowercase the search value for exact matching
          value.to_s.downcase
        when "date", "number"
          # For date/number fields, use the value directly
          value.to_s
        end
      end

      sig { returns(T::Boolean) }
      memoize def is_global_search
        !@repo_id
      end

      # Check whether issue fields are enabled for the current user, repository, or organization
      sig { returns(T::Boolean) }
      memoize def issue_fields_enabled?
        return true if !@repo_id && current_user && current_user.feature_flag_enabled?(IssueFieldsFeature::ISSUE_FIELDS_USER_FLAG, default: false)
        return false unless @repo_id

        context = IssueFieldsFeature::Context::ElasticSearch
        return false unless repository

        return true if IssueFieldsFeature.enabled?(T.must(repository), context: context)

        owner = repository&.owner
        !!(owner&.organization? && IssueFieldsFeature.enabled?(owner, context: context))
      end

      sig { returns(T.nilable(Repository)) }
      memoize private def repository
        return unless @repo_id && @repo_id.is_a?(Integer)
        T.cast(::Repositories.domain.by_id(@repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      end

      sig { returns(String) }
      def query_complexity_level
        depth = @query_depth.to_i
        q_count = @qualifier_count || 0

        return "text_only" if depth <= 1 && q_count == 0 && @has_text_terms
        return "very_complex" if depth >= 4 || q_count > 12
        return "complex" if @complex || depth >= 3 || q_count > 6
        return "simple" if depth <= 1 && q_count <= 2

        "medium"
      end

      sig { returns(String) }
      def query_text_tag
        @has_text_terms ? "query_text:true" : "query_text:false"
      end
    end
  end
end
