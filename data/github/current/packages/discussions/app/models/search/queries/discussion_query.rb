# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class DiscussionQuery < ::Search::Query
      # The set of fields that can be queried when performing a discussion search
      sig { override.returns(T::Array[Symbol]) }
      def self.field_list
        [
          :in, :sort, :author, :commenter, :involves, :user, :org, :owner, :repo, :created,
          :reason, :closed, :updated, :comments, :is, :category, :"answered-by", :label, :no
        ].freeze
      end

      # A set of terms that have mutually exclusive values.
      sig { override.returns(T::Array[Symbol]) }
      def self.unique_field_list
        [
          :author, :sort, :reason, :"answered-by"
        ].freeze
      end

      IS_VALUES = {
        public: %w[public private],
        state: %w[open closed],
        answered: %w[answered unanswered],
        locked: %w[locked unlocked],
        type: %w[discussion]
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[latest desc].freeze

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # The largest possible 4-byte Ruby int value (this is half the
      # largest 4-byte Java int value).
      MAX_DISCUSSION_NUMBER = 1073741824

      sig { override.params(array: T::Array[Symbol]).returns(T::Array[Symbol]) }
      def self.normalize(array)
        components = super(array)

        # Use the rightmost 'is':
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

        # no:labels and label:... terms are mutually exclusive. The rightmost
        # occurrence of either takes precedence.
        seen_label = T.let(nil, T.nilable(Symbol))
        components = ParsedQuery.filter_terms(components) do |key, value|
          if key == :no && value.match?(/\Alabels?\z/i)
            if seen_label
              false
            else
              seen_label = :exclusion
              true
            end
          elsif key == :label
            if seen_label
              seen_label == :inclusion
            else
              seen_label = :inclusion
              true
            end
          else
            true
          end
        end

        components
      end

      # Construct a DiscussionQuery. The query can be restricted to a single
      # repository by providing the :repo_id option.
      #
      # opts - The options Hash.
      #   :repo_id  - The Repository ID to filter by
      sig { params(opts: (T::Hash[Symbol, T.untyped]), block: T.nilable(T.proc.void)).void }
      def initialize(opts = {}, &block)
        super(opts, &block)

        @index = Elastomer::Indexes::Discussions.new
        @context_repo_id = opts[:repo_id]
        @available_category_ids = opts[:category_ids]
        @ngram_title = opts[:ngram_title]
        @top_filter_only_unlocked = opts[:top_filter_only_unlocked]
        @force_discussion_number_terms = opts.fetch(:force_discussion_number_terms, false)
        @escape_wildcards = opts.fetch(:escape_wildcards, true)
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      sig { override.returns(T::Array[Symbol]) }
      def qualifier_fields
        self.class.field_list
      end

      sig { override.params(value: T.nilable(T::Hash[Symbol, T.untyped])).void }
      def qualifiers=(value)
        super(value)

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "locked"
              qualifiers[:locked].clear.must(true)
            when "unlocked"
              qualifiers[:locked].clear.must(false)
            when "public"
              qualifiers[:public].clear.must(true)
            when "private"
              qualifiers[:public].clear.must(false)
            when "answered"
              qualifiers[:answered].clear.must(true)
            when "unanswered"
              qualifiers[:unanswered].clear.must(true)
            when "open"
              qualifiers[:state].clear.must("open")
            when "closed"
              qualifiers[:state].clear.must("closed")
            end
          end
        end

        # Handle negated must_not answered and unanswered qualifiers
        if qualifiers.key?(:is) && !qualifiers[:is].must?
          qualifiers[:is].must_not.each do |value|
            case value.downcase
            when "answered"
              qualifiers[:answered].clear.must_not(true)
            when "unanswered"
              qualifiers[:unanswered].clear.must_not(true)
            end
          end
        end

        if qualifiers.key?(:no) && qualifiers[:no].must?
          qualifiers[:no].must.each do |value|
            if value.match?(/\Alabels?\z/i)
              qualifiers[:label].clear.must(:missing)
            end
          end
        end
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      #
      sig { returns(T::Hash[String, String]) }
      def create_sort_mappings
        {
          "updated" => "updated_at",
          "latest" => "bumped_at",
          "top" =>  "total_upvotes",
          "comments" => "num_comments",
          "date_created" => "created_at",
          "reactions" => "num_reactions",
          "reactions-+1" => "reactions.+1",
          "reactions--1" => "reactions.-1",
          "reactions-smile" => "reactions.smile",
          "reactions-thinking_face" => "reactions.thinking_face",
          "reactions-heart" => "reactions.heart",
          "reactions-tada" => "reactions.tada",
          "interactions" => "num_interactions",
        }
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
      sig { params(value: T.nilable(T.any(T::Array[String], String, T::Boolean))).void }
      def source_fields=(value)
        case value
        when Array, String
          @source_fields = Array(value) << "public"
          @source_fields.uniq!
        when nil, false
          @source_fields = %w[public]
        else
          @source_fields = true
        end
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def query_params
        return @query_params if defined? @query_params
        @query_params = {}
        @query_params[:routing] = routing if routing.present?
        @query_params
      end

      # Internal: Returns the Array of field names that will be queried.
      sig { returns T::Array[String] }
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

      sig { returns(T::Array[String]) }
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
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def query_doc
        return if escaped_query.empty?

        q = { function_score: {
          query: { query_string: {
            query: escaped_query,
            fields: query_fields,
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          } },
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
          ],
        } }

        # when the user query doesn't specify an `in` qualifier we look for discussion numbers
        # if we find them then we add clauses to look for those explicitly
        # if escape_wildcards parameter is false we need to strip the query off wildcards
        # before trying to match it with discussion number
        query_without_wildcards = @escape_wildcards ? escaped_query : query.gsub(/[\*\?]/, "")
        more_clauses = search_in.empty? || @force_discussion_number_terms ? discussion_number(query_without_wildcards) : []

        if more_clauses.any?
          more_clauses.unshift q
          q = { bool: { should: more_clauses } }
        end


        q
      end

      # Internal: Helper method that will scan the query string looking for
      # Discussion numbers. If any are found, then an Array is returned containing
      # term query hashes, one for each Discussion number found. If no Discussion
      # numbers are found, then an empty Array is returned.
      #
      # query - The full query String (not the phrase).
      #
      # Returns an array of Discussion number term queries.
      sig { params(query: String).returns(T::Array[T.any(T::Hash[Symbol, T.untyped], String)]) }
      def discussion_number(query)
        discussion_number_clauses = T.cast(query.scan(/(?<=\A|\s)[1-9]\d*(?=\Z|\s)/), T::Array[String])

        discussion_number_clauses.map! do |number_string|
          number = number_string.to_i
          next unless searchable_discussion_number?(number)

          { term: { number: {
              value: number,
              boost: 100,
          } } }
        end
        discussion_number_clauses.compact!
        discussion_number_clauses
      end

      # Determine if the give number is a valid Discussion number. It must be
      # greater than 0 and must fit in a 4-byte int value to prevent
      # ElasticSearch (and Java) from exploding with a type error.
      #
      # number - The Integer to validate
      #
      # Returns true or false
      sig { params(number: Integer).returns(T::Boolean) }
      def searchable_discussion_number?(number)
        number > 0 && number < MAX_DISCUSSION_NUMBER
      end

      # Internal: Returns the highlight Hash.
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
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
        end

        unless fields.empty?
          { encoder: :html, fields: fields, type: "plain" }
        end
      end

      # Internal: Returns the sorting options Array.
      sig { returns(T.nilable(T::Array[T.untyped])) }
      def build_sort
        return if sort.blank?
        ary = build_sort_section(sort, "_score", create_sort_mappings)
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "updated_at" == key || "bumped_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end
        end

        ary
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      sig { returns(T::Array[String]) }
      def default_sort
        DEFAULT_SORT
      end

      # Internal: We need to use the same filters for the query and for the
      # aggregations.
      #
      # Returns the Hash of filter hashes.
      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def filter_hash
        return @filter_hash if defined? @filter_hash

        qualifiers[:locked].must(false) if top_filter_only_unlocked?

        exclude_private_profiles = @context_repo_id.nil?
        filters = {}

        filters[:public] = builder.term_filter(:public)
        filters[:answered] = builder.term_filter(:answered)
        filters[:unanswered] = builder.term_filter(:unanswered)
        filters[:locked] = builder.term_filter(:locked)
        filters[:author_id] = builder.user_filter(:user_id, :author, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:commenter] = builder.user_filter("comments.user_id", :commenter, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:answered_by_id] = builder.user_filter(:answered_by_id, :"answered-by",
          missing: :none,
          exclude_private_profiles: exclude_private_profiles
        )
        filters[:author_id] = builder.user_filter(:user_id, :author, current_user: current_user, exclude_private_profiles: exclude_private_profiles)
        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)
        filters[:closed_at] = builder.date_range_filter(:closed_at, :closed)
        filters[:state] = builder.term_filter(:state)
        filters[:state_reason] = builder.term_filter(:state_reason, :reason)
        filters[:num_comments] = builder.range_filter(:num_comments, :comments)
        filters[:category_id] = builder.discussions_category_filter(
          :category_id,
          :category,
          repository_ids: repo_ids,
        )

        filters[:labels] = builder.term_filter(
          :labels, :label,
          execution: :and,
          missing: :none,
        ) { |label| label.downcase }

        resource = "discussions"
        filters[:repository_id] = builder.repository_filter(
          current_user,
          @context_repo_id,
          resource,
          user_session: user_session,
          ip: remote_ip,
          field: :repository_id,
        )

        filters[:involves] = builder.involves_filter([:user_id, "comments.user_id"], :involves, current_user: current_user, exclude_private_profiles: exclude_private_profiles)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Take the repository IDs and generate a routing String. This
      # routing string is used to limit our search to the specific set of
      # shards where the discussions are stored.
      #
      # Returns a routing String.
      sig { returns(T.nilable(T.any(String, Integer))) }
      def routing
        return @routing if defined? @routing
        @routing = @context_repo_id

        if @context_repo_id.nil? && !repository_filter.global?
          ids = repository_filter.accessible_repository_ids
          @routing = ids.to_a.join(",") unless ids.length > 200
        end

        @routing
      end

      sig { returns(T::Boolean) }
      def global?
        repository_filter.global?
      end

      sig { returns(Search::Filters::RepositoryFilter) }
      def repository_filter
        filter_hash[:repository_id]
      end

      sig { returns(T::Boolean) }
      def valid_query?
        return false unless super

        if global? && escaped_query.empty?
          filters = filter_hash.keys - [:repository_id]
          if filters.empty?
            @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
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
      sig { override.params(results: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of discussion results and remove those for which
      # the discussion no longer exists or has been flagged as spammy. We will
      # only perform this pruning in test and production; development mode is
      # for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      sig { override.params(results: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
      def prune_results(results)
        GitHub.tracer.in_span("Search::Query::DiscussionQuery#prune_results", kind: :internal) do
          discussion_ids = results.map { |h| h["_id"] }
          discussions = GitHub.dogstats.distribution_time("search", tags: ["index:#{index.name}", "action:prune_results_discussions_lookup"]) do
            Discussion.includes(:user, :repository).where(id: discussion_ids).index_by(&:id)
          end

          results.delete_if do |h|
            doc_id = h["_id"].to_i
            prune_discussion(h, discussions[doc_id])
          end
        end
      end

      # Internal: Determine if the search result doc should be pruned from the
      # result set based on the existence or spamminess of the corresponding
      # discussion, and the enabled/disabled status of the discussion's parent repository.
      #
      # doc   - The document Hash from ElasticSearch
      # discussion - The corresponding Discussion or nil
      #
      # Returns true or false.
      sig { params(doc: T::Hash[T.any(Symbol, String), T.untyped], discussion: T.nilable(Discussion)).returns(T::Boolean) }
      def prune_discussion(doc, discussion)
        @discussion_repairs ||= {}
        pub = is_public doc

        # The read_attribute here is used for speed to bypass the potentially slow #spammy? method.
        if discussion.nil? || discussion.user.nil? || T.must(discussion.user).read_attribute(:spammy)
          unless Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("discussion", doc["_id"], doc["_routing"])
          end
          true

        # if the repo has no discussions, or isn't searchable (including marked spammy) then remove from index
        elsif !discussion.parent_repo_is_searchable?
          repo_id = discussion.repository_id
          unless @discussion_repairs[repo_id]
            RemoveFromSearchIndexJob.perform_later("bulk_discussions", repo_id)
            @discussion_repairs[repo_id] = true
          end
          true

        # if the discussios category isn't available them remove from index
        elsif @available_category_ids.present? && @available_category_ids.exclude?(discussion.category_id)
          RemoveFromSearchIndexJob.perform_later("discussion", doc["_id"], doc["_routing"])
          true

        # if the public visibility of the repository has changed, or the user
        # does not have access.
        else
          if !pub.nil? && discussion.repository&.public != pub
            repo_id = discussion.repository_id
            unless @discussion_repairs[repo_id]
              Search.add_to_search_index("bulk_discussions", repo_id, "purge" => true)
              @discussion_repairs[repo_id] = true
            end

            return true if qualifiers.has_key?(:public)
          end

          doc["_model"] = discussion
          !security_validation doc

        end
      end

      # Internal: validate that the user is allowed to see the given search
      # result document.
      #
      # doc - The search result Hash
      #
      # Returns boolean indicating visibility.
      sig { params(doc: T::Hash[T.any(Symbol, String), T.untyped]).returns(T::Boolean) }
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
      sig { params(doc: T::Hash[T.any(Symbol, String), T.untyped]).returns(T.any(T::Boolean, NilClass)) }
      def is_public(doc)
        if source = doc["_source"]
          source["public"]
        end
      end

      private

      sig { returns(T::Array[Integer]) }
      def repo_ids
        return @repo_ids if @repo_ids

        @repo_ids =
          if @context_repo_id
            [@context_repo_id]
          elsif qualifiers[:repo]&.must?
            Repository.with_names_with_owners(qualifiers[:repo].must.map { |nwo| nwo.downcase }).pluck(:id)
          else
            []
          end
      end

      # Private: Should we only filter unlocked discussions for this search?
      #          This is done if we're soring by `top`, and the `top_filter_only_unlocked` option is true.
      sig { returns(T::Boolean) }
      def top_filter_only_unlocked?
        return false unless @top_filter_only_unlocked
        sort&.first == "top"
      end
    end
  end
end
