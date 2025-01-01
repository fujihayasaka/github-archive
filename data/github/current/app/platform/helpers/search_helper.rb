# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module SearchHelper
      def execute_search(**arguments)
        query_class = case arguments[:type]
        when "Issues";       ::Search::Queries::IssueQuery
        when "IssuesAdvanced"; ::Search::Queries::IssueQuery
        when "Repositories"; ::Search::Queries::RepoQuery
        when "Users";        ::Search::Queries::UserQuery
        when "UserLogin";    ::Search::Queries::UserLoginQuery
        when "Discussions";  ::Search::Queries::DiscussionQuery
        end

        is_issues_search = arguments[:type] == "Issues" || arguments[:type] == "IssuesAdvanced"

        if arguments[:type] == "IssuesAdvanced" && GitHub.issues_advanced_search_enabled?(@context[:viewer])
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
        source_fields = !is_using_text_matches && is_issues_search ? nil : true

        highlight = ::Search::OffsetHighlighter.defaults if is_using_text_matches
        normalizer = ->(results) do
          results.each do |result|
            ::Search::OffsetHighlighter.transform result["highlight"]
          end
        end if is_using_text_matches

        opts = {
          allow_insecure_user_to_server_app_query: !GitHub.flipper[:secure_user_to_server_search].enabled?,
          current_user: @context[:viewer],
          user_session: @context[:user_session],
          cap_filter: @context[:cap_filter],
          repo_id: @context[:scoped_repo_id].present? ? @context[:scoped_repo_id] : nil,
          remote_ip: @context[:ip],
          current_installation: @context[:installation],
          aggregations: arguments[:aggregations],
          phrase: arguments[:query],
          highlight: highlight,
          normalizer: normalizer,
          source_fields: source_fields,
          context: "graphql-search",
          catalog_service: @context[:catalog_service].present? ? @context[:catalog_service] : nil,
        }

        if is_issues_search && bypass_query_limitation
          opts[:bypass_query_limitation] = true
        end

        query = query_class&.new(opts)

        if arguments[:type] == "Repositories"
          return [] if ::Search::Queries::RepoQuery.query_text_forbid_message(query).present?
        end

        query
      end

      def bypass_query_limitation
        @context[:operation_id].present? && @context[:viewer].present? && @context[:viewer].feature_enabled?(:issues_react_bypass_es_limits)
      end
    end
  end
end
