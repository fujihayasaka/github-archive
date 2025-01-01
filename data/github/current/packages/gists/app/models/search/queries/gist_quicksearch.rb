# typed: true
# frozen_string_literal: true

module Search::Queries

  class GistQuicksearch < GistQuery

    # Internal: Constructs the actual `:query` portion of the query
    # document. This will later be wrapped in a filtered query if search
    # qualifiers were also used.
    #
    # Returns the search query Hash.
    def query_doc
      return if escaped_query.empty?

      # We only search description for quicksearch
      query_opts = { match_phrase_prefix: {
        description: {
          query: query,
          slop: 8,
          max_expansions: 10,
        },
      } }

      q = { function_score: {
        query: query_opts,
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
    end

    def filter_hash
      return @filter_hash if defined?(@filter_hash)

      @filter_hash = super
      # Override gist_id filter to restrict results to gists
      # owned by this user or starred by them.
      @filter_hash[:gist_id] = Search::Filters::GistFilter.new \
        qualifiers: owned_or_starred_qualifiers,
        current_user: current_user
      @filter_hash
    end

    def valid_query?
      unless current_user
        @invalid_reason = "You must be logged in to use Gist quicksearch."
        return false
      end

      super
    end

    # Internal: Returns nil, thus disallowing aggregationing on quicksearch queries.
    def build_aggregations
      nil
    end

    # Internal: Returns nil since we don't support global filters.
    def build_filter
      nil
    end

    def owned_or_starred_qualifiers
      {
        user: ::Search::ParsedQuery::BoolCollection.new(:user).tap do |bool|
          bool.must(current_user.login)
        end,
        starred: ::Search::ParsedQuery::BoolCollection.new(:starred).tap do |bool|
          bool.must(current_user.login)
        end,
      }
    end
  end

end
