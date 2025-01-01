# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueQuery < ::Search::Queries::IssueQuery
      # These are fields that support the "no:<field>" and the "has:<field>" syntax. This is passed to the parser so it knows to look for
      # this syntax and set the appropriate values in the BoolCollection for that field.
      #
      # See IssueQuery#qualifiers= for where this list of fields comes from
      PRESENCE_VALUE_FIELDS = {
        label: :label,
        labels: :label,
        milestone: :milestone,
        milestones: :milestone,
        project: :project,
        assignee: :assignee,
        type: :issue_type,
        "review-requested": :"review-requested",
        "reviewed-by": :"reviewed-by",
        "parent-issue": :"parent-issue",
        "sub-issue": :"sub-issue",
      }

      QUERY_DEPTH_LIMIT = 5
      QUERY_DEPTH_ERROR_MESSAGE = "Query clause limit exceeded"
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
      }

      # These are qualifiers that are interpreted by the parser to be at the top level no matter which level
      # we find them in. They're also removed from the list of qualifiers before we start building the query.
      TOP_LEVEL_TERMS = [
        :user, :org, :owner, :repo, :sort
      ]

      # terms that support <field_name>:*
      WILDCARDABLE_TERMS = [:assignee, :milestone]

      AGGREGATION_FIELDS = [:language_id, :state]

      sig { returns(ParsletQuery::BoolQualifier) }
      attr_accessor :conditional_qualifiers

      sig { returns(T::Array[ParsletQuery::Qualifier]) }
      attr_accessor :top_level_qualifiers

      sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
      attr_accessor :aggregation_qualifiers

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
            enumerable_terms: enumerable_terms,
            wildcardable_terms: WILDCARDABLE_TERMS,
            top_level_terms: TOP_LEVEL_TERMS,
            aggregation_fields: aggregations.present? ? AGGREGATION_FIELDS : []
          )
        end
        @is_valid = pq.valid_query?
        self.query = pq.query
        GitHub.dogstats.distribution_time("search.advanced_search.set_qualifiers") do
          self.qualifiers = pq.qualifiers
          self.conditional_qualifiers = pq.conditional_qualifiers
          self.top_level_qualifiers = pq.top_level_qualifiers
          self.aggregation_qualifiers = pq.aggregation_qualifiers
        end
        @complex = pq.complex?
        @index_type = pq.index_type
        @repo_filter = nil
        @valid_filters = true
        @query_depth = 0
      end

      sig { override.returns(T.nilable(T::Boolean)) }
      private def complex?
        @complex
      end

      # The fields that are enumerable with commas.
      # This overrides the method in IssueQuery.
      # We cannot add onto the method in IssueQuery because it uses different parsing.
      sig { returns T::Array[Symbol] }
      def enumerable_terms
        [:label, :type, :"parent-issue", :"sub-issue"]
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

          unless repository_filter.valid?
            @invalid_reason = repository_filter.invalid_reason
            return false
          end

          true
        end
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

        # Right now build_repository_filter uses the global filter builder. We probably want to re-implement this
        # so we can define our own filter builder that is only passed the qualifiers contained in top_level_terms.
        @repo_filter = build_repository_filter(candidate_private_repo_ids: candidate_private_repo_ids)

        # We will also need to override valid_query?. That function, currently defined in IssueQuery and Query, is calling
        # @filter_hash and checking if it includes repo_id. We need to change that to not depend on @filter_hash.

        # Once we've generated the repo filter we need to call `.must` and/or `.must_not`. We then need to combine
        # that with our query so we are forcing the repo filtering to apply to our conditions.
        @query_filter = {
          bool: {
            must: filtered_query.nil? ? @repo_filter.must : [@repo_filter.must, filtered_query]
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

      # Internal: Returns the Array of field names that will be queried.
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

      sig { params(qualifier: ParsletQuery::QueryQualifier, search_in_fields: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifier_to_query(qualifier, search_in_fields)
        query = {
          function_score: {
            query: {
              query_string: {
                query: escape_query(qualifier.query),
                fields: query_fields_to_search(search_in_fields),
                phrase_slop: 10,
                default_operator: "AND",
                analyzer: "texty_search",
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
          if bool_type == OR_BOOL_TYPE && filter_qualifiers.count > 1
            if qualifier.field == :label || (qualifier.field == :type && !type_issue_or_pr(qualifier.collection))
              # label and type use `Search::Filters::EnumeratedTermFilter`
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
        filters[:requested_reviewer_ids] = builder.review_request_filter(:requested_reviewer_ids, :"review-requested", missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles, execution: bool_type)
        filters[:requested_reviewer_user_ids] = builder.user_review_request_filter(:requested_reviewer_user_ids, :"user-review-requested", current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:"team-review-requested"] = builder.team_filter(current_user, :requested_reviewer_team_ids, :"team-review-requested")
        filters[:issue_type_name] = builder.issue_type_name_filter(:issue_type, execution: bool_type)

        filters[:parent_issue] = builder.enumerated_term_filter(:parent_issue, :"parent-issue")
        filters[:parent_issue]&.map_bool_collection { |v| v.downcase }
        filters[:sub_issue] = builder.enumerated_term_filter(:sub_issue, :"sub-issue")
        filters[:sub_issue]&.map_bool_collection { |v| v.downcase }

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

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        filters.each_value do |filter|
          unless filter.valid?
            @valid_filters = false
            @invalid_reason = filter.invalid_reason
          end
        end

        bool_collection = ::Search::Filters::BoolFilter.new(filters)
        query_fragment = bool_collection.build

        if !query_fragment.nil? && query_fragment[:bool] && query_fragment[:bool][:should]
          query_fragment[:bool][:minimum_should_match] = 1
        end

        query_fragment
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
    end
  end
end
