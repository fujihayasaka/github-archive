# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Search
  module Queries

    class RepoQuery < ::Search::Query

      PROPERTIES_PREFIXED_REGEX_TEXT = "(properties|props|p)\\.#{CustomProperties::Public::NAME_VALID_CHARS_REGEX_TEXT}"
      PROPERTIES_PREFIXED_REGEX = /#{PROPERTIES_PREFIXED_REGEX_TEXT}/

      # The set of fields that can be queried when performing a repository search
      def self.field_list
        [:in, :sort, :size, :forks, :fork, :pushed, :user, :org, :owner, :repo, :lang, :language,
                :license, :created, :followers, :stars, :mirror, :template, :is, :topic, :topics,
                :archived, :"help-wanted-issues", :"good-first-issues", :has, :visibility,
                :sponsorable, :no,
                PROPERTIES_PREFIXED_REGEX_TEXT].freeze
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "stars"   => "followers",
        "forks"   => "forks",
        "updated" => "pushed_at",
        "help-wanted-issues" => "help_wanted_issues_count",
        "name" => "name_sort",
        "topics" => "num_topics",
        "size" => "size",
        "language" => "language",
        "license" => "license_id",
      }.freeze

      IS_VALUES = {
        public: %w[public private internal],
        sponsorable: %w[sponsorable],
      }.freeze

      HAS_VALUES = {
        "funding-file" => %w[has_funding_file],
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[stars desc].freeze

      # Tables required to prune_results without triggering N+1s
      DEFAULT_PRELOAD_TABLES = %i(owner network network_privilege).freeze

      # Construct a RepoQuery. The query can be restricted to a single
      # language by providing a :language option.
      #
      # opts - The options Hash.
      #   :language - The language name or Linguist::Language instance to filter by
      #   :limit_to_repo_ids - An array of repository IDs to limit the search to.
      #                        When this is present, other qualifiers like org: or owner: may be ignored.
      #   :cap_filter - The object to run authorize permission checks
      #   :skip_permission_check - Allow to view all repos without checking user permissions.
      #                            This can leak repositories the user is not allowed to see,
      #                            so the caller MUST ensure permissions are enforced before or after.
      #
      def initialize(opts = {}, &block)
        # @sort = %w[stars desc]   # default sort ordering by stars
        super(opts, &block)

        self.star_search  = opts.fetch(:star_search, false)
        self.star_user    = opts.fetch(:star_user, self.current_user)

        @index = Elastomer::Indexes::Repos.new
        @language = opts.fetch(:language, nil)
        @include_forks = opts.fetch(:include_forks, false)
        @include_topics = opts.fetch(:include_topics, false)
        @binary_fork_filter = opts.fetch(:binary_fork_filter, false)
        @preload_tables = opts.fetch(:preload_tables, DEFAULT_PRELOAD_TABLES)
        @limit_to_repo_ids = opts.fetch(:limit_to_repo_ids, nil)
        @cap_filter = opts.fetch(:cap_filter, nil)
        @skip_permission_check = opts.fetch(:skip_permission_check, false)
        @experiment_owner_id_and_repo_id = GitHub.flipper[:repo_query_owner_id_and_repo_id_optimization_forced].enabled?
        @experiment_unbounded = opts.fetch(:experiment_unbounded, false)
      end

      attr_accessor :cap_filter

      # Restrict searches to the current user's constellation of stars + Bool predicate
      attr_accessor :star_search
      def star_search?
        !!star_search
      end

      # The user who's stars would be searched if `star_search` is true
      attr_accessor :star_user

      def global?
        return false if filter_hash[:owner_id]
        filter_hash[:repo_id].global?
      end

      def warn_limited_results?
        return false unless filter_hash[:repo_id].respond_to?(:hit_max_repo_filter_limit?)
        filter_hash[:repo_id].hit_max_repo_filter_limit?
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
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

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      def query=(value)
        super(value)

        parse_exact_match_query
      end

      def qualifiers=(value)
        super(value)

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:visibility].clear
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "private"
              qualifiers[:visibility].must("private")
            when "public"
              qualifiers[:visibility].must("public")
            when "internal"
              qualifiers[:visibility].must("internal")
            when "sponsorable"
              qualifiers[:sponsorable].clear.must(true)
            end
          end
        end

        if qualifiers.key?(:has) && qualifiers[:has].must?
          qualifiers[:has].must.each do |value|
            case value.downcase
            when "funding-file"
              qualifiers[:has_funding_file].clear.must(true)
            end
          end
        end

        parse_exact_match_query
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:language_id]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "repository" }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "name";        @query_fields.concat(%w[name^2 name.camel name.ngram^0.8 name_with_owner])
          when "description"; @query_fields << "description"
          when "readme";      @query_fields << "readme"
          when "topics";      @query_fields << "applied_topics"
          end
        end

        if @query_fields.empty?
          @query_fields = %w[name^1.2 name.camel name.ngram^0.8 description applied_topics]
          @query_fields << "name_with_owner" if escaped_query.index("/")
        end
        @query_fields
      end

      # Enable comma syntax with 'or' logic for `visibility:` and `props.*:` terms
      def self.enumerable_terms(current_user:)
        [:visibility, :language, :lang, :license, :topic, PROPERTIES_PREFIXED_REGEX_TEXT]
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        query_hash = if escaped_query.present?
          {
            function_score: {
              query: {
                query_string: {
                  query:            escaped_query,
                  fields:           query_fields,
                  default_operator: "AND",
                },
              },
              score_mode: "multiply",
              functions: [{ field_value_factor: { field: "rank", missing: 1 } }],
            },
          }
        end

        if use_exact_match_clause? && query_hash.present?
          boost_name_with_owner = { filter: { bool: { must: [
            { term: { "owner_id": @query_owner.id } },
            { match: { "name": @query_repo_name } },
          ] } }, weight: 20 }

          query_hash[:function_score][:functions] << boost_name_with_owner
        end

        if filtering_by_topic? || filtering_out_topic? # Searching explicitly for or without an applied topic
          query_with_topics(query_hash)
        else
          query_hash
        end
      end

      def use_exact_match_clause?
        @query_owner && @query_repo_name
      end

      def parse_exact_match_query
        # Extract parts from "owner/repo" format
        owner_part, repo_part, remainder = query.split("/", 3)

        # Same if no "/" but using the org: qualifier
        if repo_part.blank? && qualifiers
          org_names = qualifiers[:org].must || []
          org_names.concat qualifiers[:user].must if qualifiers[:user].must
          org_names.concat qualifiers[:owner].must if qualifiers[:owner].must
          if org_names&.size == 1
            owner_part, repo_part, remainder = [org_names.first, query, nil]
          end
        end

        valid_name = repo_part.present? && !repo_part.include?(" ")
        if owner_part.present? && valid_name && remainder.blank?
          owner = User.find_by(login: owner_part, spammy: false)
          if owner.present?
            @query_owner = owner
            @query_repo_name = repo_part
          end
        end
      end

      # Internal, overriding to increase the timeout so queries return accurate total counts
      def default_query_params
        if current_user.present?
          defaults = {
            timeout: "1000ms",
          }
          defaults[:preference] = preference if preference
          defaults
        else
          super
        end
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str.starts_with?("name") }
          fields[:name] = { number_of_fragments: 0 }
          fields["name.camel"] = { number_of_fragments: 0 }
          fields["name.ngram"] = { number_of_fragments: 0 }
        end

        if query_fields.any? { |str| str.starts_with?("name_with_owner") }
          fields[:name_with_owner] = { number_of_fragments: 0 }
        end

        if query_fields.any? { |str| str.starts_with?("description") }
          fields[:description] = {
            number_of_fragments: 1,
            fragment_size: 256,
          }
        end

        unless fields.empty?
          { encoder: :html, fields: fields, type: "plain" }
        end
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
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

        # the fork filter is a special case
        # by default we will not show forks in the search results - you have
        # to explicitly add "fork:true" or "fork:only" to the search
        qualifiers[:fork].must(false) unless qualifiers[:fork].must? || @include_forks

        filters = {}

        filters[:public] = builder.term_filter(:public)

        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language, :lang)

        filters[:license_id] = builder.license_filter(:license_id, :license)

        filters[:visibility] = builder.enumerated_term_filter(:visibility)
        filters[:visibility].map_bool_collection { |v| v.downcase }

        if can_use_properties?
          filters[:custom_property_values] = builder.custom_properties_filter(
            "custom_property_values.keyword",
            PROPERTIES_PREFIXED_REGEX,
          )

          filters[:no] = builder.repos_no_filter("custom_property_values.keyword", PROPERTIES_PREFIXED_REGEX)
        end

        filters[:fork] = builder.term_filter(:fork, singular: true) do |value|
          case value
          when /\Atrue\z/i; @binary_fork_filter ? true : nil
          when /\Aonly\z/i; true
          else false
          end
        end

        filters[:mirror] = builder.term_filter(:mirror, singular: true) do |value|
          case value
          when /\Atrue\z/i; true
          when true; true
          else false
          end
        end

        filters[:template] = builder.term_filter(:template, singular: true) do |value|
          case value
          when /\Atrue\z/i; true
          when true; true
          else false
          end
        end

        filters[:archived] = builder.term_filter(:archived, singular: true) do |value|
          case value
          when /\Atrue\z/i; true
          when true; true
          else false
          end
        end

        filters[:sponsorable] = builder.term_filter(:sponsorable, singular: true) do |value|
          case value
          when /\Atrue\z/i; true
          when true; true
          else false
          end
        end

        filters[:forks]      = builder.range_filter(:forks)
        filters[:size]       = builder.range_filter(:size)
        filters[:followers]  = builder.range_filter(:followers, :followers, :stars)

        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:pushed_at]  = builder.date_range_filter(:pushed_at,  :pushed)

        if @experiment_unbounded
          filters[:repo_id] = builder.owner_repo_filter(current_user, cap_filter:, skip_permission_check: @skip_permission_check, limit_to_repo_ids: @limit_to_repo_ids)
          filter_tag = filters[:repo_id].filter_type
        elsif filter_with_owner_id?
          filter_tag = "filter:owner"
          filters[:owner_id] = builder.term_filter(:owner_id, :org, :owner, :user) do
            single_owner.id
          end
        elsif @skip_permission_check && @limit_to_repo_ids.present?
          filter_tag = "filter:limit"
          filters[:repo_id] = Search::Filters::RepoIdFilter.new(:repo_id, @limit_to_repo_ids)
        elsif @experiment_owner_id_and_repo_id && filter_with_owner_id_and_repo_id?
          filter_tag = "filter:owner_visibility"
          filters[:repo_id] = Search::Filters::OwnerVisibilityFilter.new(single_owner, filters[:visibility], current_user:, cap_filter:)
          # Once we're applied the visibility filter in the repo_id filter, we can drop it, it's a duplication
          filters.delete(:visibility) unless filters[:visibility].bool_collection.must_not?
        else
          filter_tag = "filter:repository"
          filters[:repo_id] = builder.repository_filter(current_user, nil, "metadata", cap_filter:, user_session:, ip: remote_ip, limit_to_repo_ids: @limit_to_repo_ids)
        end

        instrument_repo_ids_size(filters[:repo_id], filter_tag)

        filters[:num_topics] = builder.range_filter(:num_topics, :topics)
        filters[:has_funding_file] = builder.term_filter(:has_funding_file)

        filters[:help_wanted_issues_count] = builder.range_filter(:help_wanted_issues_count, :"help-wanted-issues")
        filters[:good_first_issue_issues_count] = builder.range_filter(:good_first_issue_issues_count, :"good-first-issues")

        if star_search?
          filters[:star_search] = builder.star_filter(current_user, star_user)
        end

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def repo_ids_size
        filter_hash[:repo_id]&.repo_ids_size || 0
      end

      def valid_query?
        return false unless super

        if global? && escaped_query.empty? && !filtering_by_topic? && !filtering_out_topic?
          filters = filter_hash.keys - [:repo_id, :owner_id, :fork]
          if filters.empty?
            @invalid_reason = if any_custom_property_qualifiers?
              "Cannot search for custom properties without specifying an organization"
            else
              ::Search::Query::REASON_EMPTY_QUERY
            end
            return false
          end
        end

        true
      end

      def any_custom_property_qualifiers?
        qualifiers.any? { |key, _value| PROPERTIES_PREFIXED_REGEX.match(key) }
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

      # Internal: Take the array of repository results and remove those that
      # no longer exist in the database or have been flagged as spammy. We
      # will only perform this pruning in test and production; development
      # mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        repo_ids = results.map { |h| h["_id"] }
        repos = Repository.where(id: repo_ids).preload(@preload_tables)
        repos = repos.includes(repository_topics: [:topic]) if @include_topics
        repos = repos.index_by(&:id)

        results.delete_if do |h|
          repo_id = h["_id"].to_i
          repo = repos[repo_id]
          pub = is_public? h

          if repo.nil?
            GitHub.dogstats.increment("search.query.exclude.nil", { tags: metric_tags })
            true

          elsif !repo.repo_is_searchable?(log_reason: true)
            GitHub.dogstats.increment("search.query.exclude.is_searchable", { tags: metric_tags })
            true

          # This is a special case where an inaccessible repo cannot be automatically excluded from the search
          # results by the repository_filter. The repository_filter works by constructing an allow-list of all
          # private repos the user has access to. But a repo satisfying these conditions is a _public_ repo that
          # has been specifically marked to only show up for specific users. Our only choice is to filter it out
          # here, after the query has completed.
          elsif repo.collaborators_only? && !repo.writable_by?(current_user)
            true

          # if the public visibility of the repository has changed
          elsif !pub.nil? && repo.public != pub
            Search.add_to_search_index("repository", repo_id)
            true

          else
            h["_model"] = repo
            !security_validation h
          end
        end
      end

      # Validate that the user is allowed to see the given search result
      # document.
      #
      # doc - The search result Hash
      #
      # Returns boolean indicating visibility.
      def security_validation(doc)
        repo = doc["_model"]

        if filter_hash[:owner_id]
          return true if repo.owner_id == single_owner.id
        else
          return true if filter_hash[:repo_id].accessible_repository?(repo)
        end

        GitHub.dogstats.increment("search.query.errors.security", { tags: metric_tags })
        false
      end

      # Internal: Returns `true`, `false`, or `nil`. nil will only be returned
      # if a public attribute is not included as part of the search result
      # doc.
      #
      # doc - The document Hash returned from the search index.
      #
      def is_public?(doc)
        if source = doc["_source"]
          source["public"]
        end
      end

      # Internal: Returns combined Elastic Search query doc for query and applied/negated topics
      def query_with_topics(query_hash)
        must = [query_hash]
        must_not = nil

        if filtering_by_topic?
          must.push(*topic_queries)
        end

        if filtering_out_topic?
          must_not = [*topic_not_queries].compact
        end

        must.compact!
        must = nil if must.empty?

        { bool: { must: must, must_not: must_not }.compact } #remove nil elements from final query
      end

      SUSPICIOUS_QUERIES = [
        "is:public sort:updated",
        "created:>2012-01-01, sort:updated-desc",
      ]

      # Public: Check if the query is suspicious and allow callers to disable it
      # This is a helper method exposed to external consumers, not applied automatically in RepoQuery.
      def self.query_text_forbid_message(query)
        if SUSPICIOUS_QUERIES.include?(query.user_query) && GitHub.flipper[:query_ban_suspicious_queries].enabled?
          return "This search query is disabled."
        end

        if query.query.blank? && GitHub.flipper[:query_check_text_query_present].enabled?
          return "The search must include some text, not only qualifiers."
        end

        if query.user_query.present? && query.user_query.length > 256 && GitHub.flipper[:query_check_user_query_length].enabled?
          return "The complete search text is longer than 256 characters."
        end

        nil
      end

      private

      # Private: Is the user making a query for topics that have been manually applied
      # to repositories, and they're allowed to do so?
      def filtering_by_topic?
        qualifiers[:topic] && (qualifiers[:topic].must? || qualifiers[:topic].and_should?)
      end

      def filtering_out_topic?
        qualifiers[:topic] && qualifiers[:topic].must_not?
      end

      def topic_query_for(term)
        inner_query = case term
        when Array
          {
            bool: {
              should: term.map do |t|
                { match: { "ranked_hashtags.applied" => t } }
              end
            }
          }
        else
          { match: { "ranked_hashtags.applied" => term } }
        end

        {
          nested: {
            path: "ranked_hashtags",
            query: {
              function_score: {
                query: inner_query,
                score_mode: "multiply",
                functions: [
                  {
                    field_value_factor: { field: "ranked_hashtags.rank", missing: 1 },
                  },
                ],
              },
            },
          },
        }
      end

      def topic_queries
        # and_should are comma-syntax enumerable terms, that are AND's (must) with other contitions
        extended_must = (qualifiers[:topic].must || []) + (qualifiers[:topic].and_should || [])
        extended_must.map { |term| topic_query_for(term) }
      end

      def topic_not_queries
        qualifiers[:topic].must_not.map { |term| topic_query_for(term) }
      end

      def can_use_properties?
        return false unless single_owner.present?
        return false unless single_owner.organization?
        return true if @skip_permission_check
        return false unless current_user

        ::Repositories.domain.custom_properties.can_see_property_definitions?(current_user, single_owner)
      end

      def filter_with_owner_id?
        @limit_to_repo_ids.nil? &&
          !any_repo_qualifier? &&
          can_view_all_repos_of_single_org? &&
          single_org_accessible?
      end

      def filter_with_owner_id_and_repo_id?
        @limit_to_repo_ids.nil? &&
          !any_repo_qualifier? &&
          single_owner.present? &&
          single_owner.organization? &&
          single_org_accessible?
      end

      def can_search_private_repositories_for_user?
        return false unless current_user
        Api::AccessControl.scope?(current_user, "repo")
      end

      # Private: The account logins to exclude from results based on
      # whether the current user does not meet any of the conditional access policies
      # (e.g. SAML policy or IP allow list policy)
      #
      # Returns Array of String.
      def protected_account_logins
        @cap_filter.unauthorized_resources(
          current_user&.resources_for_cap_filter
        ).pluck(:login)
      end

      def can_view_all_repos_of_single_org?
        return @can_view_all_repos_of_single_org if defined?(@can_view_all_repos_of_single_org)

        @can_view_all_repos_of_single_org = single_owner.present? &&
          single_owner.organization? &&
          (@skip_permission_check || single_owner.adminable_by?(current_user))
      end

      # Private: The single org is accessible to the current user based on the cap_filter
      # This returns false also if no cap_filter is provided, which means we should not
      # apply the owner_id optimization and instead use builder.repository_filter
      # which creates its own cap_filter to check accessibility.
      def single_org_accessible?
        return true if @skip_permission_check
        return false unless @cap_filter.present?
        if current_user
          return false unless can_search_private_repositories_for_user?
          return false if current_user.governed_by_oauth_application_policy?
        end

        !protected_account_logins.include?(single_owner.display_login)
      end

      OWNER_QUALIFIERS = %i(org user owner).freeze

      def single_owner
        return @single_owner if defined?(@single_owner)

        logins = owner_must_logins
        @single_owner = logins.size == 1 ? User.find_by(login: logins.first) : nil
      end

      def metric_tags
        [
          "index:#{index.name}",
          "classname:#{T.must(self.class.name).demodulize.underscore}",
        ]
      end

      def instrument_repo_ids_size(repo_filter, filter_tag)
        tags = metric_tags.dup

        tags << filter_tag

        tags << "cap_filter:#{cap_filter.present?}"
        tags << "skip_permission_check:#{@skip_permission_check}"

        owner_size_value = %w(none one)[owner_must_logins.size] || "many"
        tags << "owner_must_size:#{owner_size_value}"
        tags << "owner_must_not_present:#{owner_must_not_logins.size > 0}"

        limited_results = if repo_filter.respond_to?(:hit_max_repo_filter_limit?)
          repo_filter.hit_max_repo_filter_limit?
        else
          false
        end
        tags << "limited_results:#{limited_results}"

        tags << "controller:#{GitHub.context[:controller]}"
        tags << "action:#{GitHub.context[:controller_action]}"

        repo_ids_size = repo_filter.present? ? repo_filter.repo_ids_size : 0
        GitHub.dogstats.histogram("search.repo_query.repo_ids", repo_ids_size, { tags: })
      end

      def any_repo_qualifier?
        qualifiers[:repo].must? || qualifiers[:repo].must_not?
      end

      def owner_must_logins
        OWNER_QUALIFIERS.map { |name| qualifiers[name].must }.compact.flatten
      end

      def owner_must_not_logins
        OWNER_QUALIFIERS.map { |name| qualifiers[name].must_not }.compact.flatten
      end
    end  # RepoQuery
  end  # Queries
end  # Search
