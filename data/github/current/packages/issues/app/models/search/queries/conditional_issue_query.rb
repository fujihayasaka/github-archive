# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueQuery < ::Search::Queries::IssueQuery
      include GitHub::Memoizer

      def self.field_list
        super + [:"milestone-number", :"blocked-by", :blocking, :blocked, :field]
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
      TOP_LEVEL_TERMS = [:sort]

      OWNERSHIP_TERMS = [:repo, :org, :user, :owner]

      # terms that support <field_name>:*
      WILDCARDABLE_TERMS = [:assignee, :milestone, :"milestone-number"]

      AGGREGATION_FIELDS = [:language_id, :state]

      # phrase slop limits how far phrase text terms can be apart from each other, making the overall
      # query more efficient for long documents
      DEFAULT_PHRASE_SLOP_VALUE = 10

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
        @is_valid = pq.valid_query?
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

        # The global repository filter builder is still used in advanced search to ensure that the query
        # will only access allowed repo ids, regardless of the ownership filters used in the query.
        @repo_filter = build_repository_filter(candidate_private_repo_ids: candidate_private_repo_ids)

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
        filter_qualifiers.select { |q| q.field == :in }.each do |q|
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
        if qualifier.type == OR_BOOL_TYPE && filter_qualifiers.size
          must_not_filter_qualifiers = filter_qualifiers.select { |q| q.collection.must_not.present? || q.collection.must == [:missing] }
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

        filter_qualifiers.each do |qualifier|
          # Remember if this was originally a field qualifier before transformation
          is_field_qualifier = issue_fields_enabled? && qualifier.field.to_s.start_with?("field.")

          # Transform field qualifiers before processing them like normal qualifiers
          if is_field_qualifier
            transformed_collection = transform_field_qualifier(qualifier)
            if transformed_collection
              qualifier = ParsletQuery::Qualifier.new(
                field: transformed_collection.name.to_sym,
                collection: transformed_collection
              )
            else
              next # Skip if transformation failed
            end
          end

          if bool_type == OR_BOOL_TYPE && filter_qualifiers.count > 1
            if simple_enumerable_terms.include?(qualifier.field) ||
              (qualifier.field == :type && !type_issue_or_pr(qualifier.collection)) ||
              is_field_qualifier
              # label, language, type, and field use `Search::Filters::EnumeratedTermFilter`
              # which internally requires an `and_should` collection
              qualifier.collection.and_should(qualifier.collection.must&.dup)
            else
              qualifier.collection.should(qualifier.collection.must&.dup)
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
          else
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
        exclude_private_profiles = @repo_id.nil?

        filters = T.let({}, T::Hash[Symbol, ::Search::Filter])
        filters[:labels] = builder.label_filter(:labels, :label, execution: bool_type, missing: :none)
        filters[:state] = builder.term_filter(:state, execution: bool_type)
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
        filters[:milestone] = builder.milestone_filter(:milestone, execution: bool_type)
        filters[:milestone_number] = builder.milestone_number_filter(:"milestone-number", execution: bool_type)
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
          resource: resource
        )

        # For each qualifier that has a key starting with `field`, which is only properly transformed for the builder's collections
        # we must build a enumerated term filter where the key is field.field_id
        builder.qualifiers.each do |key, _collection|
          if key.to_s.start_with?("field.") && issue_fields_enabled?
            case @field_types[key]
            when "date"
              filters[key] = builder.keyword_date_range_filter(key, key, execution: bool_type)
            when "number"
              filters[key] = builder.keyword_range_filter(key, key, execution: bool_type)
            else
              filters[key] = builder.enumerated_term_filter(key, key, execution: bool_type)
            end
          end
        end

        # Handle plain "field" qualifier for checking absence of any field values (no:field)
        if builder.qualifiers.include?(:field) && issue_fields_enabled?
          filters[:field] = builder.term_filter(:field, execution: bool_type)
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        filters.each_value do |filter|
          unless filter.valid?
            @valid_filters = false
            @invalid_reason = filter.invalid_reason
          end
        end

        bool_collection = ::Search::Filters::BoolFilter.new(filters)
        query_fragment = bool_collection.build

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
            if FeatureFlag.vexi.enabled?(:swap_backwards_range, default: false)
              if filters.values.all?(&:valid?)
                query_fragment[:bool][:must] = add_open_state_to_query(query_fragment[:bool][:must])
              end
            else
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

      sig { params(exception: T.nilable(Exception)).returns(T::Array[String]) }
      def datadog_tags(exception = nil)
        super.tap do |tags|
          next if @query_depth.nil?
          if @query_depth > 4
            tags << "query_depth:5+"
          elsif @query_depth > 0
            tags << "query_depth:#{@query_depth}"
          end
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
        field = if repo && repo.owner&.organization?
          IssueField.find_by(name_slug: field_name, owner: repo.owner)
        else
          IssueField.find_by(name_slug: field_name)
        end
        return unless field

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

        transformed_collection.blank? ? nil : transformed_collection
      end

      private

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
        when "text", "date", "number"
          # For text/date/number fields, use the value directly
          value.to_s
        end
      end

      # Check whether issue fields are enabled for the current user, repository, or organization
      sig { returns(T::Boolean) }
      def issue_fields_enabled?
        return false unless @repo_id

        context = IssueFieldsFeature::Context::ElasticSearch
        repo = Repository.find_by(id: @repo_id)
        return false unless repo

        return true if IssueFieldsFeature.enabled?(repo, context: context)

        owner = repo.owner
        !!(owner&.organization? && IssueFieldsFeature.enabled?(owner, context: context))
      end
    end
  end
end
