# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class CommitQuery < ::Search::Query
      include Scientist

      # The set of fields that can be queried when performing a commit search
      def self.field_list
        [:is, :merge, :sort, :hash, :sha, :parent, :tree, :author, :"author-name", :"author-email", :"author-date", :committer, :"committer-name", :"committer-email", :"committer-date", :user, :org, :owner, :repo].freeze
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "author-date" => "author_date",
        "committer-date" => "committer_date",
      }.freeze

      DEFAULT_FILTER_KEYS = [:repo_id, :is_commit_state_doc]

      # Construct a CommitQuery.
      #
      # opts - The options Hash.
      #   :language - The language name or Linguist::Language instance to filter by
      #   :repo_id  - The Repository ID to filter by
      #
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Commits.new
        @repo_id  = opts.fetch(:repo_id, nil)
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        h = { type: "commit" }
        h[:routing] = routing if routing.present?
        h
      end

      def match(field, value, operator: :or)
        value && {
          match: {
            field => {
              query: value,
              operator: operator,
            },
          },
        }
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        inner_query = if escaped_query.empty?
          nil
        else
          {
            query_string: {
              query: escaped_query,
              fields: ["message"],
              default_operator: "AND",
            },
          }
        end

        decay_query = inner_query && {
          function_score: {
            query: inner_query,
            boost_mode: "sum",
            score_mode: "max",
            functions: [
              {
                exp: { author_date: { scale: "365d", decay: 0.5 } },
                weight: 20,
              },
              {
                exp: { committer_date: { scale: "365d", decay: 0.5 } },
                weight: 20,
              },
            ],
          },
        }

        author_user = searchable_users.find_by_login(qualifiers[:author].must.try(:first))
        committer_user = searchable_users.find_by_login(qualifiers[:committer].must.try(:first))

        clauses = [
          decay_query,
          author_user && { term: { author_id: author_user.id } },
          committer_user && { term: { committer_id: committer_user.id } },
          match(:"author_name", qualifiers[:"author-name"].must.try(:first), operator: :and),
          match(:"committer_name", qualifiers[:"committer-name"].must.try(:first), operator: :and),
          match(:"author_email", qualifiers[:"author-email"].must.try(:first), operator: :and),
          match(:"committer_email", qualifiers[:"committer-email"].must.try(:first), operator: :and),
        ].compact

        return if clauses.empty?

        q = if clauses.length == 1
          clauses.first
        else
          { bool: { must: clauses } }
        end

        ary = commit_sha(escaped_query)

        unless ary.empty?
          ary.unshift q
          q = { bool: { should: ary } }
        end

        q
      end

      def searchable_users
        if GitHub.flipper[:invalidate_private_profile_searches].enabled?(current_user)
          User.with_visible_profiles_for(current_user)
        else
          User.scoped
        end
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
        ary = query.scan(/\b[0-9a-f]{7,40}\b/i)

        ary.map! do |sha|
          { prefix: { hash: {
            value: sha,
            boost: 100,
          } } }
        end
        ary.compact!
        ary
      end

      def valid_query?
        return false unless super

        if query_doc.blank?
          filters = filter_hash.keys - DEFAULT_FILTER_KEYS
          if filters.empty?
            @invalid_reason = "Search text is required when searching commits. Searches that use qualifiers only are not allowed. Were you searching for something else?"
            return false
          end
        end

        true
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        {
          encoder: :html,
          type: "plain",
          fields: {
            message: { number_of_fragments: 0 },
          },
          require_field_match: true,
        }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
      end

      def qualifiers=(value)
        super(value)

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "public"
              qualifiers[:public].clear.must(true)
            when "private"
              qualifiers[:public].clear.must(false)
            end
          end
        end
      end

      # Make sure when adding any default filter keys, to include them in DEFAULT_FILTER_KEYS
      # to ensure that empty queries aren't being sent to ES
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        # Don't return commit state documents in the search results
        qualifiers[:is_commit_state_doc].must_not(true)

        filters[:sha] = builder.sha_filter(:hash, :hash, :sha)
        filters[:parent] = builder.sha_filter(:parent_hashes, :parent)
        filters[:tree] = builder.sha_filter(:tree_hash, :tree)
        filters[:merge] = builder.term_filter(:is_merge, :merge) do |value|
          case value
          when /true/i; true
          when true; true
          else false
          end
        end
        filters[:public] = builder.term_filter(:public)
        filters[:author_date] = builder.date_range_filter(:author_date, :"author-date")
        filters[:committer_date] = builder.date_range_filter(:committer_date, :"committer-date")
        filters[:repo_id] = builder.repository_filter(current_user, @repo_id, nil, user_session: user_session, ip: remote_ip)
        filters[:is_commit_state_doc] = builder.term_filter(:is_commit_state_doc)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Take the repository IDs and generate a routing String. This
      # routing string is used to limit our search to the specific set of
      # shards where the repository commits are stored.
      #
      # Returns a routing String.
      def routing
        if @repo_id
          @repo_id
        elsif !repository_filter.global?
          ids = repository_filter.accessible_repository_ids
          ids.length < 200 ? ids.to_a.join(",") : nil
        else
          nil
        end
      end

      def repository_filter
        filter_hash[:repo_id]
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

      # Internal: Take the array of commit results and remove those for which
      # the repository no longer exists or has been flagged as spammy. We will
      # only perform this pruning in test and production; development mode is
      # for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      #
      def prune_results(results)
        repo_ids = Set.new
        results.each { |h| repo_ids << h["_source"]["repo_id"] }
        repos = Repository.where(id: repo_ids.to_a.flatten.compact).index_by(&:id)

        error_reported = false
        repo_repairs = {}

        results.delete_if do |h|
          repo_id = h["_source"]["repo_id"].to_i
          repo = repos[repo_id]

          if repo.nil? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("commit", repo_id)
            RemoveFromSearchIndexJob.perform_later("repository", repo_id)
            true
          elsif !repo.commits_are_searchable? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("commit", repo_id)
            true
          elsif repo.public != h["_source"]["public"]
            unless repo_repairs[repo_id]
              Search.add_to_search_index("commit", repo_id, "purge" => true)
              GitHub.dogstats.increment("search.reconcile.update", { tags: ["index:" + index.name.to_s] })
              repo_repairs[repo_id] = true
            end
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
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        repo = doc["_model"]

        return true if repo.public?

        @include_repos ||= repository_filter.accessible_repository_ids
        return true if @include_repos.include? repo.id

        GitHub.dogstats.increment("search.query.errors.security", { tags: ["index:" + index.name.to_s] })
        false
      end

    end  # CommitQuery
  end  # Queries
end  # Search
