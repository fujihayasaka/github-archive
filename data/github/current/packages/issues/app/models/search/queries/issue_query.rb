# typed: true
# frozen_string_literal: true

require "set"

module Search
  module Queries

    class IssueQuery < ::Search::Query

      # The set of fields that can be queried when performing a issue search
      def self.field_list
        [
          :in, :sort, :author, :assignee, :"team-review-requested", :mentions, :commenter, :involves,
          :milestone, :label, :lang, :language, :team, :user, :org, :owner, :repo, :created,
          :updated, :merged, :closed, :comments, :type, :state, :is, :no, :status,
          :head, :base, :reactions, :interactions, :project, :"user-review-requested",
          :review, :"reviewed-by", :"review-requested", :archived, :draft, :linked, :"reviewable-state",
          :reason
        ].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [
          :assignee, :author, :linked, :milestone, :mentions, :review, :"team-review-requested", :"user-review-requested",  :"review-requested", :"reviewed-by", :sort, :state, :type, :status,
          :reason
        ]
      end

      # A list of term-sets that are mutually incompatible.  For each group,
      # only the last term encountered will be retained after normalization.
      INCOMPATIBLE_FIELDS = {
        review_requests: [:"user-review-requested",  :"review-requested"]
      }

      IS_VALUES = {
        type: %w[issue pr],
        state: %w[open closed unlocked locked],
        merged_state: %w[merged unmerged],
        public: %w[public private],
        queued: %w[queued],
      }

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "comments" => "num_comments",
        "created" => "created_at",
        "updated" => "updated_at",
        "reactions" => "num_reactions",
        "reactions-+1" => "reactions.+1",
        "reactions--1" => "reactions.-1",
        "reactions-smile" => "reactions.smile",
        "reactions-thinking_face" => "reactions.thinking_face",
        "reactions-heart" => "reactions.heart",
        "reactions-tada" => "reactions.tada",
        "reactions-rocket" => "reactions.rocket",
        "reactions-eyes" => "reactions.eyes",
        "interactions" => "num_interactions",
        "relevance" => [],
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[created desc].freeze

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # The largest possible 4-byte Ruby int value (this is half the
      # largest 4-byte Java int value).
      MAX_ISSUE_NUMBER = 1073741824

      CLOSE_ISSUE_REFERENCE_FILTER_TYPES = %w[issue pull-request].freeze

      # Which search qualifiers should trigger a candidate repo search,
      # and which filters we should pass along to that search.
      # These don't have to precisely align, as there may be filters
      # we'd want to pass to CandidatePrivateRepoQuery that don't come from
      # a qualifier.
      # However, these should be edited together any time a new search qualifier
      # is added that would scope one user across many orgs.
      CANDIDATE_REPO_SEARCH_QUALIFIERS = [
        :author, :assignee, :mentions, :involves, :"review-requested",
        :"reviewed-by", :commenter, :team, :"team-review-requested", :"user-review-requested"
      ].freeze
      CANDIDATE_REPO_SEARCH_FILTERS = [
        :author_id, :assignee_id, :mentioned_users, :mentioned_teams, :involves, :requested_reviewer_ids,
        :reviewer_ids, :commenter, :requested_reviewer_team_ids, :requested_reviewer_user_ids
      ].freeze

      class InsecureUserToServerAppQuery < StandardError
        def initialize(*args)
          super("Query must include 'is:issue' or 'is:pull-request'")
        end
      end

      # If exactly one org is specified and exactly one repo is specified without the owner,
      # then search for that repo under the specified org
      def self.normalize_org_and_repo_qualifiers(components)
        return unless components

        repo_q = 0
        index_repo = T.let(-1, Integer)
        org_q = 0
        index_org = T.let(-1, Integer)

        components.each_with_index do |component, index|
          if component.is_a?(Array)
            if component[0] == :repo
              repo_q += 1
              index_repo = index
            elsif component[0] == :org
              org_q += 1
              index_org = index
            end
          end
        end

        return components if repo_q != 1
        return components if org_q != 1

        repo = components[index_repo]

        # If the org is already specified as part of the repo, bail.
        return components if repo[1].include?("/")

        # Specify the repo and org together in the repo qualifier
        org = components.delete_at(index_org)
        repo[1] = org[1] + "/" + repo[1]

        components
      end

      # Internal: Normalize terms in parsed query.
      #
      # Removes duplicate terms preferring the right-most term.
      #
      # ary - Parsed query Array
      #
      # Returns Array.
      def self.normalize(ary)
        components = super(ary)
        components = self.normalize_org_and_repo_qualifiers(components)

        # Convert deprecated is:draft -> draft:true, -is:draft -> draft:false
        components.map! do |component|
          key, value, negated = component
          if key == :is && value == "draft"
            [:draft, negated.nil? ? true : false]
          else
            component
          end
        end

        # Convert all state: and type: terms to is:
        components = components.map do |component|
          if component.is_a?(Array)
            if component[0] == :state || component[0] == :type
              component = component.dup
              component[0] = :is
              component
            else
              component
            end
          else
            component
          end
        end

        # Run sort: values through emoji ascii filter
        components.map! do |component|
          key, value = component
          if key == :sort
            [key, ParsedQuery.asciify_emoji(value)]
          else
            component
          end
        end

        # Use the right most is:
        is = {}
        components = ParsedQuery.filter_terms(components) do |key, value|
          if key == :is
            IS_VALUES.find do |term, values|
              if !is.key?(term) && values.include?(value)
                is[term] = value
                true
              else
                false
              end
            end
          else
            true
          end
        end

        seen_label = T.let(nil, T.nilable(Symbol))
        components = ParsedQuery.filter_terms(components) do |key, value|
          if key == :no && value == "label"
            if seen_label
              false
            else
              seen_label = :no
              true
            end
          elsif key == :label
            seen_label ||= :yes
            seen_label == :yes
          else
            true
          end
        end

        # Remove fields that are marked as mutually incompatible with each other.
        INCOMPATIBLE_FIELDS.each do |label, fields|
          incompatible_seen = Set.new
          components = ParsedQuery.filter_terms(components) do |key, _value|
            if fields.include?(key)
              if incompatible_seen.include?(label)
                next false
              else
                incompatible_seen.add(label)
              end
            end
            true
          end
        end

        # Normalize sort order of default terms
        if components == [[:is, "issue"], [:is, "open"]]
          [[:is, "open"], [:is, "issue"]]
        elsif components == [[:is, "pr"], [:is, "open"]]
          [[:is, "open"], [:is, "pr"]]
        else
          components
        end
      end

      # Enable memex-style 'or' search for issue labels. This value gets passed to `Search::ParsedQuery.new`,
      # `Search::ParsedQuery.parse`, and `Search::Queries.coerce`. This overrides the class method in Search::Query
      def self.enumerable_terms(current_user:)
        [:label]
      end

      # Construct an IssueQuery. The query can be restricted to a single
      # language by providing a :language option. The query can also be
      # restricted to a single repository by providing the :repo_id option.
      #
      # opts - The options Hash.
      #   :language - The language name or Linguist::Language
      #               instance to filter by
      #   :state - The issue state to filter by ('open' or 'closed')
      #   :repo_id  - The Repository ID to filter by
      #   :ngram_title - Whether the search should include partial matches to the title
      #
      def initialize(opts = {}, &block)
        super(opts, &block)

        @index    = opts.fetch(:index, Elastomer::Indexes::Issues.searcher)
        @language = opts.fetch(:language, nil)
        @state    = opts.fetch(:state, nil)
        @repo_id  = opts.fetch(:repo_id, nil)
        @type     = opts.fetch(:type, nil)
        @ngram_title = opts.fetch(:ngram_title, false)
        @memex_project_id = opts.fetch(:memex_project_id, nil)
        @ids_to_exclude = opts.fetch(:ids_to_exclude, nil)
        @force_issue_number_terms = opts.fetch(:force_issue_number_terms, false)
        @allow_insecure_user_to_server_app_query = opts.fetch(:allow_insecure_user_to_server_app_query, true)
        @escape_wildcards = opts.fetch(:escape_wildcards, true)
        # Allows us to use the new syntax from graphql queries while still requiring it to be feature flagged on the front end
      end

      attr_reader :allow_insecure_user_to_server_app_query

      def global?
        repository_filter.global?
      end

      def qualifiers=(value)
        super(value)

        if qualifiers.key?(:type)
          if qualifiers[:type].must_not?
            qualifiers[:type].must_not.each do |value|
              type_values, issue_type_values = value.downcase.split(",").partition { |v|  v == "issue" || v == "pr" }
              qualifiers[:type].must_not = type_values unless type_values.empty?
              qualifiers[:issue_type].must_not(issue_type_values)
            end
          end

          if qualifiers[:type].must?
            qualifiers[:type].must.each do |value|
              type_values, issue_type_values = value.downcase.split(",").partition { |v|  v == "issue" || v == "pr" }
              qualifiers[:type].must = type_values unless type_values.empty?
              issue_type_values.length > 1 ? qualifiers[:issue_type].and_should(issue_type_values) : qualifiers[:issue_type].must(issue_type_values)
            end
          end
        end

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "issue"
              qualifiers[:type].clear.must("issue")
            when "pr", "pull-request"
              qualifiers[:type].clear.must("pull-request")
            when "open"
              qualifiers[:state].clear.must("open")
            when "closed"
              qualifiers[:state].clear.must("closed")
            when "locked"
              qualifiers[:locked].clear.must(true)
            when "unlocked"
              qualifiers[:locked].clear.must(false)
            when "merged"
              qualifiers[:merged_state].clear.must(true)
            when "unmerged"
              qualifiers[:merged_state].clear.must(false)
            when "queued"
              qualifiers[:queued].clear.must(true)
            when "public"
              qualifiers[:public].clear.must(true)
            when "private"
              qualifiers[:public].clear.must(false)
            when "draft"
              if @current_user&.reviewable_state_searching_enabled?
                qualifiers[:"reviewable-state"].clear.must("draft")
              else
                qualifiers[:draft].clear.must(true)
              end
            else
              qualifiers[:label].must(value)
            end
          end
        end

        if qualifiers.key?(:assignee) && qualifiers[:assignee].must? && qualifiers[:assignee].must.include?("*")
          qualifiers[:assignee].clear.must(:exists)
        end

        if qualifiers.key?(:is) && qualifiers[:is].must_not?
          qualifiers[:is].must_not.each do |value|
            case value.downcase
            when "draft"
              if @current_user&.reviewable_state_searching_enabled?
                qualifiers[:"reviewable-state"].clear.must_not("draft")
              else
                qualifiers[:draft].clear.must(false)
              end
            when "queued"
              qualifiers[:queued].clear.must_not(true)
            end
          end
        end

        # Catch `draft:true` and `draft:false` as well
        if qualifiers.key?(:draft) && @current_user&.reviewable_state_searching_enabled?
          if qualifiers[:draft]
            qualifiers[:"reviewable-state"].clear.must("draft")
          else
            qualifiers[:"reviewable-state"].clear.must_not("draft")
          end
        end

        if qualifiers.key?(:no) && qualifiers[:no].must?
          qualifiers[:no].must.each do |value|
            case value.downcase
            when "label", "labels"
              qualifiers[:label].clear.must(:missing)
            when "milestone", "milestones"
              qualifiers[:milestone].clear.must(:missing)
            when "project"
              qualifiers[:project].clear.must(:missing)
            when "assignee"
              qualifiers[:assignee].clear.must(:missing)
            when "review-requested"
              qualifiers[:"review-requested"].clear.must(:missing)
            when "reviewed-by"
              qualifiers[:"reviewed-by"].clear.must(:missing)
            end
          end
        end

        if qualifiers.key?(:review) && qualifiers[:review].must?
          qualifiers[:review].must.each do |value|
            case value.downcase
            when "changes_requested", "changes-requested"
              qualifiers[:review].clear.must("changes_requested")
            when "approved", "approval"
              qualifiers[:review].clear.must("approved")
            when "rejected"
              qualifiers[:review].clear.must("rejected")
            when "none"
              qualifiers[:review].clear.must("none")
            end
          end
        end

        # NOTE: this should run after "type" qualifier is processed.
        # Parses the "linked" qualifiers
        # And adds "type" qualifier if none presents, as "linked" qualifier requires "type" constraints
        #
        parse_value = lambda do |linked_value, is_negative|
          case linked_value
          when "issue"
            is_negative ? qualifiers[:linked].clear.must_not("issue") : qualifiers[:linked].clear.must("issue")
            qualifiers[:type].clear.must("pull-request") unless qualifiers[:type]&.must?
          when "pr", "pull-request"
            is_negative ? qualifiers[:linked].clear.must_not("pull-request") : qualifiers[:linked].clear.must("pull-request")
            qualifiers[:type].clear.must("issue") unless qualifiers[:type]&.must?
          end
        end
        # parse value for regular linked qualifier
        if qualifiers.key?(:linked) && qualifiers[:linked].must?
          qualifiers[:linked].must.each do |value|
            parse_value.call value, false
          end
        end
        # parse value for negating linked qualifier
        if qualifiers.key?(:linked) && qualifiers[:linked].must_not?
          qualifiers[:linked].must_not.each do |value|
            parse_value.call value, true
          end
        end
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
      def source_fields=(value)
        case value
        when Array, String
          @source_fields = Array(value) << "public" << "state" << "updated_at"
          @source_fields.uniq!
        when nil, false
          @source_fields = %w[public state updated_at]
        else
          @source_fields = true
        end
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:language_id, :state]
      end

      # Internal, overriding to increase the timeout for issues and prs
      def default_query_params
        defaults = {
          timeout: "1000ms",
        }
        # Set shard preference if configured. See
        # http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-request-preference.html#search-request-preference
        defaults[:preference] = preference if preference
        defaults[:timeout] = "1500ms" if GitHub.flipper[:issue_and_pulls_search_increase_timeout].enabled?(current_user)
        defaults
      end

      # Internal: Returns the type of search, `issue` or `pull_request`.
      def search_type_for_param
        types = @type

        if types.nil? && qualifiers.key?(:type)
          types = qualifiers[:type].must.nil? ? nil : qualifiers[:type].must.first
        end

        case types
        when "issue", "issues"
          "issue"
        when "pr", "pull-request"
          "pull_request"
        else
          %w[issue pull_request]
        end
      end

      # Internal: Returns the type of search based on the index for hydro instrumentation, `issue` or `pull_request`.
      def search_type_from_index
        search_index = @index.name

        if search_index.start_with?("issues-search")
          %w[issue pull_request]
        elsif search_index.start_with?("issues")
          "issue"
        elsif search_index.start_with?("pull-requests")
          "pull_request"
        end
      end

      # Internal: Returns the correct index for the type of search.
      # Adds postfix to the index name if there is a postfix available
      def index_for_type_param
        types = @type

        if types.nil? && qualifiers.key?(:type)
          types = qualifiers[:type].must.nil? ? nil : qualifiers[:type].must.first
        end

        case types
        when "issue", "issues"
          Elastomer::Indexes::Issues.searcher("issues" + Elastomer.env.postfix.to_s)
        when "pr", "pull-request"
          Elastomer::Indexes::Issues.searcher("pull-requests" + Elastomer.env.postfix.to_s)
        else
          @index # return the default index (issues-search)
        end
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        return @query_params if defined? @query_params

        @query_params = {}
        @index = index_for_type_param

        qualifiers[:type].clear

        @query_params[:routing] = routing if routing.present?
        @query_params
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "title";    @query_fields += title_field
          when "body";     @query_fields << "body"
          when "comments"; @query_fields << "comments.body^0.8"
          end
        end

        @query_fields = title_field.concat(%w[body comments.body^0.8]) if @query_fields.empty?
        @query_fields
      end

      def title_field
        if @ngram_title
          ["title^1.5", "title.ngram^0.5"]
        else
          ["title^1.5"]
        end
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?
        q = { function_score: {
          query: {
            query_string: {
              query: @escape_wildcards ? "#{escaped_query}" : "#{escaped_query_with_search_modifiers}",
              fields: query_fields,
              phrase_slop: 10,
              default_operator: "AND",
              analyzer: "texty_search",
            }
          },
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
            {
              filter: { term: { state: "open" } },
              weight: 2,
            },
          ],
        } }

        # when the user query doesn't specify an `in` qualifier we look for potential commit SHAs and issue numbers
        # if we find them then we add clauses to look for those explicitly
        # if escape_wildcards parameter is false we need to strip the query off wildcards
        # before trying to match it with commit SHA or issue number
        query_without_wildcards = @escape_wildcards ? escaped_query : query.sub(/[\*\?]/, "")

        commit_sha_clauses = search_in.empty? ? commit_sha(query_without_wildcards) : []
        number_clauses = search_in.empty? || @force_issue_number_terms || search_in.include?("number") ? issue_number(query_without_wildcards) : []
        more_clauses = commit_sha_clauses + number_clauses

        if more_clauses.any?
          more_clauses.unshift q
          q = { bool: { should: more_clauses } }
        end

        q
      end

      # Internal: Helper method that will scan the query string looking for
      # Issue numbers. If any are found, then an Array is returned containing
      # term query hashes, one for each Issue number found. If no Issue
      # numbers are found, then an empty Array is returned.
      #
      # query - The full query String (not the phrase).
      #
      # Returns an array of Issue number term queries.
      def issue_number(query)
        issue_number_clauses = query.scan(/(?<=\A|\s)[1-9]\d*(?=\Z|\s)/)

        issue_number_clauses.map! do |number|
          number = number.to_i
          next unless searchable_issue_number?(number)

          { term: { number: {
              value: number,
              boost: 100,
          } } }
        end
        issue_number_clauses.compact!
        issue_number_clauses
      end

      # Determine if the give number is a valid Issue number. It must be
      # greater than 0 and must fit in a 4-byte int value to prevent
      # ElasticSearch (and Java) from exploding with a type error.
      #
      # number - The Integer to validate
      #
      # Returns true or false
      def searchable_issue_number?(number)
        number > 0 && number < MAX_ISSUE_NUMBER
      end

      # Internal: Helper method that will scan the query string looking for
      # commit SHAs. If any are found, then an Array is returned containing
      # prefix query hashes, one for each comit SHA found. If no commit SHAs
      # are found, then an empty Array is returned.
      #
      # query - The full query String (not the phrase).
      #
      # Returns an array of commit SHA prefix queries.
      def commit_sha(query)
        commit_sha_clauses = query.scan(/\b[0-9a-f]{7,40}\b/i)

        commit_sha_clauses.map! do |sha|
          { prefix: { commits: {
            value: sha,
            boost: 100,
          } } }
        end
        commit_sha_clauses.compact!
        commit_sha_clauses
      end

      # Builds a filter that restricts the repositories from which we return search results.
      #
      # The main complexity in this method comes from our handling of user-to-server integration
      # (GitHub App) requests. Those are special because they require us to consider integration
      # installations which might have access to either issues or pull requests but not necessarily
      # both. We don't have an efficient way to perform such complex filtering in the general case,
      # so instead we treat user-to-server requests differently depending on the content of the
      # search query.
      #
      # If the query asks for only issues or only pull requests, then we're in luck: we can resolve
      # that type of query easily and efficiently, so we do.
      #
      # On the other hand, if the query does not ask for just one type, then we raise an
      # InsecureUserToServerAppQuery error.
      #
      # Lastly, if this isn't a user-to-server integration request, then `builder.repository_filter`
      # will perform the correct authorizations and and we can again return results for both issues
      # and pull requests.
      #
      # Returns a Hash representing the repository filter.
      def build_repository_filter(candidate_private_repo_ids: nil)
        if qualifiers[:type].must == ["issue"]
          builder.repository_filter(current_user, @repo_id, "issues", user_session: user_session, ip: remote_ip, candidate_private_repo_ids: candidate_private_repo_ids)
        elsif qualifiers[:type].must == ["pull-request"] || qualifiers[:type].must == ["pr"]
          builder.repository_filter(current_user, @repo_id, "pull_requests", user_session: user_session, ip: remote_ip, candidate_private_repo_ids: candidate_private_repo_ids)
        elsif !current_user&.using_auth_via_granular_actor? || allow_insecure_user_to_server_app_query
          builder.repository_filter(current_user, @repo_id, "issues", user_session: user_session, ip: remote_ip, candidate_private_repo_ids: candidate_private_repo_ids)
        else
          raise InsecureUserToServerAppQuery
        end
      end

      # Checks if we need to run a query to figure out which private repos might have issues/PRs
      # that belong to a given user. We only need to do this search if we're searching across
      # multiple repos and organizations for private repository content that
      # scopes to a specific user.
      # See PRs https://github.com/github/github/pull/191720 and
      # https://github.com/github/github/pull/193853 for more details.
      def use_candidate_repo_search?
        return false if @repo_id.present?
        return false if current_user.blank?
        return false if qualifiers.keys.include?(:user)
        return false if qualifiers.keys.include?(:org)
        return false if qualifiers.keys.include?(:owner)
        return false if qualifiers[:public].must == [true]

        qualifiers.keys.any? { |qualifier| CANDIDATE_REPO_SEARCH_QUALIFIERS.include?(qualifier) }
      end

      # Fetches the ids of private repositories matching the filters passed in.
      # Returns an array of repository ids. These are typically checked for access
      # as part of `repository_filter`.
      def fetch_candidate_private_repo_ids(filters:)
        return @candidate_private_repo_ids if defined?(@candidate_private_repo_ids)

        @index = index_for_type_param
        query = CandidatePrivateRepoQuery.new(filters, index: @index)

        response = query.execute
        repo_id_buckets = response.aggregations.dig("repo_ids", "buckets")
        if repo_id_buckets&.any?
          @candidate_private_repo_ids = repo_id_buckets.map { |h| h["key"] }
        else
          @candidate_private_repo_ids = nil
        end
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str =~ /^title/ }
          fields[:title] = { number_of_fragments: 0 }  # force the whole title to be included in the fragment
        end

        if query_fields.any? { |str| str =~ /^body/ }
          fields[:body] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        end

        if query_fields.any? { |str| str =~ /^comments/ }
          fields["comments.body"] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
          if GitHub.flipper[:unified_highlighter_for_issue_comments].enabled?(current_user)
            fields["comments.body"] = fields["comments.body"].merge type: "unified"
          end
        end

        unless fields.empty?
          highlight = { encoder: :html, fields: fields, type: "plain" }
          highlight[:max_analyzed_offset] = 1000000 if index.index_running_version_8_plus?
          highlight
        end
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        ary = build_sort_section(sort, "_score", SORT_MAPPINGS)
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "created_at" == key || "updated_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end
        end

        ary
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      def build_query_filter
        filter = ::Search::Filters::BoolFilter.new(filter_hash, aggregations)
        query_filter = filter.build

        if query_filter[:bool][:should]
          query_filter[:bool][:minimum_should_match] = 1
        end

        query_filter
      end

      # Internal: We need to use the same filters for the query and for the
      # aggregations with the exception of the language query. Since we are aggregationing
      # on language, applying a language filter would be most unhelpful.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        # override the language if created with a language option
        unless @language.nil?
          qualifiers[:lang].clear
          qualifiers[:language].clear
          qualifiers[:language].must @language
        end

        # override the state if created with a state option
        unless @state.nil?
          qualifiers[:state].clear
          qualifiers[:state].must @state
        end

        filters = {}

        filters[:state]  = builder.term_filter(:state)
        filters[:status] = builder.term_filter(:status)
        filters[:merged] = builder.term_filter(:merged, :merged_state)
        filters[:draft]  = builder.term_filter(:draft) do |value|
          case value
          when /true/i; true
          when true; true
          else false
          end
        end
        filters[:public] = builder.term_filter(:public)
        filters[:locked] = builder.term_filter(:locked)
        filters[:labels] = builder.label_filter(
                             :labels, :label,
                             execution: :and,
                             missing: :none)
        filters[:queued] = builder.term_filter(:queued)

        filters[:reviewable_state] = builder.term_filter(:reviewable_state, :"reviewable-state")

        filters[:archived] = builder.term_filter(:archived, singular: true) do |value|
          case value
          when /true/i; true
          when true; true
          else false
          end
        end

        filters[:has_closing_reference] = builder.term_filter(:has_closing_reference, :linked, singular: true) do |value|
          case value
          when /issue/i; true
          when /pull-request/i; true
          else nil
          end
        end

        exclude_private_profiles = @repo_id.nil?

        filters[:head_ref] = builder.prefix_filter(:head_ref, :head) { |ref| ref.downcase }
        filters[:base_ref] = builder.prefix_filter(:base_ref, :base) { |ref| ref.downcase }

        filters[:author_id]    = builder.user_filter(:author_id, :author, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:assignee_id]  = builder.user_filter(:assignee_id, :assignee, missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:requested_reviewer_ids] = builder.review_request_filter(:requested_reviewer_ids, :"review-requested", missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:requested_reviewer_team_ids] = builder.team_filter(current_user, :requested_reviewer_team_ids, :"team-review-requested")
        filters[:requested_reviewer_user_ids] = builder.user_review_request_filter(:requested_reviewer_user_ids, :"user-review-requested", current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:reviewer_ids] = builder.user_filter(:reviewer_ids, :"reviewed-by", missing: :none, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:review_status] = builder.term_filter(:review_status, :review)
        filters[:commenter] = builder.user_filter("comments.author_id", :commenter, current_user: current_user, exclude_private_profiles: exclude_private_profiles)

        filters[:mentioned_users] = builder.user_filter(:mentioned_user_ids, :mentions, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:mentioned_teams] = builder.team_filter(current_user, :mentioned_team_ids, :team)

        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)
        filters[:merged_at]  = builder.date_range_filter(:merged_at,  :merged)
        filters[:closed_at]  = builder.date_range_filter(:closed_at,  :closed)

        filters[:num_comments]  = builder.range_filter(:num_comments, :comments)
        filters[:num_reactions] =
            builder.range_filter(:num_reactions, :reactions)
        filters[:num_interactions] =
            builder.range_filter(:num_interactions, :interactions)

        filters[:milestone] = builder.milestone_filter(:milestone)
        filters[:project_ids] = builder.issue_project_and_memex_project_filter(:project, current_user: current_user)
        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language, :lang) if @repo_id.nil?
        filters[:state_reason] = builder.state_reason_filter(:reason)
        filters[:issue_type_name] = builder.issue_type_name_filter
        if @memex_project_id && @repo_id
          filters[:issue_id] = builder.memex_project_exclusion_filter(
            memex_project_id: @memex_project_id,
            repository_id: @repo_id
          )
        end

        if @ids_to_exclude.present?
          filters[:issue_id] = builder.ids_to_exclude_filter(
            ids: @ids_to_exclude,
          )
        end

        if current_installation ||= current_user.try(:installation)
          permissions = current_installation.permissions

          issue_permission = permissions["issues"]
          pr_permission = permissions["pull_requests"]

          case
          when issue_permission && pr_permission
            # pass through existing type qualifier
          when issue_permission
            qualifiers[:is].clear; qualifiers[:type].clear
            qualifiers[:is].must("issue"); qualifiers[:type].must("issue")
          when pr_permission
            qualifiers[:is].clear; qualifiers[:type].clear
            qualifiers[:is].must("pr"); qualifiers[:type].must("pr")
          else
            # TODO: Integration without either permissions are not allowed to query
          end
        end

        filters[:involves] = builder.involves_filter(
          [:author_id, :assignee_id, :mentioned_user_ids, :requested_reviewer_ids, :reviewer_ids, "comments.author_id"],
          :involves,
          current_user: current_user,
          exclude_private_profiles: exclude_private_profiles
        )

        # Check if we should perform a separate query to find private repos that match the query
        if use_candidate_repo_search?
          candidate_repo_filters = filters.slice(*CANDIDATE_REPO_SEARCH_FILTERS)
          candidate_private_repo_ids = fetch_candidate_private_repo_ids(filters: candidate_repo_filters)
        else
          candidate_private_repo_ids = nil
        end

        filters[:repo_id] = build_repository_filter(candidate_private_repo_ids: candidate_private_repo_ids)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Take the repository IDs and generate a routing String. This
      # routing string is used to limit our search to the specific set of
      # shards where the issues / pull requests are stored.
      #
      # Returns a routing String.
      def routing
        return @routing if defined? @routing
        @routing = @repo_id

        if @repo_id.nil? && !repository_filter.global?
          ids = repository_filter.accessible_repository_ids
          @routing = ids.to_a.join(",") unless ids.length > 200
        end

        @routing
      end

      def repository_filter
        filter_hash[:repo_id]
      end

      def valid_query?
        return false unless super

        if global? && escaped_query.empty?
          filters = filter_hash.keys - [:repo_id]
          if filters.empty?
            @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
            return false
          end
        end

        if qualifiers.key?(:linked)
          if !(CLOSE_ISSUE_REFERENCE_FILTER_TYPES & qualifiers[:linked].all).any?
            @invalid_reason = "Unsupported type for the closing reference filter."
            e = QueryRejectionError.new(@invalid_reason)
            data_hash = { "gh.search.error.linked_filter" => qualifiers[:linked].all.first }
            log_query(at: "execute", data_hash: data_hash, error: e)
            return false
          end

          if qualifiers.key?(:type) && qualifiers[:type].must? && (qualifiers[:linked].all == qualifiers[:type].must)
            @invalid_reason = "Cannot search for the closing reference for the same type as the type filter."
            return false
          end
        end

        true
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

      # Internal: Take the array of issue results and remove those for which
      # the issue no longer exists or has been flagged as spammy. We will
      # only perform this pruning in test and production; development mode is
      # for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        issue_ids = []
        pull_request_ids = []
        error_reported = false

        results.each do |h|
          doc_id = h["_id"].to_i
          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues"; issue_ids << doc_id
          when "pull-requests"; pull_request_ids << doc_id
          end
        end

        issues = Instrumentation.track_time("search.dist.time", tags: ["index:#{index.name}", "action:prune_results_issues_lookup"]) do
          Issue.includes(:user, :repository).where(id: issue_ids).index_by(&:id)
        end

        pull_requests = PullRequest.includes(:user, :issue, :repository).where(id: pull_request_ids).index_by(&:id)

        results.delete_if do |h|
          doc_id = h["_id"].to_i

          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues"; prune_issue(h, issues[doc_id])
          when "pull-requests"; prune_pull_request(h, pull_requests[doc_id])
          end
        end
      end

      # Internal: Determine if the search result doc should be pruned from the
      # result set based on the existence or spamminess of the corresponding
      # issue, and the enabled/disabled status of the issue's parent repository.
      #
      # doc   - The document Hash from ElasticSearch
      # issue - The corresponding Issue or nil
      #
      # Returns true or false.
      def prune_issue(doc, issue)
        @issue_repairs ||= {}
        pub = is_public doc

        if issue.nil? || !issue.is_searchable?
          unless Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("issue", doc["_id"], doc["_routing"])
          end
          true

        # if the repo has no issues, or isn't searchable (including marked spammy) then remove from index
        elsif !issue.parent_repo_is_searchable?
          repo_id = issue.repository_id
          unless @issue_repairs[repo_id]
            RemoveFromSearchIndexJob.perform_later("bulk_issues", repo_id)
            @issue_repairs[repo_id] = true
          end
          true

        # if the public visibility of the repository has changed
        elsif !pub.nil? && issue.repository.public != pub
          repo_id = issue.repository_id
          unless @issue_repairs[repo_id]
            Search.add_to_search_index("bulk_issues", repo_id, "purge" => true)
            @issue_repairs[repo_id] = true
          end
          true

        else
          if doc.dig("_source", "updated_at") && DateTime.parse(doc["_source"]["updated_at"]) != issue.updated_at
            GitHub.dogstats.increment("issue.repair_on_read")
            issue.synchronize_search_index
          end

          doc["_model"] = issue
          !security_validation doc
        end
      end

      # Internal: Determine if the serach result doc should be pruned from the
      # result set based on the existence or spamminess of the corresponding
      # pull request.
      #
      # doc          - The document Hash from ElasticSearch
      # pull_request - The corresponding PullRequest or nil
      #
      # Returns true or false.
      def prune_pull_request(doc, pull_request)
        @pull_request_repairs ||= {}
        pub = is_public doc

        # The read_attribute here is used for speed to bypass the potentially slow #spammy? method.
        Platform::LoaderTracker.ignore_association_loads do # rubocop:disable GitHub/IgnoreAssociationLoads
          if pull_request.nil? || !pull_request.is_searchable?
            unless Rails.env.development?
              RemoveFromSearchIndexJob.perform_later("pull_request", doc["_id"], doc["_routing"])
            end
            true

          # if the public visibility of the repository has changed
          elsif !pub.nil? && pull_request.repository.public != pub
            repo_id = pull_request.repository_id
            unless @pull_request_repairs[repo_id]
              Search.add_to_search_index("bulk_pull_requests", repo_id, "purge" => true)
              @pull_request_repairs[repo_id] = true
            end
            true

          else
            # if state of PR doesn't seem to match keep match but reindex
            if pull_request_state_mismatch(doc, pull_request)
              GitHub.dogstats.increment("pull_request.repair_on_read")
              pull_request.synchronize_search_index
            end

            doc["_model"] = pull_request.issue
            !security_validation doc
          end
        end
      end

      def pull_request_state_mismatch(doc, pull_request)
        return false unless issue_state = doc.dig("_source", "state")

        state_matches =
          if issue_state == "closed"
            pull_request.closed? || pull_request.merged?
          else
            issue_state == pull_request.state.to_s
          end

        !state_matches
      end

      # Internal: validate that the user is allowed to see the given search
      # result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        repo = doc["_model"].repository

        return true if repository_filter.accessible_repository?(repo)

        GitHub.dogstats.increment("search.query.errors.security", { tags: ["index:" + index.name.to_s] })
        false
      end

      # Internal: Returns `true`, `false`, or `nil`. nil will only be returned
      # if a public attribute is not included as part of the search result
      # doc.
      #
      # doc - The document Hash returned from the search index.
      #
      def is_public(doc)
        if source = doc["_source"]
          source["public"]
        end
      end

      private

      # This method escapes query the same way escaped_query method does but leaves search special characters unescaped
      def escaped_query_with_search_modifiers
        result = query.tr("<>", " ")
        (query =~ /^["\s\\]*$/ ? "" : result)
      end
    end  # IssueQuery
  end  # Queries
end  # Search
