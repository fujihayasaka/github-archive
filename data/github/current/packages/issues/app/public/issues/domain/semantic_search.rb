# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class SemanticSearch < GH::Domain::Base
      class FullTextResult < T::Struct
        const :results, ::Search::Results[T.untyped]
        const :query_class_name, String
      end

      # All known fallback reasons for semantic search.
      # Every call to set_fallback must use one of these enum values.
      class FallbackReason < T::Enum
        enums do
          NoTextTerms = new("no_text_terms")
          QuotedText = new("quoted_text")
          OnlyNonSemanticFieldsRequested = new("only_non_semantic_fields_requested")
          NonIssueTarget = new("non_issue_target")
          OrBooleanNotSupported = new("or_boolean_not_supported")
          InferenceError = new("inference_error")
          NoAccessibleRepos = new("no_accessible_repos")
          ServiceUnavailable = new("service_unavailable")
        end
      end

      # Fallback reasons that are safe to expose publicly.
      # Any reason not in this set will be logged, metricked, and surfaced
      # to the caller as "server_error".
      ALLOWED_PUBLIC_FALLBACK_REASONS = T.let([
        FallbackReason::NoTextTerms,
        FallbackReason::QuotedText,
        FallbackReason::NonIssueTarget,
        FallbackReason::OrBooleanNotSupported,
        FallbackReason::NoAccessibleRepos,
        FallbackReason::InferenceError,
        FallbackReason::OnlyNonSemanticFieldsRequested,
        FallbackReason::ServiceUnavailable,
      ].freeze, T::Array[FallbackReason])

      # Maps internal enum values to public-facing reason strings when they differ.
      # Reasons not in this map use their serialized enum value as-is.
      PUBLIC_REASON_NAMES = T.let({
        FallbackReason::InferenceError => "server_error",
      }.freeze, T::Hash[FallbackReason, String])

      # Filters a list of fallback reasons to only those on the allowlist.
      # Unknown reasons are replaced with ServerError, logged, and counted via
      # a metric so we can detect unregistered reasons that slip through.
      # Returns nil when no allowed reasons remain so callers can omit the field.
      sig { params(reasons: T.nilable(T::Array[FallbackReason])).returns(T.nilable(T::Array[String])) }
      def self.filter_fallback_reasons(reasons) # rubocop:disable Metrics/MethodLength
        return nil if reasons.nil?

        server_error_api_name = T.must(PUBLIC_REASON_NAMES[FallbackReason::InferenceError])
        has_unknown = T.let(false, T::Boolean)
        filtered = reasons.filter_map do |r|
          if ALLOWED_PUBLIC_FALLBACK_REASONS.include?(r)
            PUBLIC_REASON_NAMES[r] || r.serialize
          else
            has_unknown = true
            report_unknown_fallback_reason(r.serialize)
            nil
          end
        end

        filtered << server_error_api_name if has_unknown && !filtered.include?(server_error_api_name)
        filtered.empty? ? nil : filtered
      end

      # Reports an unknown fallback reason via error logging and a DataDog metric.
      sig { params(reason: String).void }
      def self.report_unknown_fallback_reason(reason)
        GitHub.logger.error(
          "Unregistered semantic search fallback reason encountered",
          "code.namespace" => "Issues::Domain::SemanticSearch",
          "code.function" => "filter_fallback_reasons",
          "gh.search.unknown_fallback_reason" => reason,
        )
        GitHub.dogstats.increment(
          "search.advanced_search.unknown_fallback_reason",
          tags: ["reason:#{reason}"]
        )
      end

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
          opts: T::Hash[Symbol, T.untyped],
        ).returns(GH::Result[::Search::Queries::IssueQuery])
      end
      def resolve_query(query:, current_user:, type:, repo_id:, opts:) # rubocop:disable Metrics/MethodLength
        query_class = query_class_for_type(type)
        semantic_repo_ids = T.let(nil, T.nilable(T::Array[Integer]))

        # The caller chooses the query strategy via the type parameter.
        # IssuesAdvanced always stays as the base conditional query class
        # (lexical); to get semantic/hybrid behavior, use IssuesHybrid or
        # IssuesSemantic explicitly.
        skip_semantic_upgrade = type == "IssuesAdvanced"

        if !skip_semantic_upgrade && eligible_for_semantic?(query: query, current_user: current_user, opts: opts)
          repo_id ||= resolve_repo_from_query(query, current_user)
          opts[:repo_id] = repo_id if repo_id

          if repo_id
            query_class = semantic_query_class(fallback_class: query_class, type: type, repo_id: repo_id, current_user: current_user)
          else
            resolved = resolve_dashboard_semantic(query: query, current_user: T.must(current_user), type: type, fallback_class: query_class, cap_filter: opts[:cap_filter])
            query_class = resolved[:query_class]
            semantic_repo_ids = resolved[:semantic_repo_ids]
          end
        elsif semantic_search_query_class?(query_class)
          # When the client explicitly requests a semantic/hybrid type but the
          # query is not eligible, fall back to the base conditional query class.
          semantic_fallback_reasons = Issues::Domain::SemanticSearch.filter_fallback_reasons(@ineligibility_reasons)
          query_class = ::Search::Queries::ConditionalIssueQuery
        end

        opts[:semantic_repo_ids] = semantic_repo_ids if semantic_repo_ids.present?

        if semantic_search_query_class?(query_class)
          opts[:semantic_eligibility_pre_checked] = true
        end

        query_instance = query_class.new(opts)
        query_instance.semantic_fallback_reasons = semantic_fallback_reasons if semantic_fallback_reasons
        GH::Result::Ok.new(query_instance)
      end

      # Executes a full-text semantic or hybrid search.
      # Handles query class selection, repo scoping,
      # semantic flag wiring, and query execution.
      #
      # Returns GH::Result::Ok with FullTextResult on success,
      # GH::Result::Error::Argument for domain-level errors
      # (invalid search_type, scope qualifiers on pure semantic),
      # GH::Result::Error for query validation errors
      # (invalid query, max offset, insecure query), or
      # GH::Result::Ok with empty results on unexpected execution
      # errors (reported via Failbot).
      #
      # Hybrid search allows scope qualifiers (org:, user:, owner:) since
      # the hybrid query derives KNN repo IDs from its lexical
      # RepositoryFilter. Pure semantic search errors on these qualifiers.
      #
      # When no top repos are available for global queries, falls back to
      # a lexical ConditionalIssueQuery instead of returning an error.
      sig do
        params(
          query: String,
          current_user: T.nilable(User),
          search_type: String,
          page: Integer,
          per_page: Integer,
          sort: T.untyped,
          highlight: T.untyped,
          normalizer: T.untyped,
          source_fields: T.untyped,
          remote_ip: T.nilable(String),
          current_enterprise_installation: T.untyped,
          cap_filter: T.untyped
        ).returns(GH::Result[FullTextResult])
      end
      def full_text( # rubocop:disable Metrics/MethodLength
        query:,
        current_user:,
        search_type:,
        page:,
        per_page:,
        sort: nil,
        highlight: false,
        normalizer: nil,
        source_fields: false,
        remote_ip: nil,
        current_enterprise_installation: nil,
        cap_filter: nil
      )
        search_class = case search_type
        when "hybrid"
          ::Search::Queries::ConditionalIssueHybridQuery
        when "semantic"
          ::Search::Queries::ConditionalIssueSemanticQuery
        else
          return GH::Result::Error::Argument.new(
            "Invalid search_type '#{search_type}'. Must be 'semantic' or 'hybrid'."
          )
        end

        query_opts = {
          allow_insecure_user_to_server_app_query: false,
          current_user: current_user,
          current_enterprise_installation: current_enterprise_installation,
          remote_ip: remote_ip,
          phrase: query,
          source_fields: source_fields,
          sort: sort,
          page: page,
          per_page: per_page,
          highlight: highlight,
          normalizer: normalizer,
          context: "api-issues-search",
        }

        if search_class == ::Search::Queries::ConditionalIssueSemanticQuery &&
            FeatureFlag.vexi.enabled?(:semantic_search_bypass_validation, current_user, default: false)
          query_opts[:with_validation] = false
        end

        query_opts[:semantic_eligibility_pre_checked] = true
        query_opts[:allow_prs] = Issues::SemanticSearchEligibility.pr_semantic_search_enabled?(user: current_user)

        GitHub.logger.info(
          "Issue search: using semantic search via domain",
          user_id: current_user&.id,
          query: query,
          search_type: search_type,
          query_class: search_class.name,
        )

        parsed = ::Search::Queries::IssueSemanticHelper.parse_query(query, current_user)
        has_repo_qualifier = parsed.qualifiers[:repo]&.must?
        has_scope_qualifier = ::Search::Queries::IssueSemanticHelper.has_scope_qualifier?(parsed)

        if has_repo_qualifier
          query_opts[:context] = "api-issues-semantic-search"
        elsif has_scope_qualifier
          # Hybrid search can derive KNN repo IDs from its own lexical
          # RepositoryFilter, so scope qualifiers are allowed. Pure semantic
          # has no lexical component and cannot resolve repos this way.
          if search_class == ::Search::Queries::ConditionalIssueHybridQuery
            GitHub.logger.info(
              "Semantic search: scope qualifier with hybrid, allowing query",
              user_id: current_user&.id,
            )
            query_opts[:context] = "api-issues-semantic-search"
          else
            GitHub.logger.info(
              "Semantic search: explicit scope qualifier used, returning error",
              user_id: current_user&.id,
            )
            return GH::Result::Error::Argument.new(
              "Semantic search does not support org:, user:, or owner: qualifiers. Use repo: to scope your search."
            )
          end
        else
          top_repo_ids = ::Search::Queries::IssueSemanticHelper.fetch_top_repo_ids(
            user: current_user, cap_filter: cap_filter
          )

          if top_repo_ids.blank?
            GitHub.logger.info(
              "Semantic search: no top repositories available, falling back to lexical",
              user_id: current_user&.id,
            )
            search_class = ::Search::Queries::ConditionalIssueQuery
          else
            GitHub.logger.info(
              "Semantic search: using top repositories",
              user_id: current_user&.id,
              top_repo_ids: top_repo_ids,
            )

            if search_class == ::Search::Queries::ConditionalIssueHybridQuery
              query_opts[:semantic_repo_ids] = top_repo_ids
            else
              query_opts[:limit_to_repo_ids] = top_repo_ids
            end
          end
          query_opts[:context] = "api-issues-semantic-search"
        end

        search_query = search_class.new(query_opts)
        result = execute_search_query(search_query)

        unless result.ok?
          return GH::Result::Error.new(T.must(result.error).message)
        end

        results = result.unwrap!

        if search_query.respond_to?(:api_search_type)
          metadata = Search::Results::SearchMetadata.new(
            search_type: search_query.api_search_type,
            lexical_fallback_reason: search_query.api_fallback_reasons,
          )
          results.search_metadata = metadata
        end

        GH::Result::Ok.new(FullTextResult.new(results: results, query_class_name: T.must(search_class.name)))
      end

      # Finds issues semantically similar to a given issue.
      #
      # Returns GH::Result::Ok with an array of SimilarIssueResult on success,
      # GH::Result::Error::Forbidden when the user is not eligible,
      # GH::Result::Error::Argument for invalid target_type, or
      # GH::Result::Ok with an empty array on unexpected execution
      # errors (reported via Failbot).
      sig do
        params(
          issue: Issues::IIssue,
          current_user: T.nilable(User),
          page: Integer,
          per_page: Integer,
          threshold: T.nilable(Float),
          target_type: T.nilable(String),
        ).returns(GH::Result[T::Array[::Search::Queries::SimilarIssueResult]])
      end
      def similar_to(
        issue:,
        current_user:,
        page:,
        per_page:,
        threshold:,
        target_type:
      )
        eligibility_error = check_similar_to_eligibility(current_user: current_user, target_type: target_type)
        return eligibility_error if eligibility_error

        results = ::Search::Queries::SemanticSimilarIssueQuery.find_similar_to(
          issue: issue,
          current_user: current_user,
          page: page,
          per_page: per_page,
          threshold: threshold,
          target_type: target_type,
        )

        GH::Result::Ok.new(results)
      rescue StandardError => e
        Failbot.report(e, context: "issues_domain_semantic_search_similar_to")
        GH::Result::Ok.new([])
      end

      private

      sig do
        params(
          current_user: T.nilable(User),
          target_type: T.nilable(String)
        ).returns(T.nilable(GH::Result::Error[T::Array[::Search::Queries::SimilarIssueResult]]))
      end
      def check_similar_to_eligibility(current_user:, target_type:)
        unless Issues::SemanticSearchEligibility.can_search_issues_index?(
          user: current_user,
        )
          return GH::Result::Error::Forbidden.new("Semantic similar issues is not available")
        end

        if target_type && !::Search::Queries::SemanticSimilarIssueQuery::VALID_TARGET_TYPES.include?(target_type)
          return GH::Result::Error::Argument.new(
            "Invalid target_types '#{target_type}'. Must be one of: #{::Search::Queries::SemanticSimilarIssueQuery::VALID_TARGET_TYPES.join(', ')}"
          )
        end

        nil
      end

      sig { params(type: String).returns(T.class_of(::Search::Queries::IssueQuery)) }
      def query_class_for_type(type)
        case type
        when "IssuesAdvanced"
          ::Search::Queries::ConditionalIssueQuery
        when "IssuesSemantic"
          ::Search::Queries::ConditionalIssueSemanticQuery
        when "IssuesHybrid"
          ::Search::Queries::ConditionalIssueHybridQuery
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
        @ineligibility_reasons = T.let(nil, T.nilable(T::Array[Issues::Domain::SemanticSearch::FallbackReason]))
        return false unless current_user.present?
        return false unless Issues::SemanticSearchEligibility.can_search_issues_index?(user: current_user)

        @ineligibility_reasons = ::Search::Queries::IssueSemanticHelper.semantic_ineligibility_reasons(
          query, current_user, context: opts[:context] || "graphql-search"
        )
        @ineligibility_reasons.empty?
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

      sig { params(klass: T.class_of(::Search::Queries::IssueQuery)).returns(T::Boolean) }
      def semantic_search_query_class?(klass)
        klass.in?([::Search::Queries::ConditionalIssueHybridQuery, ::Search::Queries::ConditionalIssueSemanticQuery])
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
        return unless current_user.present?

        parsed = ::Search::Queries::IssueSemanticHelper.parse_query(query, current_user)
        repo_qual = parsed.qualifiers[:repo]
        return unless repo_qual&.must?

        repo_nwos = repo_qual.must.to_a
        return unless repo_nwos.size == 1

        Repository.nwo(repo_nwos.first)&.id
      end

      sig { params(search_query: ::Search::Queries::IssueQuery).returns(GH::Result[::Search::Results[T.untyped]]) }
      def execute_search_query(search_query)
        unless search_query.valid_query?
          return GH::Result::Error.new(search_query.invalid_reason)
        end

        results = search_query.execute
        GH::Result::Ok.new(results)
      rescue ::Search::Query::MaxOffsetError, ::Search::Queries::IssueQuery::InsecureUserToServerAppQuery => e
        GH::Result::Error.new(e.message)
      rescue StandardError => e
        Failbot.report(e, context: "issues_domain_semantic_search_full_text")
        GH::Result::Ok.new(Search::Results.empty)
      end
    end
  end
end
