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
    # Performance metrics for duplicate detection processing
    #
    # Tracks bucketed text lengths and processing time for performance analysis.
    # Text buckets: "1-200", "201-500", "501-1k", "1k-2k", "2k+"
    class ProcessingMetrics < T::Struct
      # Bucketed length of the prompt text sent to LLM (target issue content)
      const :prompt_text_length_bucket, String

      # Bucketed length of all input text (target + all candidate issues)
      const :total_input_length_bucket, String

      # End-to-end processing time in milliseconds for the entire operation
      const :processing_time_ms, Float
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
      const :reasoning, T.nilable(String)

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
      const :results, T::Array[Result]

      # Number of candidates successfully processed (0 on failure)
      const :processed_count, Integer

      # Error details if operation failed (nil on success)
      const :error, T.nilable(StandardError)
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
  end
end
