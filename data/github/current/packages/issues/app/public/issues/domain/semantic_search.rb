# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class SemanticSearch < GH::Domain::Base
      # Determines semantic search eligibility, selects the appropriate query class,
      # resolves semantic repo IDs, and returns a fully instantiated (but unexecuted)
      # query object for the GraphQL connection wrapper to lazily execute.
      #
      # Always returns GH::Result::Ok — on ineligibility it falls back to the base
      # query class rather than returning an error.
      sig do
        params(
          query: String,
          current_user: T.nilable(User),
          type: String,
          repo_id: T.nilable(Integer),
          opts: T::Hash[Symbol, T.untyped]
        ).returns(GH::Result[::Search::Queries::IssueQuery])
      end
      def resolve_query(query:, current_user:, type:, repo_id:, opts:) # rubocop:disable Metrics/MethodLength
        base_query_class = base_class_for_type(type)
        query_class = base_query_class
        semantic_repo_ids = T.let(nil, T.nilable(T::Array[Integer]))

        if eligible_for_semantic?(query: query, current_user: current_user, opts: opts)
          repo_id ||= resolve_repo_from_query(query, current_user)
          opts[:repo_id] = repo_id if repo_id

          if repo_id
            query_class = semantic_query_class(fallback_class: base_query_class, type: type, repo_id: repo_id, current_user: current_user)
          elsif FeatureFlag.vexi.enabled?(:issues_dashboard_semantic_search, current_user, default: false)
            resolved = resolve_dashboard_semantic(query: query, current_user: T.must(current_user), type: type, fallback_class: base_query_class, cap_filter: opts[:cap_filter])
            query_class = resolved[:query_class]
            semantic_repo_ids = resolved[:semantic_repo_ids]
          end
        end

        opts[:semantic_repo_ids] = semantic_repo_ids if semantic_repo_ids.present?

        if query_class.in?([::Search::Queries::ConditionalIssueHybridQuery, ::Search::Queries::ConditionalIssueSemanticQuery])
          opts[:semantic_eligibility_pre_checked] = FeatureFlag.vexi.enabled?(:semantic_search_pre_check, current_user, default: false)
        end

        query_instance = query_class.new(opts)
        GH::Result::Ok.new(query_instance)
      end

      private

      sig { params(type: String).returns(T.class_of(::Search::Queries::IssueQuery)) }
      def base_class_for_type(type)
        case type
        when "IssuesAdvanced"
          ::Search::Queries::ConditionalIssueQuery
        else
          ::Search::Queries::IssueQuery
        end
      end

      sig do
        params(
          query: String,
          current_user: T.nilable(User),
          opts: T::Hash[Symbol, T.untyped]
        ).returns(T::Boolean)
      end
      def eligible_for_semantic?(query:, current_user:, opts:)
        return false unless Issues::SemanticSearchEligibility.can_search_issues_index?(user: current_user)

        internal_schema = opts[:internal_schema] == true
        mobile_semantic_enabled = current_user.present? &&
                                  FeatureFlag.vexi.enabled?(:mobile_semantic_search, current_user, default: false) &&
                                  Apps::Privileged.capable?(:mobile_only_schema_mask, app: opts[:oauth_app])

        return false unless internal_schema || mobile_semantic_enabled

        ::Search::Queries::IssueSemanticHelper.semantic_ineligibility_reasons(
          query, current_user, context: opts[:context] || "graphql-search"
        ).empty?
      end

      sig do
        params(
          fallback_class: T.class_of(::Search::Queries::IssueQuery),
          type: String,
          repo_id: T.nilable(Integer),
          current_user: T.nilable(User)
        ).returns(T.class_of(::Search::Queries::IssueQuery))
      end
      def semantic_query_class(fallback_class:, type:, repo_id:, current_user:)
        semantic_class = case type
        when "IssuesAdvanced"
          ::Search::Queries::ConditionalIssueHybridQuery
        else
          fallback_class
        end

        GitHub.logger.info(
          "Issues index search: using semantic search",
          user_id: current_user&.id,
          repo_id: repo_id,
          search_type: type,
          query_class: semantic_class.name,
        )

        semantic_class
      end

      sig do
        params(
          query: String,
          current_user: User,
          type: String,
          fallback_class: T.class_of(::Search::Queries::IssueQuery),
          cap_filter: T.untyped
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def resolve_dashboard_semantic(query:, current_user:, type:, fallback_class:, cap_filter:)
        parsed = ::Search::Queries::IssueSemanticHelper.parse_query(query, current_user)
        has_scope_qualifier = ::Search::Queries::IssueSemanticHelper.has_scope_qualifier?(parsed)

        # Scope-qualified (e.g., org/user/owner) queries — the hybrid query
        # will derive KNN repo IDs from its own lexical RepositoryFilter,
        # so no probe query or top repo IDs are needed here.
        # Unscoped dashboard — use the user's top repositories for both components.
        top_repo_ids = has_scope_qualifier ? nil : fetch_dashboard_top_repos(current_user, cap_filter)

        # When a scope qualifier is present, top_repo_ids is nil but we still
        # want the hybrid query class — the query will derive KNN repo IDs
        # internally from its lexical RepositoryFilter.
        if top_repo_ids.present? || has_scope_qualifier
          query_class = semantic_query_class(fallback_class: fallback_class, type: type, repo_id: nil, current_user: current_user)
          # Always pass repo IDs to the semantic component only. The lexical
          # component uses the full repo set (scoped or global) without restriction.
          { query_class: query_class, semantic_repo_ids: top_repo_ids.present? ? top_repo_ids : nil }
        else
          { query_class: fallback_class, semantic_repo_ids: nil }
        end
      end

      sig { params(user: User, cap_filter: T.untyped).returns(T.nilable(T::Array[Integer])) }
      def fetch_dashboard_top_repos(user, cap_filter)
        ::Search::Queries::IssueSemanticHelper.fetch_top_repo_ids(user: user, cap_filter: cap_filter)
      end

      # Resolve a single repo: qualifier NWO to a repo ID so dashboard queries
      # behave like repo-page scoped searches, avoiding top-repo fetches.
      sig { params(query: String, current_user: T.nilable(User)).returns(T.nilable(Integer)) }
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
    end
  end
end
