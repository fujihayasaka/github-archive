# typed: strict
# frozen_string_literal: true

module Issues
  # Type definitions for LLM-assisted duplicate issue detection
  #
  # Structured data types for the duplicate detection pipeline including:
  # - Processing metrics and metadata
  # - LLM classification results
  # - Response formats for API consumption
  # - Input types for both persisted and non-persisted issues
  #
  # Example:
  #   target = TargetIssueData.from_text(title: "App crashes", body: "...")
  #   batch_result = evaluate_batch_duplicates(target: target, candidates: candidates)
  #   summary = serialize_llm_duplicate_results(batch_result)
  module DuplicateDetectionTypes
    # Token usage metrics from LLM API responses
    #
    # Captures token consumption for cost tracking and optimization analysis.
    # Only present when LLM evaluation is enabled and completes successfully.
    # Used for billing analysis, prompt optimization, and capacity planning.
    #
    # Azure OpenAI provides detailed breakdowns including:
    # - Cached tokens (reduce cost)
    # - Reasoning tokens (for O1 models)
    # - Accepted/rejected prediction tokens
    class TokenUsage < T::Struct
      # Number of tokens in the LLM prompt
      const :prompt_tokens, T.nilable(Integer)

      # Number of tokens in the LLM completion response
      const :completion_tokens, T.nilable(Integer)

      # Total tokens used in the LLM request (prompt + completion)
      const :total_tokens, T.nilable(Integer)

      # Number of tokens from cache (reduces cost)
      const :cached_tokens, T.nilable(Integer), default: nil

      # Number of reasoning tokens (for O1 models)
      const :reasoning_tokens, T.nilable(Integer), default: nil

      # Number of accepted prediction tokens
      const :accepted_prediction_tokens, T.nilable(Integer), default: nil

      # Number of rejected prediction tokens
      const :rejected_prediction_tokens, T.nilable(Integer), default: nil
    end

    # Performance metrics for duplicate detection processing
    #
    # Tracks bucketed text lengths and processing time for performance analysis.
    # Text buckets: "1-200", "201-500", "501-1k", "1k-2k", "2k+"
    class ProcessingMetrics < T::Struct
      # Bucketed length of the prompt text sent to LLM (target issue content)
      const :prompt_text_length_bucket, String

      # Bucketed length of all input text (target + all candidate issues)
      const :total_input_length_bucket, String

      # Time spent calculating input text lengths in milliseconds
      const :input_calculation_time_ms, T.any(Integer, Float)

      # End-to-end processing time in milliseconds for the entire operation
      const :processing_time_ms, T.any(Integer, Float)

      # Token usage from LLM API (nil when LLM disabled or on failure)
      const :token_usage, T.nilable(TokenUsage), default: nil
    end

    # Metadata about batch duplicate detection processing
    #
    # Tracks LLM enablement and candidate counts. processed_candidates may be less than
    # total_candidates due to batch limits or errors. When LLM is disabled, both counts
    # are equal (semantic-only evaluation). Critical for understanding result completeness.
    class ProcessingMetadata < T::Struct
      # Whether LLM evaluation was enabled for this batch operation
      const :llm_enabled, T::Boolean

      # Total number of candidate issues provided for evaluation
      const :total_candidates, Integer

      # Number of candidates actually processed (may be less due to limits or errors)
      const :processed_candidates, Integer

      # Detailed processing performance metrics
      const :processing_metrics, ProcessingMetrics
    end

    # Duplicate classification result with confidence scoring
    #
    # Confidence ranges: 0.9-1.0 (very confident), 0.7-0.9 (confident),
    # 0.5-0.7 (somewhat confident), 0.0-0.5 (low confidence).
    # llm_processed flag indicates LLM evaluation vs fallback classification.
    # Fallback behavior: is_duplicate=false, confidence_score=0.0
    class DuplicateClassification < T::Struct
      # Whether the candidate issue is classified as a duplicate of the target
      const :is_duplicate, T::Boolean

      # Confidence score (0.0-1.0) indicating certainty in the classification decision
      const :confidence_score, Float

      # Human-readable explanation of the classification decision (optional)
      const :reasoning, T.nilable(String), default: nil

      # Specific description of the shared root cause (nil if no shared root cause identified)
      const :shared_root_cause, T.nilable(String), default: nil

      # Whether the same fix would resolve both issues (nil if not evaluated)
      const :same_fix, T.nilable(T::Boolean), default: nil

      # Whether distinguishing details were found that prove different problems (nil if not evaluated)
      const :distinguishing_details_found, T.nilable(T::Boolean), default: nil

      # Whether this classification came from LLM analysis (true) or fallback logic (false)
      const :llm_processed, T::Boolean
    end

    # External API result pairing issue ID with duplicate classification
    #
    # Uses issue IDs instead of full objects to keep response payloads lean while providing
    # stable references. Consumers can fetch full issue details separately as needed.
    # Results typically sorted by confidence score (descending) for optimal UX.
    class SingleDuplicateResult < T::Struct
      # Database `issue.id` of the candidate being evaluated
      const :issue_id, Integer

      # Complete classification result for this candidate
      const :duplicate_classification, DuplicateClassification
    end

    # Final API response format combining processing metadata with duplicate results
    #
    # Provides complete context for consumers: metadata explains scope and reliability,
    # results sorted by confidence for optimal UX. Consistent format regardless of
    # processing path (LLM vs fallback). Enables result interpretation, performance
    # tracking, and informed follow-up decisions.
    class DuplicateResultSummary < T::Struct
      # Metadata about how the duplicate detection batch was processed
      const :processing_metadata, ProcessingMetadata

      # Array of individual duplicate classification results, typically sorted by confidence
      const :duplicates, T::Array[SingleDuplicateResult]
    end

    # Internal result pairing semantic search data with LLM classifications
    #
    # Unlike SingleDuplicateResult (external, ID-only), retains full SimilarIssueResult
    # context including semantic scores, issue details, and search ranking. Enables
    # score correlation analysis, performance optimization, and detailed metrics collection.
    class Result < T::Struct
      # Complete search result including semantic similarity data
      const :issue, Search::Queries::SimilarIssueResult

      # Duplicate classification result for this candidate
      const :classification, DuplicateClassification
    end

    # Batch processing output before external serialization
    #
    # Contains full Result objects with semantic context plus processing metadata for
    # metrics, debugging, and response construction. Maintains 1:1 results-to-candidates
    # correspondence with fallback classifications for unprocessed items. Consumed by
    # serialization, telemetry, and correlation analysis.
    class BatchResult < T::Struct
      # Array of individual candidate evaluation results with full context
      const :results, T::Array[Result]

      # Whether LLM evaluation was enabled for this batch
      const :llm_enabled, T::Boolean

      # LLM model used or attempted for evaluation (e.g., "gpt-4-0613"); defaults to "unknown" when unavailable
      const :model, String, default: "unknown"

      # Total number of candidates provided for evaluation
      const :total_candidates, Integer

      # Number of candidates successfully processed (may be limited by batch size or errors)
      const :processed_candidates, Integer

      # Detailed processing performance metrics
      const :processing_metrics, ProcessingMetrics
    end

    # Typed interface for async Promise-based LLM evaluation results
    #
    # Replaces hash-based returns with structured data for compile-time type safety.
    # Used in Promise chains to handle success/failure states with proper error handling.
    # Success: populated results and processed_count. Failure: empty results with error details.
    class AsyncEvaluationResult < T::Struct
      # Whether the async operation completed successfully
      const :success, T::Boolean

      # Array of evaluation results (empty on failure)
      const :results, T::Array[Result], default: []

      # Number of candidates successfully processed (0 on failure)
      const :processed_count, Integer, default: 0

      # Error details if operation failed (nil on success)
      const :error, T.nilable(StandardError), default: nil

      # Token usage from LLM API response (nil on failure or when unavailable)
      # Values can be Integer (token counts) or nested Hash (details like completion_tokens_details)
      const :usage, T.nilable(T::Hash[String, T.any(Integer, T::Hash[String, Integer])]), default: nil
    end

    # Unified interface for both persisted Issues and pre-creation raw text inputs
    #
    # Optional metadata fields enable LLM to adapt analysis approach: full contextual
    # analysis with metadata (persisted issues) or content-focused similarity (raw text).
    # Factory methods: from_issue() for persisted objects, from_text() for raw content.
    # Supports duplicate prevention in forms, post-creation analysis, and bulk imports.
    class TargetIssueData < T::Struct
      # Issue title text (always present for both persisted and non-persisted issues)
      const :title, String

      # Issue body text (optional, may be nil for title-only issues)
      const :body, T.nilable(String)

      # Issue state ("open", "closed") - only present for persisted issues
      const :state, T.nilable(String), default: nil

      # Issue creation timestamp - only present for persisted issues
      const :created_at, T.nilable(Time), default: nil

      # GitHub issue number - only present for persisted issues
      const :number, T.nilable(Integer), default: nil

      # Factory method extracting content and metadata from persisted Issue objects
      #
      # Includes full context (title, body, state, created_at, number) for comprehensive
      # duplicate analysis. Used for post-creation analysis and existing issue workflows.
      sig { params(issue: Issue).returns(TargetIssueData) }
      def self.from_issue(issue)
        new(
          title: issue.title,
          body: issue.body_text,
          state: issue.state,
          created_at: issue.created_at,
          number: issue.number
        )
      end

      # Factory method creating content-only data from raw title/body strings
      #
      # Sets metadata fields to nil for content-focused similarity analysis without
      # temporal factors. Used for pre-creation duplicate prevention in forms,
      # API endpoints, and bulk import processes.
      sig { params(title: String, body: T.nilable(String)).returns(TargetIssueData) }
      def self.from_text(title:, body: nil)
        new(
          title:,
          body:,
          state: nil,
          created_at: nil,
          number: nil
        )
      end
    end

    # Parsed LLM response containing evaluation results and token usage
    #
    # Internal data structure for passing parsed LLM API responses through the processing
    # pipeline. Separates results array from raw usage metrics for clear data flow and
    # type safety. Usage hash contains raw token counts from the LLM API response when
    # available, useful for cost tracking and optimization analysis.
    class ParsedLlmResponse < T::Struct
      # Array of evaluation results for each candidate
      const :results, T::Array[Result], default: []

      # Raw token usage hash from LLM API response (nil if unavailable)
      # Contains token counts (Integer) and nested detail hashes (e.g., completion_tokens_details)
      # Example: {"prompt_tokens" => 1680, "completion_tokens_details" => {"cached_tokens" => 0}}
      const :usage, T.nilable(T::Hash[String, T.any(Integer, T::Hash[String, Integer])]), default: nil
    end

    # Metrics analyzing how LLM re-ranking changes candidate ordering
    #
    # Captures the impact of LLM confidence-based ranking compared to original semantic
    # similarity ordering. Used for performance analysis, correlation studies, and
    # tuning decisions. Supports both raw metrics (for statistical analysis) and
    # bucketed tags (for intuitive filtering in observability dashboards).
    class RerankingMetrics < T::Struct
      # Average absolute position change across all candidates
      const :mean_rank_change, Float

      # Largest position change among all candidates
      const :max_rank_change, Float

      # Kendall's tau correlation coefficient (-1.0 to 1.0) between semantic and LLM rankings
      const :rank_correlation, Float

      # Number of candidates that moved to higher positions in LLM ranking
      const :movement_up_count, Integer

      # Number of candidates that moved to lower positions in LLM ranking
      const :movement_down_count, Integer

      # Number of candidates that remained in the same position
      const :movement_unchanged_count, Integer
    end
  end
end
