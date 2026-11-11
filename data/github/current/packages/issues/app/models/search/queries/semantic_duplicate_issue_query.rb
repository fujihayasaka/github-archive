# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # SemanticDuplicateIssueQuery is a dedicated KNN query class for detecting
    # potential duplicates of issue content before issue creation.
    #
    # Unlike general semantic search which uses hybrid lexical+semantic evaluation,
    # this class focuses on pure KNN similarity with high confidence thresholds
    # specifically tuned for accurate duplicate detection.
    #
    # For duplicate detection we prioritize precision over recall to minimize false positives, so we use:
    # - Pure KNN evaluation (no hybrid lexical component, unlike ConditionalIssueSemanticQuery/ConditionalIssueHybridQuery)
    # - Configurable similarity thresholds (0.75 default, 0.92 for high-precision contexts)
    # - Dedicated scoring weights optimized for duplicate detection (2.5/2.0 vs 2.0/1.75)
    # - Smaller result sets for higher precision (K=20 vs K=500, candidates=1000 vs 10000)
    # - Contextual thresholds: use high_confidence: true for UI contexts requiring maximum precision
    #
    # Primary use cases:
    # - Pre-creation duplicate detection for new issues
    # - Draft content duplicate validation in semantics_controller
    # - Issue submission flow duplicate prevention
    # - High-confidence duplicate alerts
    #
    # Usage in duplicate detection:
    #   content = IssueContent.new(title: "Bug report", body: "Description", repository_id: 123)
    #   query   = SemanticDuplicateIssueQuery.new(issue_content: content, current_user: user)
    #   potential_duplicates = query.execute.results
    #
    # Or using class method for controller usage:
    #   # Standard precision (includes medium + high confidence)
    #   duplicates = SemanticDuplicateIssueQuery.find_similar_to_content(
    #     title: "Bug report", body: "Description", repository_id: 123, current_user: user
    #   )
    #
    #   # High precision for UI contexts (high confidence only)
    #   high_confidence_duplicates = SemanticDuplicateIssueQuery.find_potential_duplicates_with_context(
    #     title: "Bug report", body: "Description", repository_id: 123, current_user: user, high_confidence: true
    #   )
    #
    # For additional context on the design and tuning decisions behind this implementation,
    # see the following discussion:
    #
    # https://github.com/github/copilot-indexing-issues-prs/discussions/650#discussioncomment-16071604
    #
    class SemanticDuplicateIssueQuery < IssueQuery
      include T::Sig
      include IssueSemanticHelper
      include GitHub::Memoizer

      class DuplicateDetectionError < StandardError; end

      # Duplicate detection specific constants - higher thresholds than general search
      HIGH_CONFIDENCE_THRESHOLD   = 0.92    # For UI contexts requiring high precision
      DUPLICATE_TITLE_WEIGHT      = 2.5     # Slightly higher weight for title matching
      DUPLICATE_BODY_WEIGHT       = 2.0     # Higher weight for body matching
      MAX_CONTENT_LENGTH          = 1000    # Extended context for comprehensive duplicate detection

      # Content length limits for safe embedding inference
      # Conservative default: 16K chars ~4K tokens (well under 8,192 token limit)
      # Can be increased via feature flag for repos that need more context
      DEFAULT_MAX_CONTENT_LENGTH  = 16_000  # Safe for most content (4K tokens at 4 chars/token)
      EXTENDED_MAX_CONTENT_LENGTH = 32_000  # Extended limit when feature flag enabled (~8K tokens)

      # KNN parameters optimized for duplicate detection
      DUPLICATE_KNN_K = 20                  # Fewer results, higher precision
      DUPLICATE_KNN_CANDIDATES = 2000       # Smaller candidate pool for faster, focused results
      DUPLICATE_SIMILARITY_THRESHOLD = 0.75 # Higher minimum similarity for duplicate detection

      # Elasticsearch timeout optimized for duplicate detection
      DUPLICATE_QUERY_TIMEOUT = "1500ms"    # Matches increased timeout, shorter than SemanticSimilarIssueQuery (2000ms)
      DUPLICATE_READ_TIMEOUT  = 2.5         # Shorter read timeout

      # Softens recency decay and removes reactions scoring to prevent older, valid duplicates
      # from being suppressed by age or engagement.
      DUPLICATE_SCORING_FUNCTIONS = [
        # Primary signal: Recent activity with softened decay
        {
          exp: {
            updated_at: {
              scale: "14d",   # Keep same scale for minimal change
              decay: 0.85,    # Softer decay: less aggressive penalization of older updates
              offset: "0d"    # No offset, immediate decay from now
            }
          }
        },
        # Secondary signal: Recent creation with much gentler decay
        {
          exp: {
            created_at: {
              scale: "90d",   # Keep same scale for minimal change
              decay: 0.9      # Much softer decay to preserve older canonical issues
            }
          }
        }
        # NOTE: Reactions scoring removed we couldn’t make it neutral (log1p(0)=0 still penalizes).
        # It was suppressing older, valid duplicates so field_value_factor was removed entirely.
      ].freeze

      # Result struct for duplicate detection - represents a potentially duplicate issue
      # with its similarity score and confidence classification
      class DuplicateIssueResult < T::Struct
        prop :issue, T.nilable(Issue)
        prop :score, T.nilable(Float)
        prop :confidence, Symbol

        # Check if this is a high-confidence duplicate
        sig { returns(T::Boolean) }
        def high_confidence_duplicate?
          confidence == :high
        end

        # Check if this is likely a duplicate (medium or high confidence)
        sig { returns(T::Boolean) }
        def likely_duplicate?
          [:medium, :high].include?(confidence)
        end

        # Validates that the result has all required fields for duplicate detection
        sig { returns(T::Boolean) }
        def valid?
          issue.present? && score.present? && confidence.present?
        end
      end

      class IssueContent < T::Struct
        prop :title, T.nilable(String)
        prop :body, T.nilable(String)
        prop :repository_id, Integer

        # Returns the body with long uninterrupted strings removed to prevent inference failures
        # Note: T::Struct instances are frozen, so we can't use instance variable memoization
        sig { returns(String) }
        def cleaned_body
          ::Search.remove_long_uninterrupted_strings(body.to_s, source: "duplicate_issue_detection")
        end

        # Validates that the content has searchable text.
        # Returns true if either title or body is present.
        sig { returns(T::Boolean) }
        def valid_for_search?
          title.present? || cleaned_body.present? || false
        end

        # Returns a clean, searchable content representation
        sig { returns(String) }
        def searchable_content
          parts = []
          parts << title.to_s.strip if title.present?
          parts << cleaned_body.strip if body.present?
          parts.join("\n").squish
        end

        # Returns total character count of content
        sig { returns(Integer) }
        def content_length
          (title&.length || 0) + (body&.length || 0)
        end
      end

      sig { returns(IssueContent) }
      attr_reader :issue_content

      # Expose repository_id for compatibility with parent class expectations
      sig { returns(Integer) }
      def repo_id
        @issue_content.repository_id
      end

      # Check if the content is valid for duplicate detection
      sig { returns(T::Boolean) }
      def valid_content?
        @issue_content.valid_for_search?
      end

      # Returns the repository object, loading it if not provided during initialization.
      # Note: DB lookup only occurs when instantiating directly with .new() without the repository parameter.
      # All factory methods (find_similar_to_content, find_potential_duplicates_with_context, etc.)
      # pass the repository, so they avoid this lookup. This method is memoized to avoid multiple lookups.
      sig { returns(T.nilable(::Repository)) }
      memoize def repository
        @repository || Repository.find_by(id: @issue_content.repository_id)
      end

      # Instantiates SemanticDuplicateIssueQuery for duplicate detection.
      # The query will use pure KNN evaluation with high confidence thresholds
      # to identify potential duplicates of the provided content.
      #
      # opts - The options Hash.
      #   :issue_content - The IssueContent struct containing title, body, and repository_id
      #   :repository - The Repository object (optional, will be looked up from issue_content if not provided)
      #   :current_user - The current User (optional)
      #   :threshold - The minimum score threshold for duplicate detection (default: 0.75)
      sig  { params(opts: T::Hash[Symbol, T.untyped]).void }
      def initialize(opts = {})
        @current_user = T.let(opts.fetch(:current_user, nil), T.nilable(::User))
        @repository = T.let(opts[:repository], T.nilable(::Repository))
        issue_content_param = opts.fetch(:issue_content)

        validate_issue_content!(issue_content_param)
        @issue_content = T.let(issue_content_param, IssueContent)

        # Validate content quality for duplicate detection
        unless @issue_content.valid_for_search?
          GitHub.dogstats.increment("search.duplicate_detection.invalid_content")
          raise DuplicateDetectionError, "Content must have either a title or body for duplicate detection"
        end

        @threshold = T.let(opts[:threshold] || DUPLICATE_SIMILARITY_THRESHOLD, Float)

        # Set up opts for IssueQuery parent class
        parent_opts = opts.merge(
          type: "issues",
          repo_id: @issue_content.repository_id,  # Parent sets @repo_id for routing optimization
          quote_words: false  # Disable quote processing for content matching
        )

        # Remove our custom params that are not relevant to the parent class
        parent_opts.delete(:issue_content)
        parent_opts.delete(:repository)
        parent_opts.delete(:threshold)
        parent_opts.compact!

        super(parent_opts)
      end

      # Find potential duplicate issues for the provided content.
      # This is the primary interface for duplicate detection in controllers.
      # Uses pure KNN evaluation with high confidence thresholds.
      #
      # Returns an array of DuplicateIssueResult structs containing:
      # - issue: The potentially duplicate Issue object
      # - score: The similarity score (Float), higher scores indicate more likely duplicates
      # - confidence: Confidence level (:high, :medium, :low) based on score thresholds
      #
      # The score is from Elasticsearch's KNN evaluation combining:
      # - Title semantic similarity (weight: 2.5)
      # - Body semantic similarity (weight: 2.0)
      # Higher scores indicate greater likelihood of being a duplicate.
      sig do
        params(
          title: T.nilable(String),
          body: T.nilable(String),
          current_user: T.nilable(::User),
          repository: T.nilable(::Repository),
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_similar_to_content(title:, body:, current_user:, repository: nil, threshold: nil, per_page: nil, page: nil, context: nil, **kwargs)
        # Early validation and return for duplicate detection
        return [] if repository.nil?
        return [] if title.blank? && body.blank?

        # Use factory method for better error handling in duplicate detection
        issue_content = create_issue_content(title:, body:, repository_id: repository.id)
        return [] if issue_content.nil?

        begin
          query = self.new(issue_content:, current_user:, repository:, threshold:, per_page:, page:, context:, **kwargs)
          search_result = query.execute.results

          # Log score distribution for threshold validation (behind feature flag)
          if search_result.any?
            scores = search_result.map { |r| r["_score"] }.compact
            query.log_score_distribution(scores)
          end

          search_result.map do |result|
            score = result["_score"] || 0.0
            confidence = classify_duplicate_confidence(score)
            DuplicateIssueResult.new(issue: result["_model"], score:, confidence:)
          end
        rescue DuplicateDetectionError => e
          # Handle known duplicate detection errors gracefully without raising
          Failbot.report(e)
          GitHub.dogstats.increment(
            "search.duplicate_detection.class_method.duplicate_detection_error",
            tags: ["error_class:#{e.class.name}"]
          )
          []
        rescue StandardError => e
          Failbot.report(e)
          GitHub.dogstats.increment(
            "search.duplicate_detection.class_method.error",
            tags: ["error_class:#{e.class.name}"]
          )
          raise e
        end
      end

      # Get duplicate results with contextual thresholds
      # Use high_confidence: true for UI contexts where precision is critical
      sig do
        params(
          title: T.nilable(String),
          body: T.nilable(String),
          current_user: T.nilable(::User),
          repository: T.nilable(::Repository),
          high_confidence: T::Boolean,
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_potential_duplicates_with_context(title:, body:, current_user:, repository: nil, high_confidence: false, threshold: nil, per_page: nil, page: nil, context: nil, **kwargs)
        effective_threshold = if high_confidence
          HIGH_CONFIDENCE_THRESHOLD
        else
          threshold || DUPLICATE_SIMILARITY_THRESHOLD
        end

        # T.unsafe: Sorbet limitation with **kwargs and required keyword params.
        # Safe - all required params explicitly passed, only overriding threshold.
        results = T.unsafe(self).find_similar_to_content(
          title:,
          body:,
          repository:,
          current_user:,
          threshold: effective_threshold,
          per_page:,
          page:,
          context:,
          **kwargs
        )

        # If high_confidence requested, filter to only high confidence results
        high_confidence ? high_confidence_only(results) : results
      end

      # Find high-confidence duplicate issues only.
      # This method is optimized for scenarios where only the most confident duplicate matches matter,
      # such as automatic duplicate detection warnings or high-precision UI such duplicate detection UI.
      #
      # Always uses HIGH_CONFIDENCE_THRESHOLD (0.92) and only returns results with :high confidence.
      # This provides a simpler interface compared to find_potential_duplicates_with_context
      # when you know you only want the highest confidence matches.
      #
      # Returns an array of DuplicateIssueResult structs with only high confidence duplicates.
      # Results are pre-filtered so all returned items will have confidence == :high.
      #
      # Example usage:
      #   high_confidence_duplicates = SemanticDuplicateIssueQuery.find_high_confidence_duplicates(
      #     title: "Critical bug in login flow",
      #     body: "Users are unable to log in",
      #     repository_id: 123,
      #     current_user: current_user
      #   )
      sig do
        params(
          title: T.nilable(String),
          body: T.nilable(String),
          current_user: T.nilable(::User),
          repository: T.nilable(::Repository),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String)
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_high_confidence_duplicates(title:, body:, current_user:, repository: nil, per_page: nil, page: nil, context: nil)
        # Call find_similar_to_content with high confidence threshold and filter results
        T.unsafe(self).find_potential_duplicates_with_context(
          title:,
          body:,
          repository:,
          current_user:,
          high_confidence: true,
          per_page:,
          page:,
          context:
        )
      end

      # Factory method to safely create IssueContent with validation for duplicate detection
      sig do
        params(
          title: T.nilable(String),
          body: T.nilable(String),
          repository_id: Integer
        ).returns(T.nilable(IssueContent))
      end
      def self.create_issue_content(title:, body:, repository_id:)
        content = IssueContent.new(
          title: title&.strip,
          body: body&.strip,
          repository_id:
        )
        content.valid_for_search? ? content : nil
      end

      # Convenience method to create duplicate detection query from raw content
      sig do
        params(
          title: T.nilable(String),
          body: T.nilable(String),
          repository_id: Integer,
          current_user: T.nilable(::User),
          threshold: T.nilable(Float),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T.nilable(SemanticDuplicateIssueQuery))
      end
      def self.from_content(title:, body:, repository_id:, current_user:, threshold: nil, **kwargs)
        return nil unless issue_content = create_issue_content(title:, body:, repository_id:)
        self.new(issue_content:, current_user:, threshold:, **kwargs)
      end

      # Get timeout settings optimized for duplicate detection
      def default_query_params
        super.merge(
          timeout: DUPLICATE_QUERY_TIMEOUT,
          read_timeout: DUPLICATE_READ_TIMEOUT
        )
      end

      # Build KNN query optimized for duplicate detection
      # Uses pure KNN evaluation with high confidence thresholds which is used  in Search::Query
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_query
        # Ensure we have valid content before building duplicate detection query
        unless valid_content?
          GitHub.dogstats.increment("search.duplicate_detection.build_query.invalid_content")
          raise DuplicateDetectionError, "Cannot build duplicate detection query: issue content is not valid for search"
        end

        knn_query = if use_optimized_query?
          log_duplicate_detection_flow("build_query.approach", context: "optimized_query_selected", data: {
            "content_length_limit": use_extended_content_length? ? EXTENDED_MAX_CONTENT_LENGTH : DEFAULT_MAX_CONTENT_LENGTH
          })
          build_optimized_knn_query
        else
          # Use combined embedding (original behavior)
          log_duplicate_detection_flow("build_query.approach", context: "original_query_selected", data: {
            "content_length_limit": MAX_CONTENT_LENGTH
          })
          prepared_text = prepare_text_for_embedding(issue_content.searchable_content, content_limit: MAX_CONTENT_LENGTH)
          if prepared_text.blank?
            GitHub.dogstats.increment("search.duplicate_detection.build_query.empty_content")
            nil
          else
            build_knn_query(prepared_text)
          end
        end

        unless knn_query
          GitHub.dogstats.increment("search.duplicate_detection.build_query.knn_failed")
          raise DuplicateDetectionError, "Failed to build KNN query for duplicate detection"
        end

        # Wrap KNN query in function_score to apply duplicate detection scoring functions
        {
          function_score: {
            query: knn_query,
            functions: DUPLICATE_SCORING_FUNCTIONS,
            boost_mode: "multiply",  # Multiply the KNN score by the function scores
            score_mode: "avg"        # Average function scores to keep them normalized (0-1 range)
          }
        }
      end

      # Build filters specifically for duplicate detection
      def filter
        {
          bool: {
            must: [
              { term: { repo_id: @issue_content.repository_id } },
              { prefix: { _index: "issues" } },
            ]
            # Note: No issue ID exclusion since we're checking against existing issues for duplicates
            # Note: Index prefix filter is manually added since we bypass parent class query building
          }
        }
      end

      # Build a single KNN query component for duplicate detection
      sig { params(text: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_knn_query(text)
        return nil if text.blank?

        # Get embedding vector for the text
        embedding_vector = fetch_embedding_vector(text)
        return nil if embedding_vector.nil?

        # Build KNN queries only for fields with content
        knn_queries = []

        # Add title KNN query if title has content
        if @issue_content.title.present?
          knn_queries << IssueSemanticHelper.build_knn_clause(
            "title_dense_vector",
            query_vector: embedding_vector,
            boost: DUPLICATE_TITLE_WEIGHT,
            filter:,
            k: DUPLICATE_KNN_K,
            num_candidates: DUPLICATE_KNN_CANDIDATES,
            similarity: use_duplicate_threshold
          )
        end

        # Add body KNN query if body has content
        if @issue_content.body.present?
          knn_queries << IssueSemanticHelper.build_knn_clause(
            "body_dense_vector",
            query_vector: embedding_vector,
            boost: DUPLICATE_BODY_WEIGHT,
            filter:,
            k: DUPLICATE_KNN_K,
            num_candidates: DUPLICATE_KNN_CANDIDATES,
            similarity: use_duplicate_threshold
          )
        end

        return nil if knn_queries.empty?

        # If only one query, return it directly. If multiple, wrap in bool.
        if knn_queries.length == 1
          knn_queries.first
        else
          {
            bool: {
              should: knn_queries,
              minimum_should_match: 1
            }
          }
        end
      rescue EmbeddingError => e
        # Log the error but don't fail the entire query for embedding failures
        Failbot.report(e)
        GitHub.dogstats.increment(
          "search.duplicate_detection.build_query.embedding_error",
          tags: ["error_class:#{e.class.name}"]
        )
        log_duplicate_detection_error(e,
          step: "build_knn_query",
          context: "knn_construction",
          data: { "text_length": text.length }
        )
        nil
      end

      # Separate embeddings prevent dilution for title_dense_vector/body_dense_vector
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_optimized_knn_query
        knn_queries = []

        if @issue_content.title.present?
          title_text = prepare_text_for_embedding(T.must(@issue_content.title))
          title_embedding = fetch_embedding_vector(title_text)

          if title_embedding.present?
            knn_queries << IssueSemanticHelper.build_knn_clause(
              "title_dense_vector",
              query_vector: title_embedding,
              boost: DUPLICATE_TITLE_WEIGHT,
              filter:,
              k: DUPLICATE_KNN_K,
              num_candidates: DUPLICATE_KNN_CANDIDATES,
              similarity: use_duplicate_threshold
            )
          end
        end

        if @issue_content.body.present?
          body_text = prepare_text_for_embedding(T.must(@issue_content.cleaned_body))
          body_embedding = fetch_embedding_vector(body_text)

          if body_embedding.present?
            knn_queries << IssueSemanticHelper.build_knn_clause(
              "body_dense_vector",
              query_vector: body_embedding,
              boost: DUPLICATE_BODY_WEIGHT,
              filter:,
              k: DUPLICATE_KNN_K,
              num_candidates: DUPLICATE_KNN_CANDIDATES,
              similarity: use_duplicate_threshold
            )
          end
        end

        return nil if knn_queries.empty?

        # If only one query, return it directly. If multiple, wrap in bool.
        if knn_queries.length == 1
          knn_queries.first
        else
          {
            bool: {
              should: knn_queries,
              minimum_should_match: 1
            }
          }
        end
      rescue EmbeddingError => e
        # Log the error but don't fail the entire query for embedding failures
        Failbot.report(e)
        GitHub.dogstats.increment(
          "search.duplicate_detection.build_query.embedding_error",
          tags: ["error_class:#{e.class.name}", "approach:optimized"]
        )
        log_duplicate_detection_error(e,
          step: "build_optimized_knn_query",
          context: "knn_construction"
        )
        nil
      end

      sig { returns(Float) }
      def use_duplicate_threshold
        duplicate_threshold = if use_query_threshold_for_duplicate_detection?
          @threshold
        else
          DUPLICATE_SIMILARITY_THRESHOLD
        end

        log_duplicate_detection_flow("threshold_selection", context: "threshold_selection", data: {
          "feature_flag": "use_query_threshold_for_duplicate_detection",
          "enabled": use_query_threshold_for_duplicate_detection?,
          "threshold_value": duplicate_threshold
        })

        duplicate_threshold
      end

      sig { returns(T::Boolean) }
      memoize def use_query_threshold_for_duplicate_detection?
        feature_enabled?(:use_query_threshold_for_duplicate_detection, default: false)
      end

      sig { returns(T::Boolean) }
      memoize def use_optimized_query?
        feature_enabled?(:semantic_duplicate_detection_optimized_query)
      end

      sig { returns(T::Boolean) }
      memoize def use_extended_content_length?
        feature_enabled?(:semantic_duplicate_detection_extended_content_length)
      end

      # Prepare text for embedding: sanitize and truncate to safe limits
      # Handles both title and body text with appropriate length limits
      sig { params(text: String, content_limit: T.nilable(Integer)).returns(String) }
      def prepare_text_for_embedding(text, content_limit: nil)
        return "" if text.blank?

        sanitized = ::Search.clean_and_sanitize(text)
        return "" if sanitized.blank?

        if content_limit.present?
          log_duplicate_detection_flow("prepare_text.content_limit", context: "explicit_limit", data: {
            "limit": content_limit,
            "original_length": sanitized.length,
            "truncated": sanitized.length > content_limit
          })

          return sanitized.truncate(content_limit, omission: "")
        end

        max_length = if use_extended_content_length?
          log_duplicate_detection_flow("prepare_text.content_limit", context: "extended_limit", data: {
            "limit": EXTENDED_MAX_CONTENT_LENGTH,
            "original_length": sanitized.length,
            "truncated": sanitized.length > EXTENDED_MAX_CONTENT_LENGTH
          })
          EXTENDED_MAX_CONTENT_LENGTH
        else
          log_duplicate_detection_flow("prepare_text.content_limit", context: "default_limit", data: {
            "limit": DEFAULT_MAX_CONTENT_LENGTH,
            "original_length": sanitized.length,
            "truncated": sanitized.length > DEFAULT_MAX_CONTENT_LENGTH
          })
          DEFAULT_MAX_CONTENT_LENGTH
        end

        sanitized.truncate(max_length, omission: "")
      end

      # Classify confidence level based on similarity score
      sig { params(score: Float).returns(Symbol) }
      def self.classify_duplicate_confidence(score)
        case score
        when 0.95..Float::INFINITY
          :high
        when 0.85..0.95
          :medium
        else
          :low
        end
      end

      # Filter results for high confidence duplicates only (for UI contexts requiring precision)
      sig { params(results: T::Array[DuplicateIssueResult]).returns(T::Array[DuplicateIssueResult]) }
      def self.high_confidence_only(results)
        results.select(&:high_confidence_duplicate?)
      end

      # Log score distribution for threshold validation
      sig { params(scores: T::Array[Float]).void }
      def log_score_distribution(scores)
        return if scores.empty?
        return unless duplicate_detection_logging_enabled?

        log_duplicate_detection_flow("score.distribution", context: "threshold_validation", data: {
          "score.min": scores.min,
          "score.max": scores.max,
          "score.avg": (scores.sum / scores.size.to_f).round(3),
          "score.median": (scores.sort[scores.size / 2] || 0.0).round(3),
          "count.total": scores.size,
          "count.high": scores.count { |s| s >= HIGH_CONFIDENCE_THRESHOLD },
          "count.medium": scores.count { |s| s >= DUPLICATE_SIMILARITY_THRESHOLD && s < HIGH_CONFIDENCE_THRESHOLD },
          "count.low": scores.count { |s| s < DUPLICATE_SIMILARITY_THRESHOLD }
        })
      end

      private

      # Logs duplicate detection processing events and errors with structured data
      #
      # Similar to log_llm_flow but focused on semantic duplicate detection operations.
      # Provides detailed logging behind a feature flag for debugging and monitoring.
      sig do
        params(
          error: T.nilable(StandardError),
          step: String,
          context: String,
          data: T.nilable(T::Hash[String, T.untyped])
        ).void
      end
      def log_duplicate_detection_error(error, step:, context:, data: nil)
        return unless duplicate_detection_logging_enabled?

        log_data = {
          "code.namespace": self.class.name,
          "code.function": "log_duplicate_detection_error",
          "processing.step": step,
          "context": context,
          "timestamp": Time.current.iso8601(3)
        }

        if error
          log_data = log_data.merge(
            "error.message": error.message,
            "error.class": error.class.name,
          )
        end

        if data.present?
          # Merge in the provided data, ensuring we don't override core fields
          safe_data = data.reject { |key, _| log_data.key?(key) }
          log_data = log_data.merge(safe_data)
        end

        GitHub.logger.error(log_data)
      end

      # Logs duplicate detection flow events with structured data
      sig do
        params(
          step: String,
          context: String,
          data: T.nilable(T::Hash[String, T.untyped])
        ).void
      end
      def log_duplicate_detection_flow(step, context:, data: nil)
        return unless duplicate_detection_logging_enabled?

        log_data = {
          "code.namespace": self.class.name,
          "code.function": "log_duplicate_detection_flow",
          "processing.step": step,
          "context": context,
          "timestamp": Time.current.iso8601(3)
        }

        if data.blank?
          log_data = log_data.merge("message": "Duplicate detection flow log - no additional data")
        else
          # Merge in the provided data, ensuring we don't override core fields
          safe_data = data.reject { |key, _| log_data.key?(key) }
          log_data = log_data.merge(safe_data)
        end

        GitHub.logger.info(log_data)
      end

      # Check if duplicate detection logging is enabled
      sig { returns(T::Boolean) }
      memoize def duplicate_detection_logging_enabled?
        feature_enabled?(:semantic_duplicate_detection_logging, default: false)
      end

      # Check if a duplicate detection feature flag is enabled for current context.
      # Returns the provided default if user or repository is missing, otherwise
      # checks the flag against user, repository, and organization actors.
      sig { params(flag_name: Symbol, default: T::Boolean).returns(T::Boolean) }
      def feature_enabled?(flag_name, default: false)
        return default unless @current_user.present?
        return default unless repository.present?

        organization = repository&.organization
        actors = [@current_user, repository, organization].compact
        FeatureFlag.vexi.enabled?(flag_name, actors, default: default)
      end

      # Comprehensive validation of issue content parameter for duplicate detection
      sig { params(content: T.untyped).void }
      def validate_issue_content!(content)
        raise DuplicateDetectionError, "IssueContent cannot be nil" if content.nil?

        unless content.is_a?(IssueContent)
          raise DuplicateDetectionError, "Expected IssueContent struct, got #{content.class}"
        end

        raise DuplicateDetectionError, "repository_id is required for duplicate detection" if content.repository_id.nil?
        raise DuplicateDetectionError, "repository_id must be positive" if content.repository_id <= 0
      end
    end
  end
end
