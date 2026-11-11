# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module SearchHelper
      def execute_search(**arguments)
        current_user = @context[:viewer]

        query_class = case arguments[:type]
        when "Issues";       ::Search::Queries::IssueQuery
        when "IssuesAdvanced"; ::Search::Queries::ConditionalIssueQuery
        when "IssuesSemantic"; ::Search::Queries::ConditionalIssueSemanticQuery
        when "IssuesHybrid"; ::Search::Queries::ConditionalIssueHybridQuery
        when "Repositories"; ::Search::Queries::RepoQuery
        when "Users";        ::Search::Queries::UserQuery
        when "UserLogin";    ::Search::Queries::UserLoginQuery
        when "Discussions";  ::Search::Queries::DiscussionQuery
        end

        is_issues_search = arguments[:type].in?(%w[Issues IssuesAdvanced IssuesSemantic IssuesHybrid])

        repo_id = @context[:scoped_repo_id].present? ? @context[:scoped_repo_id] : nil

        if is_issues_search
          # Exclude archived PRs from search results.
          scoped_repo = repo_id ? ::Repository.find_by(id: repo_id) : nil
          if scoped_repo.nil? || FeatureFlag.vexi.enabled?(:archive_pull_request, scoped_repo, default: false)
            is_admin = scoped_repo&.adminable_by?(current_user) || false
            components = if arguments[:type] == "Issues"
              ::Search::Queries::IssueQuery.parse(arguments[:query], current_user)
            else
              ::Search::ParsedQuery.parse(arguments[:query], terms: [:is])
            end
            filtered = ::Search::Queries::IssueQuery.enforce_archived_pr_visibility(components, is_admin: is_admin)
            arguments = arguments.merge(query: ::Search::ParsedQuery.stringify(filtered))
          end

          query = execute_issues_search_via_domain(arguments, is_issues_search, repo_id, current_user)
        else
          opts = build_query_opts(arguments, is_issues_search, repo_id, current_user)
          query = query_class&.new(opts)
        end

        if @context && @context[:rails_request]
          @context[:rails_request]&.env[GitHub::TaggingHelper::SEARCH_QUERY_CLASS] = query&.class&.name
        end
        GitHub.dogstats.increment("search.query.class", tags: ["class:#{query&.class&.name}"])

        if arguments[:type] == "Repositories"
          return [] if ::Search::Queries::RepoQuery.query_text_forbid_message(query).present?
        end

        query
      end

      def execute_issues_search_via_domain(arguments, is_issues_search, repo_id, current_user)
        opts = build_query_opts(arguments, is_issues_search, repo_id, current_user)

        opts[:internal_schema] = @context[:permission].present? && Platform::Helpers::ViaActions.using_internal_schema?(@context)
        opts[:oauth_app] = @context[:oauth_app]
        result = Issues.domain.semantic_search.resolve_query(
          query: arguments[:query],
          current_user: current_user,
          type: arguments[:type],
          repo_id: repo_id,
          opts: opts
        )
        result.unwrap!
      end

      # Builds the shared opts hash for search queries.
      def build_query_opts(arguments, is_issues_search, repo_id, current_user)
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
          allow_insecure_user_to_server_app_query: false,
          current_user: current_user,
          user_session: @context[:user_session],
          cap_filter: @context[:cap_filter],
          repo_id: repo_id,
          remote_ip: @context[:ip],
          current_installation: @context[:installation],
          aggregations: arguments[:aggregations],
          phrase: arguments[:query],
          highlight: highlight,
          normalizer: normalizer,
          source_fields: source_fields,
          context: "graphql-search",
          catalog_service: @context[:catalog_service].present? ? @context[:catalog_service] : nil,
          referrer_controller_action: @context[:referrer_controller_action],
        }

        if is_issues_search && bypass_query_limitation
          opts[:bypass_query_limitation] = true
        end

        opts
      end

      def bypass_query_limitation
        @context[:operation_id].present? && @context[:viewer].present?
      end
    end
  end
end
