# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module IssueSemanticHelper
      include GitHub::Memoizer
      extend T::Helpers
      abstract!

      SEMANTIC_ISSUE_SEARCH_REPO_LIMIT = 100

      # Fields that have dense vector embeddings and can be searched semantically.
      # When an in: qualifier includes at least one of these fields, semantic search
      # proceeds with KNN limited to the matching vectors. Non-semantic fields in
      # the qualifier (e.g., comments) are silently ignored for the KNN portion.
      SEMANTIC_SEARCHABLE_FIELDS = T.let(%w[title body].freeze, T::Array[String])

      # Lightweight parse of a query string to extract qualifiers without building a full query object.
      sig { params(query_string: String, current_user: T.nilable(User)).returns(::Search::ParsedQuery) }
      def self.parse_query(query_string, current_user)
        ::Search::ParsedQuery.new(
          query_string,
          ::Search::Queries::ConditionalIssueQuery.field_list,
          current_user,
        )
      end

      # Checks if the parsed query contains org:, user:, or owner: scope qualifiers.
      sig { params(parsed: ::Search::ParsedQuery).returns(T::Boolean) }
      def self.has_scope_qualifier?(parsed)
        [:org, :user, :owner].any? { |q| parsed.qualifiers[q]&.must? }
      end

      # Returns an array of FallbackReason values explaining why semantic search should NOT
      # be used for this query. An empty array means the query is eligible for semantic search.
      #
      # This performs a lightweight pre-check using ParsedQuery to avoid initializing
      # semantic/hybrid query classes when they would just fall back to lexical search.
      # When a context tag is provided, fallback metrics are emitted automatically.
      sig { params(query_string: String, current_user: T.nilable(User), context: T.nilable(String), allow_prs: T::Boolean).returns(T::Array[Issues::Domain::SemanticSearch::FallbackReason]) }
      def self.semantic_ineligibility_reasons(query_string, current_user, context: nil, allow_prs: false)
        # Global kill switch: immediately ineligible when semantic is unavailable
        unless Issues::SemanticSearchEligibility.semantic_available?
          return [Issues::Domain::SemanticSearch::FallbackReason::ServiceUnavailable]
        end

        parsed = self.parse_query(query_string, current_user)

        reasons = T.let([], T::Array[Issues::Domain::SemanticSearch::FallbackReason])

        # Must have free text (not just qualifiers)
        reasons << Issues::Domain::SemanticSearch::FallbackReason::NoTextTerms if parsed.query.blank?

        # Must not have quoted text in the free text portion
        reasons << Issues::Domain::SemanticSearch::FallbackReason::QuotedText if parsed.query.include?('"')

        # Check in: qualifier for semantic-capable fields.
        # Semantic search supports title and body via dense vectors; if the in:
        # qualifier includes at least one of those fields, the query stays eligible
        # and the KNN search is narrowed to the semantic-capable subset. Only fall
        # back when none of the requested fields have dense vectors (e.g., in:comments).
        if parsed.qualifiers[:in]&.must?
          in_values = Array(parsed.qualifiers[:in].must).flat_map { |v| v.split(/[,\s]/) }.map(&:downcase).reject(&:blank?)
          unless in_values.any? { |f| SEMANTIC_SEARCHABLE_FIELDS.include?(f) }
            reasons << Issues::Domain::SemanticSearch::FallbackReason::OnlyNonSemanticFieldsRequested
          end
        end

        # Must not explicitly target a non-issue type (e.g., is:pr, type:discussion),
        # unless the caller explicitly allows PR targets (e.g., REST API with PR rollout).
        unless allow_prs
          reasons << Issues::Domain::SemanticSearch::FallbackReason::NonIssueTarget if non_issue_type_targeted?(parsed)
        end

        # Must not have nested boolean qualifiers (OR operators)
        reasons << Issues::Domain::SemanticSearch::FallbackReason::OrBooleanNotSupported if query_string.match?(/\bOR\b/)

        if reasons.any? && context
          emit_semantic_fallback_metrics(reasons, tags: ["context:#{context}"])
        end

        reasons
      end

      # Emit fallback metrics for each ineligibility reason, mirroring the format
      # used by ConditionalIssueSemanticQuery#set_fallback.
      sig { params(reasons: T::Array[Issues::Domain::SemanticSearch::FallbackReason], tags: T::Array[String]).void }
      def self.emit_semantic_fallback_metrics(reasons, tags: [])
        reasons.each_with_index do |reason, index|
          GitHub.dogstats.increment(
            "search.advanced_search.semantic_fallback",
            tags: tags + [
              "fallback_reason:#{reason.serialize}",
              "fallback_reason_primary:#{index == 0}",
              "source:pre_check"
            ]
          )
        end
      end

      # Checks if the parsed query does not exclusively target issues. Semantic
      # search should only run when issues is the sole requested type — e.g.
      # "is:issue" or "type:issue" with no other type qualifiers present.
      # Only considers search-type values (issue, pr, pull-request), ignoring
      # state qualifiers (is:open) and custom issue type names (type:"Bug").
      sig { params(parsed: ::Search::ParsedQuery).returns(T::Boolean) }
      def self.non_issue_type_targeted?(parsed)
        search_type_values = T.let(%w[issue pr pull-request], T::Array[String])
        is_qualifiers = (parsed.qualifiers[:is]&.must || []).select { |v| search_type_values.include?(v) }
        type_qualifiers = (parsed.qualifiers[:type]&.must || []).select { |v| search_type_values.include?(v) }
        all_types = is_qualifiers + type_qualifiers
        issues_only = all_types == ["issue"]
        !issues_only
      end

      sig { params(user: T.nilable(User), cap_filter: T.untyped, limit: Integer).returns(T::Array[Integer]) }
      def self.fetch_top_repo_ids(user:, cap_filter:, limit: SEMANTIC_ISSUE_SEARCH_REPO_LIMIT)
        return [] unless user

        # TopRepositories merges ranked + unranked sources in Ruby, so we must
        # materialize full objects before extracting IDs.
        TopRepositories.for(
          viewer: user,
          cap_filter: cap_filter
        ).limit(limit).to_a.map(&:id)
      rescue StandardError => e
        Failbot.report(e, context: "fetch_semantic_search_top_repo_ids", user_id: user&.id)
        []
      end

      # Extracts the top N most recently updated repo IDs from a RepositoryFilter.
      # Used for org:/user:/owner:-scoped queries to scope the semantic (KNN)
      # component without restricting the lexical component.
      sig { params(repo_filter: ::Search::Filters::RepositoryFilter, limit: Integer).returns(T::Array[Integer]) }
      def self.select_top_repo_ids_from_filter(repo_filter, limit: SEMANTIC_ISSUE_SEARCH_REPO_LIMIT)
        repo_ids = repo_filter.accessible_repository_ids.to_a
        return [] if repo_ids.empty?

        # Select the most recently updated non-fork repos, matching the ranking
        # strategy used by RepositoryFilter#limit_repository_ids for lexical search.
        select_top_repo_ids(repo_ids, limit: limit)
      rescue StandardError => e
        Failbot.report(e, context: "select_top_repo_ids_from_filter", user_id: repo_filter.current_user&.id)
        []
      end

      # Legacy wrapper: extracts top repo IDs from a probe query's repository filter.
      # Used by the non-dedup code path (FF off) and search_helper probe queries.
      sig { params(query: ::Search::Queries::IssueQuery, limit: Integer).returns(T::Array[Integer]) }
      def self.fetch_scoped_repo_ids(query, limit: SEMANTIC_ISSUE_SEARCH_REPO_LIMIT)
        repo_filter = query.repository_filter
        return [] unless repo_filter

        repo_ids = repo_filter.accessible_repository_ids.to_a
        return [] if repo_ids.empty?

        select_top_repo_ids(repo_ids, limit: limit)
      rescue StandardError => e
        Failbot.report(e, context: "fetch_semantic_search_scoped_repo_ids", user_id: query.current_user&.id)
        []
      end

      # Shared: picks the top N most-recently-updated non-fork repos from a list of IDs.
      sig { params(repo_ids: T::Array[Integer], limit: Integer).returns(T::Array[Integer]) }
      def self.select_top_repo_ids(repo_ids, limit: SEMANTIC_ISSUE_SEARCH_REPO_LIMIT)
        Repository.where(id: repo_ids)
          .order(Arel.sql(
            "repositories.parent_id IS NULL DESC," \
            "GREATEST(repositories.updated_at, repositories.pushed_at) DESC," \
            "repositories.id"
          ))
          .limit(limit)
          .pluck(:id)
      end
      private_class_method :select_top_repo_ids

      # We need a stable sample size for KNN search to ensure consistent
      # pagination and aggregates. To do so, we need to oversample quite a bit (num_candidates)
      # and narrow down the results (k) afterwards.
      # Since we have two semantic fields (title and body), we can get back a maximum of
      # 2 * KNN_K results per query (other than lexical matches).
      KNN_K = 500
      KNN_CANDIDATES = 10_000
      SIMILARITY = 0.5

      requires_ancestor { IssueQuery }

      # Build a KNN query clause for the given field. Wraps KNN in a
      # nested query (required because the `nested` param on `knn` is only
      # supported at the top-level search request, not inside bool queries).
      sig { params(base_field: String, knn_params: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def self.build_knn_clause(base_field, **knn_params)
        {
          nested: {
            path: base_field,
            score_mode: "max",
            query: {
              knn: {
                field: "#{base_field}.embedding",
                **knn_params
              }
            }
          }
        }
      end

      def initialize(opts = {}, &block)
        opts[:quote_words] = false

        super(opts, &block)
      end

      def build_semantic_function_query(escaped_query, search_in_fields: [])
        include_title = search_in_fields.empty? || search_in_fields.include?("title")
        include_body = search_in_fields.empty? || search_in_fields.include?("body")

        # If no semantic-capable fields are requested, skip embedding inference entirely.
        return nil unless include_title || include_body

        query_vector = begin
          fetch_embedding_vector(escaped_query)
        rescue EmbeddingError
          return nil # will trigger fallback to lexical search
        end

        knn_clauses = []

        if include_title
          knn_clauses << IssueSemanticHelper.build_knn_clause(
            "title_dense_vector",
            query_vector: query_vector,
            boost: 1.5,
            k: KNN_K,
            num_candidates: KNN_CANDIDATES,
            similarity: SIMILARITY
          )
        end

        if include_body
          knn_clauses << IssueSemanticHelper.build_knn_clause(
            "body_dense_vector",
            query_vector: query_vector,
            boost: 1.0,
            k: KNN_K,
            num_candidates: KNN_CANDIDATES,
            similarity: SIMILARITY
          )
        end

        return nil if knn_clauses.empty?

        {
          bool: {
            should: knn_clauses,
            minimum_should_match: 1
          }
        }
      end

      def fetch_embedding_vector(text)
        return nil if text.blank?
        return nil if GitHub.es_issues_prs_inference_id.nil?

        start_time = T.let(Time.now, Time)
        success = false
        error_class = T.let(nil, T.nilable(String))
        error_message = T.let(nil, T.nilable(String))

        begin
          # Note: The underlying ElastomerClient automatically retries transient failures
          # (timeouts, connection errors) for GET/HEAD requests with max: 1 retry, 50ms base
          # interval, and exponential backoff. POST requests to /_inference/ endpoints are
          # also retried when the :elastomer_inference_post_retry feature flag is enabled.
          # The client has a 5 second read_timeout and 1 second open_timeout
          # by default. See lib/elastomer/router.rb and lib/elastomer/config.rb for the full
          # retry and timeout configuration.
          normalize = FeatureFlag.vexi.enabled?(:issues_normalize_query_embedding_vectors, current_user, default: false)
          embedding = Elastomer::VectorUtils.fetch_embedding(index, text, inference_id: GitHub.es_issues_prs_inference_id, normalize: normalize)
        rescue StandardError => e
          error_class = e.class.name
          error_message = e.message
          raise Search::Queries::EmbeddingError::EmbeddingFetchError.new(e)
        end

        if embedding.nil?
          error_class = Search::Queries::EmbeddingError::InvalidEmbeddingResponseError.name
          error_message = "Inference endpoint returned no embedding"
          raise Search::Queries::EmbeddingError::InvalidEmbeddingResponseError.new({})
        end

        success = true
        embedding
      ensure
        duration_ms = nil
        if start_time
          duration_ms = ((Time.now - start_time) * 1000).round
          tags = ["success:#{success}"]
          tags << "error_class:#{error_class}" if error_class
          GitHub.dogstats.distribution(
            "search.advanced_search.embedding_fetch.duration",
            duration_ms,
            tags: tags
          )
        end

        if error_class
          # Capture timeout configuration for debugging
          read_timeout = nil
          open_timeout = nil
          client = index.client
          if client.respond_to?(:connection)
            connection = client.connection
            if connection.respond_to?(:options)
              read_timeout = connection.options.timeout
              open_timeout = connection.options.open_timeout
            end
          end

          log_context = {
            "code.namespace" => "Search::Queries::IssueSemanticHelper",
            "code.function" => "fetch_embedding_vector",
            "exception.class" => error_class,
            "exception.message" => error_message,
            "gh.elasticsearch.inference_id" => GitHub.es_semantic_inference_id,
            "gh.elasticsearch.elapsed_time_ms" => duration_ms || 0,
            "gh.request_id" => GitHub.context[:request_id]
          }
          log_context["gh.elasticsearch.read_timeout"] = read_timeout if read_timeout
          log_context["gh.elasticsearch.open_timeout"] = open_timeout if open_timeout

          GitHub.logger.error("Failed to fetch embedding", log_context)
        end
      end

      def prune_results(results)
        issue_ids = []
        pull_request_ids = []
        error_reported = false

        results.each do |h|
          doc_id = h["_id"].to_i
          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues"; issue_ids << doc_id
          when "pull-requests"; pull_request_ids << doc_id
          end
        end

        issues = Instrumentation.track_time("search.dist.time", tags: ["index:#{index.name}", "action:prune_results_issues_lookup"]) do
          Issue.includes(:user, :repository).where(id: issue_ids).index_by(&:id)
        end

        pull_requests = ::PullRequest.includes(:user, :issue, :repository).where(id: pull_request_ids).index_by(&:id)

        results.delete_if do |h|
          doc_id = h["_id"].to_i

          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues"; prune_issue(h, issues[doc_id])
          when "pull-requests"; prune_pull_request(h, pull_requests[doc_id])
          end
        end
      end
    end
  end
end
