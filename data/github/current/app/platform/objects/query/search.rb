# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Search
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :search, Connections::SearchResultItem, description: "Perform a search across resources, returning a maximum of 1,000 results.", null: false, connection: true do
      argument :query, String, "The search string to look for. GitHub search syntax is supported. For more information, see \"[Searching on GitHub](https://docs.github.com/search-github/searching-on-github),\" \"[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax),\" and \"[Sorting search results](https://docs.github.com/search-github/getting-started-with-searching-on-github/sorting-search-results).\"", required: true
      argument :type, Enums::SearchType, "The types of search items to search within.", required: true
      argument :aggregations, Boolean, "Calculate aggregations. This arg must be true for `languageAggregations` to be returned.", default_value: false, visibility: :internal, required: false
      argument :skip, Integer, "The number of items to skip, for pagination.", required: false, visibility: :internal
    end

    def search(**arguments)
      query_class = case arguments[:type]
      when "Issues";       ::Search::Queries::IssueQuery
      when "Repositories"; ::Search::Queries::RepoQuery
      when "Users";        ::Search::Queries::UserQuery
      when "UserLogin";    ::Search::Queries::UserLoginQuery
      when "Discussions";  ::Search::Queries::DiscussionQuery
      end

      if arguments[:type] == "Issues" && GitHub.flipper[:issues_advanced_search].enabled?(@context[:viewer])
        query_class = ::Search::Queries::ConditionalIssueQuery
      end

      # Adding search query class to the request environment for request-level logging
      # See GitHub::Middleware::Stats
      if @context && @context[:rails_request]
        @context[:rails_request]&.env[GitHub::TaggingHelper::SEARCH_QUERY_CLASS] = query_class&.name
      end
      GitHub.dogstats.increment("search.query.class", tags: ["class:#{query_class&.name}"])

      # those are performance optimizations we can do when the query does not contain a text_matches node
      # highlighting can be skipped and we can also skip load all fields
      # this can save a lot of I/O time for some queries
      is_using_text_matches = @context.query.lookahead.selection(:search).selection(:edges).selection(:text_matches).name == :text_matches
      source_fields = !is_using_text_matches && arguments[:type] == "Issues" ? nil : true

      highlight = ::Search::OffsetHighlighter.defaults if is_using_text_matches
      normalizer = ->(results) do
        results.each do |result|
          ::Search::OffsetHighlighter.transform result["highlight"]
        end
      end if is_using_text_matches

      # See https://github.com/github/collaboration-workflows-flex/issues/938. For an Issue search where the
      # issues_advanced_search FF is not yet enabled, we're going to enqueue a background job to run the search
      # using *both* classes. We'll log the results of the searches and compare them to validate that our new
      # search code is doing what we expect it to do.
      if arguments[:type] == "Issues" && !GitHub.flipper[:issues_advanced_search].enabled?(@context[:viewer])
        # The issues_advanced_search_performance_validation FF will allow us to enable/disable background
        # search validation; we'll likely turn it on in bursts to get data, then turn it off while we do analysis.

        if !GitHub.enterprise? && GitHub.flipper[:issues_advanced_search_performance_validation].enabled?(@context[:viewer])
          GitHub.dogstats.increment("search.advanced_search.validation_job")
          Issues::ConditionalIssueQueryValidationJob.perform_later(
            allow_insecure_user_to_server_app_query: !GitHub.flipper[:secure_user_to_server_search].enabled?,
            current_user: @context[:viewer],
            user_session: nil, # We've decided not to pass user_session to start (see https://github.com/github/collaboration-workflows-flex/issues/705#issuecomment-2093572216)
            repo_id: @context[:scoped_repo_id].present? ? @context[:scoped_repo_id] : nil,
            remote_ip: @context[:ip],
            current_installation: @context[:installation],
            aggregations: arguments[:aggregations],
            phrase: arguments[:query],
            highlight: highlight,
            normalizer: normalizer,
            source_fields: source_fields,
            context: "graphql-search",
            catalog_service: @context[:catalog_service].present? ? @context[:catalog_service] : nil
          )
        end
      end

      query_class&.new \
        allow_insecure_user_to_server_app_query: !GitHub.flipper[:secure_user_to_server_search].enabled?,
        current_user: @context[:viewer],
        user_session: @context[:user_session],
        repo_id: @context[:scoped_repo_id].present? ? @context[:scoped_repo_id] : nil,
        remote_ip: @context[:ip],
        current_installation: @context[:installation],
        aggregations: arguments[:aggregations],
        phrase: arguments[:query],
        highlight: highlight,
        normalizer: normalizer,
        source_fields: source_fields,
        context: "graphql-search",
        catalog_service: @context[:catalog_service].present? ? @context[:catalog_service] : nil
    end
  end
end
