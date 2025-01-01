# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The WikiQuery is used to search wiki pages.
    #
    class WikiQuery < ::Search::Query

      # The set of fields that can be queried when performing a wiki search
      def self.field_list
        [:updated, :user, :org, :owner, :repo, :sort, :in].freeze
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "updated" => "updated_at",
      }.freeze

      DEFAULT_FILTER_KEYS = [:repo_id, :is_wiki_state_doc]

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # Construct a new WikiQuery instance that will highlight search results
      # by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Wikis.new
        @repo_id = opts.fetch(:repo_id, nil)
      end

      # Sets the list of source fields that will be returned for each matching
      # search document.
      #
      # value - Array of field names
      #
      def source_fields=(value)
        case value
        when Array, String
          @source_fields = Array(value).concat(%w[repo_id public])
          @source_fields.uniq!
        when nil, false
          @source_fields = %w[repo_id public]
        else
          @source_fields = true
        end
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        params = { type: "page" }
        params[:routing] = routing if routing.present?
        params
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "title";    @query_fields << "title^1.5"
          when "body";     @query_fields << "body"
          end
        end

        @query_fields = %w[title^1.5 body] if @query_fields.empty?
        @query_fields
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        {
          query_string: {
            query: escaped_query,
            fields: query_fields,
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          },
        }
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        { encoder: :html,
          type: "plain",
          fields: {
          title: { number_of_fragments: 0 },  # force the whole title to be included in the fragment
          body: { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE },
        } }
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

      # Internal: We need to use the same filters for the query and for the
      # aggregations with the exception of the language query. Since we are aggregationing
      # on language, applying a language filter would be most unhelpful.
      # Make sure when adding any default filter keys, to include them in DEFAULT_FILTER_KEYS
      # to ensure that empty queries aren't being sent to ES
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        # Don't return wiki state documents in the search results
        qualifiers[:is_wiki_state_doc].must_not(true)

        filters[:public]      = builder.term_filter(:public)
        filters[:updated_at]  = builder.date_range_filter(:updated_at, :updated)
        filters[:repo_id]     = builder.repository_filter(current_user, @repo_id, nil, user_session: user_session, ip: remote_ip)
        filters[:is_wiki_state_doc] = builder.term_filter(:is_wiki_state_doc)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def repository_filter
        filter_hash[:repo_id]
      end

      def global?
        repository_filter.global?
      end

      # Internal: Take the repository IDs and generate a routing String. This
      # routing string is used to limit our search to the specific set of
      # shards where the issues / pull requests are stored.
      #
      # Returns a routing String.
      def routing
        return @routing if defined? @routing

        unless global?
          ids = repository_filter.accessible_repository_ids
          @routing = ids.to_a.join(",") unless ids.length > 200
        end

        @routing
      end

      # Internal: Helper method that will ensure the query is not empty.
      #
      # Returns true for a valid query; false for an invalid query.
      def valid_query?
        return false unless super

        if global? && escaped_query.empty?
          filters = filter_hash.keys - DEFAULT_FILTER_KEYS
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
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of wiki results and remove those for which
      # the wiki no longer exists or has been flagged as spammy. We will
      # only perform this pruning in test and production; development mode is
      # for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        repo_ids = results.map { |h| h["_source"]["repo_id"] }.uniq

        repos = Repository.where(id: repo_ids).index_by(&:id)
        results.delete_if do |result|
          repo_id = result["_source"]["repo_id"].to_i
          repo = repos[repo_id]
          pub = is_public result

          # If the repo does not exist or is not searchable
          if repo.nil? || !repo.wiki_is_searchable?
            RemoveFromSearchIndexJob.perform_later("wiki", repo_id)
            true

          # If the public visibility of the repository has changed or the index
          # is out of sync with the database
          elsif !pub.nil? && repo.public != pub
            Search.add_to_search_index("wiki", repo_id)
            true

          # The result should be pruned from the list if the user lacks access to it.
          else
            result["_model"] = repo
            !security_validation result
          end
        end
      end

      # Internal: validate that the user is allowed to see the given search
      # result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        repo = doc["_model"]
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
    end
  end
end
