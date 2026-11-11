# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module SearchHelper
      def execute_search(**arguments)
        query_class = case arguments[:type]
        when "Issues";       ::Search::Queries::IssueQuery
        when "IssuesAdvanced"; ::Search::Queries::ConditionalIssueQuery
        when "Repositories"; ::Search::Queries::RepoQuery
        when "Users";        ::Search::Queries::UserQuery
        when "UserLogin";    ::Search::Queries::UserLoginQuery
        when "Discussions";  ::Search::Queries::DiscussionQuery
        end

        is_issues_search = arguments[:type] == "Issues" || arguments[:type] == "IssuesAdvanced"

        repo_id = @context[:scoped_repo_id].present? ? @context[:scoped_repo_id] : nil
        current_user = @context[:viewer]

        if is_issues_search && FeatureFlag.vexi.enabled?(:issues_search_domain, current_user, default: false)
          query = execute_issues_search_via_domain(arguments, is_issues_search, repo_id, current_user)
        else
          semantic_repo_ids = nil

          mobile_semantic_enabled = current_user.present? &&
                                    FeatureFlag.vexi.enabled?(:mobile_semantic_search, current_user, default: false) &&
                                    Apps::Privileged.capable?(:mobile_only_schema_mask, app: @context[:oauth_app])

          if is_issues_search &&
             Issues::SemanticSearchEligibility.can_search_issues_index?(user: current_user) &&
             (Platform::Helpers::ViaActions.using_internal_schema?(@context) || mobile_semantic_enabled) &&
             ::Search::Queries::IssueSemanticHelper.semantic_ineligibility_reasons(
               arguments[:query], current_user, context: "graphql-search"
             ).empty?

            repo_id ||= resolve_repo_from_query(arguments[:query], current_user)

            if repo_id
              query_class = issues_semantic_query_class(
                fallback_class: query_class,
                type: arguments[:type],
                repo_id: repo_id,
                current_user: current_user
              )
            elsif FeatureFlag.vexi.enabled?(:issues_dashboard_semantic_search, current_user, default: false)
              parsed = ::Search::Queries::IssueSemanticHelper.parse_query(arguments[:query], current_user)
              has_scope_qualifier = ::Search::Queries::IssueSemanticHelper.has_scope_qualifier?(parsed)

              top_repo_ids = if has_scope_qualifier
                # Scope-qualified (e.g., org/user/owner) queries — the hybrid query
                # will derive KNN repo IDs from its own lexical RepositoryFilter,
                # so no probe query or top repo IDs are needed here.
                nil
              else
                # Unscoped dashboard — use the user's top repositories for both components.
                ::Search::Queries::IssueSemanticHelper.fetch_top_repo_ids(
                  user: current_user,
                  cap_filter: @context[:cap_filter]
                )
              end

              # When a scope qualifier is present, top_repo_ids is nil but we still
              # want the hybrid query class — the query will derive KNN repo IDs
              # internally from its lexical RepositoryFilter.
              if top_repo_ids.present? || has_scope_qualifier
                # Always pass repo IDs to the semantic component only. The lexical
                # component uses the full repo set (scoped or global) without restriction.
                semantic_repo_ids = top_repo_ids if top_repo_ids.present?
                query_class = issues_semantic_query_class(
                  fallback_class: query_class,
                  type: arguments[:type],
                  repo_id: nil,
                  current_user: current_user
                )
              end
            end
          end

          # those are performance optimizations we can do when the query does not contain a text_matches node
          # highlighting can be skipped and we can also skip load all fields
          # this can save a lot of I/O time for some queries
          opts = build_query_opts(arguments, is_issues_search, repo_id, current_user)

          if semantic_repo_ids.present?
            opts[:semantic_repo_ids] = semantic_repo_ids
          end

          if is_issues_search && query_class.in?([::Search::Queries::ConditionalIssueHybridQuery, ::Search::Queries::ConditionalIssueSemanticQuery])
            opts[:semantic_eligibility_pre_checked] = FeatureFlag.vexi.enabled?(:semantic_search_pre_check, current_user, default: false)
          end

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

      # Builds the shared opts hash for search queries. Used by both the
      # domain path and the legacy path to prevent drift.
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

      # Resolve a single repo: qualifier NWO to a repo ID so dashboard queries
      # behave like repo-page scoped searches, avoiding top-repo fetches.
      def resolve_repo_from_query(query, current_user)
        return unless current_user.present? &&
          FeatureFlag.vexi.enabled?(:semantic_search_skip_top_repos_for_repo_qualifier, current_user, default: false)

        parsed = ::Search::Queries::IssueSemanticHelper.parse_query(query, current_user)
        repo_qual = parsed.qualifiers[:repo]
        return unless repo_qual&.must?

        repo_nwos = repo_qual.must.to_a
        return unless repo_nwos.size == 1

        Repository.nwo(repo_nwos.first)&.id
      end

      def issues_semantic_query_class(fallback_class:, type:, repo_id:, current_user:)
        semantic_class = case type
        when "IssuesAdvanced"
          ::Search::Queries::ConditionalIssueHybridQuery
        else
          fallback_class
        end
        GitHub.logger.info(
          "Issues index search: using semantic search",
          user_id: current_user.id,
          repo_id: repo_id,
          search_type: type,
          query_class: semantic_class.name,
        )

        semantic_class
      end
    end
  end
end
