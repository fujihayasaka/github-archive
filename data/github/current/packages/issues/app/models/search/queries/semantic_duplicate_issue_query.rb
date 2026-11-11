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
    # - Higher confidence thresholds than general search (0.85 vs 0.8, 0.92 for high-precision contexts)
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
      DEFAULT_DUPLICATE_THRESHOLD = 0.85    # Higher than general search (0.8)
      HIGH_CONFIDENCE_THRESHOLD   = 0.92    # For UI contexts requiring high precision
      DUPLICATE_TITLE_WEIGHT      = 2.5     # Slightly higher weight for title matching
      DUPLICATE_BODY_WEIGHT       = 2.0     # Higher weight for body matching
      MAX_CONTENT_LENGTH          = 1000    # Extended context for comprehensive duplicate detection

      # KNN parameters optimized for duplicate detection
      DUPLICATE_KNN_K = 20                  # Fewer results, higher precision
      DUPLICATE_KNN_CANDIDATES = 2000       # Smaller candidate pool for faster, focused results
      DUPLICATE_SIMILARITY_THRESHOLD = 0.75 # Higher minimum similarity for duplicate detection

      # Elasticsearch timeout optimized for duplicate detection
      DUPLICATE_QUERY_TIMEOUT = "1500ms"    # Matches increased timeout, shorter than SemanticSimilarIssueQuery (2000ms)
      DUPLICATE_READ_TIMEOUT  = 2.5         # Shorter read timeout

      # Scoring function definitions for duplicate detection
      DUPLICATE_SCORING_FUNCTIONS = [
        # Primary signal: Recent activity (comments, reactions, etc.)
        {
          exp: {
            updated_at: {
              scale: "14d",   # Half-life of 14 days for activity decay
              decay: 0.5,     # 50% score reduction at 14 days
              offset: "0d"    # No offset, immediate decay from now
            }
          }
        },
        # Secondary signal: Recent creation with gentler decay
        {
          exp: {
            created_at: {
              scale: "90d",   # Extended candidate pool for canonical issues
              decay: 0.3      # Gentler decay to preserve older canonical issues
            }
          }
        },
        # Tertiary signal: Activity engagement level
        {
          field_value_factor: {
            field: "num_reactions",
            factor: 1.2,
            modifier: "log1p",
            missing: 1
          }
        }
      ].freeze

      sig { returns(IssueContent) }
      attr_reader :issue_content

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

        # Returns a clean, searchable text representation
        sig { returns(String) }
        def searchable_text
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

      # Instantiates SemanticDuplicateIssueQuery for duplicate detection.
      # The query will use pure KNN evaluation with high confidence thresholds
      # to identify potential duplicates of the provided content.
      #
      # opts - The options Hash.
      #   :issue_content - The IssueContent struct containing title, body, and repository_id
      #   :threshold - The minimum score threshold for duplicate detection (default: 0.85)
      sig  { params(opts: T::Hash[Symbol, T.untyped]).void }
      def initialize(opts = {})
        @current_user = T.let(opts.fetch(:current_user, nil), T.nilable(::User))
        issue_content_param = opts.fetch(:issue_content)

        validate_issue_content!(issue_content_param)
        @issue_content = T.let(issue_content_param, IssueContent)

        # Validate content quality for duplicate detection
        unless @issue_content.valid_for_search?
          GitHub.dogstats.increment("search.duplicate_detection.invalid_content")
          raise DuplicateDetectionError, "Content must have either a title or body for duplicate detection"
        end

        @threshold = T.let(opts[:threshold] || DEFAULT_DUPLICATE_THRESHOLD, Float)

        # Set up opts for IssueQuery parent class
        parent_opts = opts.merge(
          type: "issues",
          repo_id: @issue_content.repository_id,  # Parent sets @repo_id for routing optimization
          quote_words: false  # Disable quote processing for content matching
        )

        # Remove our custom params that are not relevant to the parent class
        parent_opts.delete(:issue_content)
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
          repository_id: T.nilable(Integer),
          current_user: T.nilable(::User),
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_similar_to_content(title:, body:, repository_id:, current_user:, threshold: nil, per_page: nil, page: nil, context: nil, **kwargs)
        # Early validation and return for duplicate detection
        return [] if repository_id.nil?
        return [] if title.blank? && body.blank?

        # Use factory method for better error handling in duplicate detection
        issue_content = create_issue_content(title:, body:, repository_id:)
        return [] if issue_content.nil?

        begin
          query = self.new(issue_content:, current_user:, threshold:, per_page:, page:, context:, **kwargs)
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
          repository_id: T.nilable(Integer),
          current_user: T.nilable(::User),
          high_confidence: T::Boolean,
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_potential_duplicates_with_context(title:, body:, repository_id:, current_user:, high_confidence: false, threshold: nil, per_page: nil, page: nil, context: nil, **kwargs)
        effective_threshold = if high_confidence
          HIGH_CONFIDENCE_THRESHOLD
        else
          threshold || DEFAULT_DUPLICATE_THRESHOLD
        end

        # T.unsafe: Sorbet limitation with **kwargs and required keyword params.
        # Safe - all required params explicitly passed, only overriding threshold.
        results = T.unsafe(self).find_similar_to_content(
          title:,
          body:,
          repository_id:,
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
          repository_id: T.nilable(Integer),
          current_user: T.nilable(::User),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String)
        ).returns(T::Array[DuplicateIssueResult])
      end
      def self.find_high_confidence_duplicates(title:, body:, repository_id:, current_user:, per_page: nil, page: nil, context: nil)
        # Call find_similar_to_content with high confidence threshold and filter results
        T.unsafe(self).find_potential_duplicates_with_context(
          title:,
          body:,
          repository_id:,
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

      # Override to use issue_content.body with duplicate detection optimizations
      def body_query
        return @body_query if defined?(@body_query)

        body_text = @issue_content.body.to_s.strip
        # Use larger context for duplicate detection
        @body_query = if body_text.length > MAX_CONTENT_LENGTH
          body_text.truncate(MAX_CONTENT_LENGTH, omission: "")
        else
          body_text
        end

        @body_query
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

        # Use sanitized and truncated search content for embedding - pure KNN approach
        if searchable_content.blank?
          GitHub.dogstats.increment("search.duplicate_detection.build_query.empty_content")
          raise DuplicateDetectionError, "No valid content available for duplicate detection"
        end

        knn_query = build_knn_query(searchable_content)
        unless knn_query
          GitHub.dogstats.increment(
            "search.duplicate_detection.build_query.knn_failed",
            tags: ["content_length_bucket:#{length_bucket(searchable_content.length)}"]
          )
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
          knn_queries << {
            knn: {
              field: "title_dense_vector",
              query_vector: embedding_vector,
              boost: DUPLICATE_TITLE_WEIGHT,
              filter:,
              k: DUPLICATE_KNN_K,
              num_candidates: DUPLICATE_KNN_CANDIDATES,
              similarity: DUPLICATE_SIMILARITY_THRESHOLD
            }
          }
        end

        # Add body KNN query if body has content
        if @issue_content.body.present?
          knn_queries << {
            knn: {
              field: "body_dense_vector",
              query_vector: embedding_vector,
              boost: DUPLICATE_BODY_WEIGHT,
              filter:,
              k: DUPLICATE_KNN_K,
              num_candidates: DUPLICATE_KNN_CANDIDATES,
              similarity: DUPLICATE_SIMILARITY_THRESHOLD
            }
          }
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
          "count.medium": scores.count { |s| s >= DEFAULT_DUPLICATE_THRESHOLD && s < HIGH_CONFIDENCE_THRESHOLD },
          "count.low": scores.count { |s| s < DEFAULT_DUPLICATE_THRESHOLD }
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
      def duplicate_detection_logging_enabled?
        return false unless @current_user.present?

        # Get repository and org for feature flag context
        repository = Repository.find_by(id: @issue_content.repository_id)
        return false unless repository.present?

        organization = repository.organization
        actors = [@current_user, repository, organization].compact

        # Check feature flag against user, repo, and org
        FeatureFlag.vexi.enabled?(:semantic_duplicate_detection_logging, actors, default: false)
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

      memoize def searchable_content
        # Use the optimized searchable_text method from IssueContent
        text = @issue_content.searchable_text
        sanitized = ::Search.clean_and_sanitize(text)
        sanitized.truncate(MAX_CONTENT_LENGTH, omission: "")
      end

      # Convert numeric values to low-cardinality buckets for metrics
      sig { params(length: Integer).returns(String) }
      def length_bucket(length)
        case length
        when 0..9
          "0-9"
        when 10..49
          "10-49"
        when 50..199
          "50-199"
        when 200..499
          "200-499"
        else
          "500+"
        end
      end
    end
  end
end
