# typed: strict
# frozen_string_literal: true

module Issues
  # Instrumentation and observability for LLM-assisted duplicate detection
  #
  # This module provides metrics tracking, logging, and analysis
  # for duplicate detection operations. It separates observability concerns from
  # core LLM evaluation logic, making both easier to maintain and test.
  #
  # Responsibilities:
  # - Metrics bucketing (similarity scores, confidence scores, text lengths)
  # - Processing metrics instrumentation (timing, counts, success rates)
  # - Re-ranking analysis (position changes, correlations)
  # - Score correlation tracking (semantic vs LLM confidence)
  # - Structured logging for debugging and analysis
  # - Error tracking and reporting
  module DuplicateDetectionLlmInstrumentation
    extend T::Helpers
    include DuplicateDetectionTypes

    requires_ancestor { AbstractRepositoryController }

    abstract!

    sig { abstract.returns(Repository) }
    def current_repository; end

    sig { abstract.returns(T.nilable(User)) }
    def current_user; end

    # Buckets similarity score into coarse ranges for metrics analysis
    #
    # This method enables analysis of semantic search score distributions and correlation
    # with LLM confidence scores. Bucketed scores prevent high-cardinality metrics while
    # still providing meaningful insights for performance analysis.
    #
    # Note: Elasticsearch _score is not normalized to [0,1] and can exceed 1.0 depending
    # on the query and document relevance. We explicitly separate normalized high scores
    # (0.8-1.0) from unnormalized ES scores (>=1.0) to distinguish typical high-confidence
    # matches from exceptional relevance scores.
    #
    # Score Ranges (semantic similarity from Elasticsearch):
    # - "0.0-0.2": Very low similarity [0.0, 0.2)
    # - "0.2-0.4": Low similarity [0.2, 0.4)
    # - "0.4-0.6": Medium similarity [0.4, 0.6)
    # - "0.6-0.8": High similarity [0.6, 0.8)
    # - "0.8-1.0": Very high similarity [0.8, 1.0) - normalized range
    # - ">=1.0": Exceptional ES scores [1.0, ∞) - unnormalized range
    # - "null": No score available
    #
    # Usage:
    #   bucket_similarity_score(0.15)  # => "0.0-0.2"
    #   bucket_similarity_score(0.75)  # => "0.6-0.8"
    #   bucket_similarity_score(0.95)  # => "0.8-1.0"
    #   bucket_similarity_score(1.5)   # => ">=1.0"
    #   bucket_similarity_score(nil)   # => "null"
    #
    sig { params(score: T.nilable(Float)).returns(String) }
    def bucket_similarity_score(score)
      return "null" if score.nil?

      if score < 0.2
        "0.0-0.2"
      elsif score < 0.4
        "0.2-0.4"
      elsif score < 0.6
        "0.4-0.6"
      elsif score < 0.8
        "0.6-0.8"
      elsif score < 1.0
        "0.8-1.0"
      else
        ">=1.0"
      end
    end

    # Buckets confidence score into coarse ranges for metrics analysis
    #
    # This method enables analysis of LLM confidence score distributions and correlation
    # with semantic similarity scores. Bucketed scores prevent high-cardinality metrics
    # while still providing actionable insights for performance tuning.
    #
    # The confidence score represents the LLM's certainty in its duplicate classification
    # decision. Higher scores indicate greater confidence, while lower scores suggest
    # the LLM found the decision more ambiguous. Uses half-open ranges [a, b) to avoid
    # boundary ambiguity, with the final bucket capturing all high-confidence decisions.
    #
    # Score Ranges (LLM confidence from duplicate detection):
    # - "0.0-0.2": Very low confidence (highly uncertain decisions) [0.0, 0.2)
    # - "0.2-0.4": Low confidence (uncertain decisions) [0.2, 0.4)
    # - "0.4-0.6": Medium confidence (moderately certain decisions) [0.4, 0.6)
    # - "0.6-0.8": High confidence (fairly certain decisions) [0.6, 0.8)
    # - "0.8+": Very high confidence (highly certain decisions) [0.8, 1.0]
    #
    # Usage:
    #   bucket_confidence_score(0.15)  # => "0.0-0.2"
    #   bucket_confidence_score(0.85)  # => "0.8+"
    #
    sig { params(score: Float).returns(String) }
    def bucket_confidence_score(score)
      case score
      when 0.0...0.2
        "0.0-0.2"
      when 0.2...0.4
        "0.2-0.4"
      when 0.4...0.6
        "0.4-0.6"
      when 0.6...0.8
        "0.6-0.8"
      else
        "0.8+"
      end
    end

    # Buckets text length into coarse ranges for metrics analysis
    #
    # This method is critical for telemetry and performance analysis of LLM processing.
    # Rather than tracking exact character counts (which would create thousands of unique
    # metric tags), we bucket text lengths into manageable ranges that still provide
    # meaningful insights for performance correlation.
    #
    # The bucketing serves multiple purposes:
    # 1. **Metrics Safety**: Prevents high-cardinality tags that could overwhelm DataDog
    # 2. **Performance Analysis**: Enables correlation between input size and processing time
    # 3. **Resource Planning**: Helps identify patterns in typical issue text lengths
    # 4. **Cost Optimization**: Allows tracking of LLM token usage patterns
    #
    # Bucket Ranges (aligned with MAX_ISSUE_BODY_LENGTH processing limit):
    # - "1-200": Short issues (titles + brief descriptions)
    # - "201-400": Medium issues (typical bug reports)
    # - "401-700": Long issues (detailed feature requests)
    # - "701-1k": Very long issues (comprehensive reports)
    # - "1k+": Extremely long issues (require truncation)
    #
    # Usage:
    #   bucket_text_length(150)   # => "1-200"
    #   bucket_text_length(300)   # => "201-400"
    #   bucket_text_length(500)   # => "401-700"
    #   bucket_text_length(800)   # => "701-1k"
    #   bucket_text_length(1200)  # => "1k+"
    #
    sig { params(text_length: Integer).returns(String) }
    def bucket_text_length(text_length)
      case text_length
      when 0..200
        "1-200"
      when 201..400
        "201-400"
      when 401..700
        "401-700"
      when 701..1000
        "701-1k"
      else
        "1k+"
      end
    end

    # Buckets average rank change into interpretable impact levels
    #
    # This method converts numeric rank change values (average absolute position changes)
    # into meaningful categories for easier analysis and alerting in DataDog. Rather than
    # requiring knowledge of what "rank change of 2.5" means, tags like "reranking_impact:moderate"
    # provide immediate context.
    #
    # Impact Levels:
    # - "minimal": 0-1 positions (LLM ranking very similar to semantic search)
    # - "low": 1-2.5 positions (minor reordering)
    # - "moderate": 2.5-5 positions (noticeable reordering)
    # - "high": 5+ positions (significant reordering)
    #
    # Usage:
    #   bucket_rank_change(0.5)   # => "minimal"
    #   bucket_rank_change(2.0)   # => "low"
    #   bucket_rank_change(3.5)   # => "moderate"
    #   bucket_rank_change(6.0)   # => "high"
    #
    sig { params(mean_change: Float).returns(String) }
    def bucket_rank_change(mean_change)
      case mean_change
      when 0.0...1.0
        "minimal"
      when 1.0...2.5
        "low"
      when 2.5...5.0
        "moderate"
      else
        "high"
      end
    end

    # Buckets Kendall's tau correlation into interpretable agreement levels
    #
    # This method converts correlation coefficients into meaningful categories that
    # describe how well semantic search rankings align with LLM rankings. Instead of
    # interpreting raw tau values, tags like "ranking_agreement:strong" provide clear insights.
    #
    # Kendall's tau ranges from -1 (perfect disagreement) to +1 (perfect agreement):
    #
    # Agreement Levels:
    # - "strong_disagreement": -1.0 to -0.5 (rankings are reversed)
    # - "weak_disagreement": -0.5 to -0.2 (rankings somewhat oppose)
    # - "no_correlation": -0.2 to 0.2 (rankings unrelated)
    # - "weak_agreement": 0.2 to 0.5 (rankings somewhat align)
    # - "moderate_agreement": 0.5 to 0.8 (rankings fairly aligned)
    # - "strong_agreement": 0.8 to 1.0 (rankings nearly identical)
    #
    # Usage:
    #   bucket_rank_correlation(-0.6)  # => "strong_disagreement"
    #   bucket_rank_correlation(0.1)   # => "no_correlation"
    #   bucket_rank_correlation(0.65)  # => "moderate_agreement"
    #   bucket_rank_correlation(0.95)  # => "strong_agreement"
    #
    sig { params(correlation: Float).returns(String) }
    def bucket_rank_correlation(correlation)
      case correlation
      when -1.0...-0.5
        "strong_disagreement"
      when -0.5...-0.2
        "weak_disagreement"
      when -0.2...0.2
        "no_correlation"
      when 0.2...0.5
        "weak_agreement"
      when 0.5...0.8
        "moderate_agreement"
      else
        "strong_agreement"
      end
    end

    # Returns repository visibility as a string for metrics tagging
    sig { returns(String) }
    def repo_visibility_tag
      current_repository.private? ? "private" : "public"
    end

    # Feature flag to control detailed LLM response logging for debugging
    sig { returns(T::Boolean) }
    def duplicate_detection_logging_enabled?
      FeatureFlag.vexi.enabled?(:llm_duplicate_detection_response_logging, current_repository, current_repository.owner, current_user, default: false)
    end

    # Feature flag to control detailed LLM raw choice logging for debugging
    sig { returns(T::Boolean) }
    def duplicate_detection_raw_choice_logging_enabled?
      FeatureFlag.vexi.enabled?(:llm_duplicate_detection_raw_choice_logging, current_repository, current_repository.owner, current_user, default: false)
    end

    # Logs raw processing data and execution flow for debugging and analysis
    #
    # This method provides flexible logging for capturing detailed execution flow,
    # raw data inputs/outputs, and processing steps throughout the duplicate detection
    # pipeline. It's designed to be placed at various points in the processing flow
    # to track data transformations, intermediate results, and execution progress.
    sig do
      params(
        step: String,
        context: String,
        data: T.nilable(T::Hash[String, T.untyped]),
      ).void
    end
    def log_llm_flow(step, context:, data: nil)
      return unless duplicate_detection_logging_enabled?

      log_data = {
        "code.namespace": self.class.name,
        "code.function": "log_llm_flow",
        "processing.step": step,
        "context": context,
        "repo_visibility": repo_visibility_tag,
        "timestamp": Time.current.iso8601(3)
      }

      if data.blank?
        log_data = log_data.merge("message": "LLM flow log - no additional data")
      else
        # Merge in the provided data, ensuring we don't override core fields
        safe_data = data.reject { |key, _| log_data.key?(key) }
        log_data = log_data.merge(safe_data)
      end

      GitHub.logger.info(log_data)
    end

    # Logs and reports LLM duplicate detection errors with metrics tracking
    sig { params(error: StandardError, context: T.untyped, reason: String).void }
    def log_llm_error(error, context:, reason:)
      if duplicate_detection_logging_enabled?
        GitHub.logger.error("issues.duplicate_detection.llm_error",
          "error.message": error.message,
          "code.namespace": self.class.name,
          "code.function": "log_llm_error",
          "context": context,
          "reason": reason,
        )
      end

      GitHub.dogstats.increment("issues.duplicate_detection.llm_error",
        tags: [
          "context:#{context}",
          "error:#{error.class.name}",
          "repo_visibility:#{repo_visibility_tag}",
          "has_user:#{current_user.present?}"
        ]
      )

      Failbot.report(error,
        "context": context,
        "reason": reason,
        "code.namespace": self.class.name,
        "code.function": "log_llm_error",
      )
    end

    # Tracks processing metrics for LLM-assisted duplicate detection.
    #
    # This method instruments key metrics for duplicate detection operations and,
    # when the LLM path is enabled, captures both Elasticsearch semantic similarity
    # scores and LLM results to support correlation analysis.
    #
    # The collected data is intended to inform future tuning decisions, such as
    # confidence-based gating (e.g., when ES scores alone are sufficient to bypass
    # the LLM) and cost / latency optimization.
    #
    # Metrics tracked:
    # - End-to-end processing time
    # - Total and processed candidate counts
    # - Duplicate detection outcomes
    # - Semantic score Vs. LLM results correlation (when LLM is enabled)
    #
    # All metrics are tagged with contextual information to enable detailed analysis
    # by repository, feature flag status, and input size characteristics.
    sig do
      params(
        batch_result: BatchResult,
        context: String,
      ).void
    end
    def instrument_processing_metrics(batch_result, context:)
      tags = build_instrumentation_tags(
        context:,
        llm_enabled: batch_result.llm_enabled,
        llm_model: batch_result.model,
        prompt_text_length_bucket: batch_result.processing_metrics.prompt_text_length_bucket,
        total_input_length_bucket: batch_result.processing_metrics.total_input_length_bucket
      )

      # Processing time metrics
      GitHub.dogstats.histogram("issues.duplicate_detection.processing_time_ms", batch_result.processing_metrics.processing_time_ms, tags: tags)
      GitHub.dogstats.histogram("issues.duplicate_detection.input_calculation_time_ms", batch_result.processing_metrics.input_calculation_time_ms, tags: tags)

      # Candidate counts
      GitHub.dogstats.histogram("issues.duplicate_detection.total_candidates", batch_result.total_candidates, tags:)
      GitHub.dogstats.histogram("issues.duplicate_detection.processed_candidates", batch_result.processed_candidates, tags:)

      # Success rate
      total = batch_result.total_candidates
      success_rate = total.zero? ? 0 : batch_result.processed_candidates.to_f / total
      GitHub.dogstats.histogram("issues.duplicate_detection.success_rate", success_rate, tags:)

      # Token usage metrics for cost tracking and optimization
      if batch_result.llm_enabled
        if batch_result.processing_metrics.token_usage.present?
          token_usage = T.must(batch_result.processing_metrics.token_usage)

          # Basic token counts
          prompt_tokens = token_usage.prompt_tokens
          completion_tokens = token_usage.completion_tokens
          total_tokens = token_usage.total_tokens

          GitHub.dogstats.histogram("issues.duplicate_detection.prompt_tokens", prompt_tokens, tags:) if prompt_tokens
          GitHub.dogstats.histogram("issues.duplicate_detection.completion_tokens", completion_tokens, tags:) if completion_tokens
          GitHub.dogstats.histogram("issues.duplicate_detection.total_tokens", total_tokens, tags:) if total_tokens

          # Detailed token breakdowns (Azure OpenAI specific)
          cached_tokens = token_usage.cached_tokens
          reasoning_tokens = token_usage.reasoning_tokens
          accepted_prediction_tokens = token_usage.accepted_prediction_tokens
          rejected_prediction_tokens = token_usage.rejected_prediction_tokens

          GitHub.dogstats.histogram("issues.duplicate_detection.cached_tokens", cached_tokens, tags:) if cached_tokens
          GitHub.dogstats.histogram("issues.duplicate_detection.reasoning_tokens", reasoning_tokens, tags:) if reasoning_tokens
          GitHub.dogstats.histogram("issues.duplicate_detection.accepted_prediction_tokens", accepted_prediction_tokens, tags:) if accepted_prediction_tokens
          GitHub.dogstats.histogram("issues.duplicate_detection.rejected_prediction_tokens", rejected_prediction_tokens, tags:) if rejected_prediction_tokens
        end

        # LLM-specific metrics
        llm_processed_count = batch_result.results.count { |result| result.classification.llm_processed }
        duplicate_count = batch_result.results.count { |result| result.classification.is_duplicate }

        GitHub.dogstats.histogram("issues.duplicate_detection.llm_processed_count", llm_processed_count, tags:)
        GitHub.dogstats.histogram("issues.duplicate_detection.duplicates_found", duplicate_count, tags:)

        # Delegate to specialized score correlation analysis
        instrument_score_correlation_metrics(batch_result, tags:)

        # Track re-ranking effectiveness (always log, even if zeros - indicates no scored results)
        reranking_metrics = calculate_reranking_metrics(batch_result.results)
        log_reranking_results(batch_result.results, reranking_metrics, context:)
        instrument_reranking_metrics(reranking_metrics, tags:)
      end
    end

    # Calculates re-ranking metrics by comparing semantic search order to LLM-reranked order.
    #
    # This method analyzes how LLM evaluation changes the candidate ranking compared to
    # the original semantic similarity ordering. The metrics help answer:
    # - How much does LLM re-ranking change candidate order?
    # - Which candidates move up/down significantly?
    # - What's the correlation between semantic scores and LLM confidence?
    #
    # Returns a RerankingMetrics struct with:
    # - mean_rank_change: Average absolute position change
    # - max_rank_change: Largest position change
    # - rank_correlation: Kendall's tau correlation coefficient
    # - movement_up_count: Candidates that moved up
    # - movement_down_count: Candidates that moved down
    # - movement_unchanged_count: Candidates that stayed in same position
    #
    sig do
      params(
        results: T::Array[Result]
      ).returns(RerankingMetrics)
    end
    def calculate_reranking_metrics(results)
      # Filter to only LLM-processed results with semantic scores
      scored_results = results.select do |result|
        result.classification.llm_processed && result.issue.score.present?
      end

      # Return default values if no scored results
      return RerankingMetrics.new(
        mean_rank_change: 0.0,
        max_rank_change: 0.0,
        rank_correlation: 0.0,
        movement_up_count: 0,
        movement_down_count: 0,
        movement_unchanged_count: 0
      ) if scored_results.empty?

      llm_ranks = {}
      semantic_ranks = {}

      # Create semantic order (original ES ranking by score)
      semantic_ordered = scored_results.sort_by { |r| -T.must(r.issue.score) }.map(&:issue)

      # Create LLM order (re-ranked by confidence)
      llm_ordered = scored_results.sort_by { |r| -r.classification.confidence_score }.map(&:issue)

      # Precompute rank mappings for O(1) lookup (same pattern as calculate_kendalls_tau)
      semantic_ordered.each_with_index { |result, rank| semantic_ranks[result.issue.id] = rank }
      llm_ordered.each_with_index { |result, rank| llm_ranks[result.issue.id] = rank }

      # Calculate position changes
      rank_changes = []
      movement_up = 0
      movement_down = 0
      movement_unchanged = 0

      scored_results.each do |result|
        issue_id = result.issue.issue.id
        semantic_rank = semantic_ranks[issue_id]
        llm_rank = llm_ranks[issue_id]

        next unless semantic_rank && llm_rank

        rank_change = semantic_rank - llm_rank
        rank_changes << rank_change.abs

        if rank_change.positive?
          movement_up += 1
        elsif rank_change.negative?
          movement_down += 1
        else
          movement_unchanged += 1
        end
      end

      # Calculate Kendall's tau correlation
      correlation = calculate_kendalls_tau(semantic_ordered, llm_ordered)

      RerankingMetrics.new(
        mean_rank_change: (rank_changes.empty? ? 0.0 : (rank_changes.sum.to_f / rank_changes.size).round(2)).to_f,
        max_rank_change: rank_changes.empty? ? 0.0 : rank_changes.max.to_f,
        rank_correlation: correlation,
        movement_up_count: movement_up,
        movement_down_count: movement_down,
        movement_unchanged_count: movement_unchanged
      )
    end

    # Calculates Kendall's tau correlation coefficient between two rankings.
    #
    # Kendall's tau measures the similarity between two orderings, ranging from -1 to 1:
    # - 1.0: Perfect agreement (identical rankings)
    # - 0.0: No correlation
    # - -1.0: Perfect disagreement (reversed rankings)
    #
    # This method expects both arrays to contain the same items (just in different orders),
    # as it's called with semantic_ordered and llm_ordered which are both derived from
    # the same **scored_results** array.
    #
    # Implementation is O(n^2) by precomputing rank lookups rather than repeatedly
    # scanning arrays inside the nested pair loop. This is sufficient for duplicate
    # detection which typically processes 5-20 candidates. While O(n log n) algorithms
    # exist (via merge sort inversion counting), they add significant complexity for
    # negligible performance gain at this scale (n=20 → ~190 comparisons vs ~60).
    #
    sig do
      params(
        order1: T::Array[Search::Queries::SimilarIssueResult],
        order2: T::Array[Search::Queries::SimilarIssueResult]
      ).returns(Float)
    end
    def calculate_kendalls_tau(order1, order2)
      n = order1.length

      # Edge cases
      return 0.0 if n.zero?
      return 1.0 if n == 1 # Single item = perfect agreement (no reordering possible)

      # Precompute rank mapping for order2 (issue_id -> rank)
      # For order1, we can use i/j directly since we're iterating in order
      order2_ranks = {}
      order2.each_with_index do |result, rank|
        order2_ranks[result.issue.id] = rank
      end

      # Count concordant and discordant pairs
      concordant = 0
      discordant = 0

      (0...n).each do |i|
        ((i + 1)...n).each do |j|
          id_i = T.must(order1[i]).issue.id
          id_j = T.must(order1[j]).issue.id

          # Ranks in order1 are simply i and j (since we iterate in order)
          rank1_i = i
          rank1_j = j

          # Look up ranks in order2 from precomputed hash
          rank2_i = order2_ranks[id_i]
          rank2_j = order2_ranks[id_j]

          next unless rank2_i && rank2_j

          sign1 = (rank1_i - rank1_j) <=> 0
          sign2 = (rank2_i - rank2_j) <=> 0

          if sign1 == sign2
            concordant += 1
          else
            discordant += 1
          end
        end
      end

      total_pairs = (n * (n - 1)) / 2
      return 0.0 if total_pairs.zero?

      (((concordant - discordant).to_f / total_pairs).round(3)).to_f
    end

    # Logs detailed re-ranking data for analysis.
    #
    # This method captures before/after snapshots of candidate rankings:
    # - Original semantic search order (by ES similarity score)
    # - LLM-reranked order (by confidence score)
    # - Position changes for each candidate
    # - Aggregate metrics
    #
    sig do
      params(
        results: T::Array[Result],
        metrics: RerankingMetrics,
        context: String
      ).void
    end
    def log_reranking_results(results, metrics, context:)
      return unless duplicate_detection_logging_enabled?

      # Build detailed ranking comparison
      scored_results = results.select do |result|
        result.classification.llm_processed && result.issue.score.present?
      end

      ranking_data = scored_results.map do |result|
        {
          "issue_number":   result.issue.issue.number,
          "semantic_score": result.issue.score&.round(3),
          "llm_confidence": result.classification.confidence_score.round(3),
          "is_duplicate":   result.classification.is_duplicate
        }
      end

      log_llm_flow("reranking_analysis",
        context:,
        data: {
          "reranking.candidates_count": scored_results.length,
          "reranking.metrics.mean_rank_change":         metrics.mean_rank_change,
          "reranking.metrics.max_rank_change":          metrics.max_rank_change,
          "reranking.metrics.rank_correlation":         metrics.rank_correlation,
          "reranking.metrics.movement_up_count":        metrics.movement_up_count,
          "reranking.metrics.movement_down_count":      metrics.movement_down_count,
          "reranking.metrics.movement_unchanged_count": metrics.movement_unchanged_count,
          "reranking.comparison": ranking_data
        }
      )
    end

    # Instruments aggregate re-ranking metrics to Datadog.
    #
    # Tracks trends in how LLM re-ranking changes candidate ordering:
    # - Average and maximum rank changes (with interpretable bucket tags)
    # - Correlation between semantic and LLM rankings (with agreement level tags)
    # - Movement patterns (up/down/unchanged)
    #
    # Emits both raw histogram values for statistical analysis and bucketed tags
    # for intuitive filtering and dashboarding (e.g., reranking_impact:high,
    # ranking_agreement:moderate).
    #
    sig do
      params(
        metrics: RerankingMetrics,
        tags: T::Array[String]
      ).void
    end
    def instrument_reranking_metrics(metrics, tags:)
      mean_change = metrics.mean_rank_change
      correlation = metrics.rank_correlation

      # Add bucketed tags for interpretable filtering
      reranking_tags = tags + [
        "reranking_impact:#{bucket_rank_change(mean_change)}",
        "ranking_agreement:#{bucket_rank_correlation(correlation)}"
      ]

      max_rank_change = metrics.max_rank_change
      movement_up_count = metrics.movement_up_count
      movement_down_count = metrics.movement_down_count
      movement_unchanged_count = metrics.movement_unchanged_count

      [["mean_rank_change", mean_change], ["max_rank_change", max_rank_change], ["rank_correlation", correlation]]
        .each do |metric_name, value|
        GitHub.dogstats.histogram("issues.duplicate_detection.reranking.#{metric_name}", value, tags: reranking_tags)
      end

      [["movement_up", movement_up_count], ["movement_down", movement_down_count], ["movement_unchanged", movement_unchanged_count]]
        .each do |metric_name, value|
        GitHub.dogstats.count("issues.duplicate_detection.reranking.#{metric_name}", value, tags: reranking_tags)
      end
    end

    # Tracks correlation metrics between semantic similarity scores and LLM confidence.
    #
    # This method analyzes the relationship between Elasticsearch semantic scores and
    # LLM duplicate-detection confidence to support data-driven tuning of the pipeline
    # (e.g., confidence-based gating and cost/latency optimization).
    #
    # The correlation data helps answer questions such as:
    # - Do high semantic scores reliably predict high LLM confidence?
    # - When can semantic scores safely pre-filter candidates before LLM evaluation?
    #
    # Metrics tracked per result:
    # - Semantic similarity score (when available)
    # - LLM confidence score
    # - Score delta (LLM confidence − semantic score)
    # - Bucketed score combinations for trend analysis
    #
    # Metrics are emitted with bucketed tags (to avoid high cardinality), including:
    # - semantic_score_bucket
    # - llm_confidence_bucket
    # - is_duplicate
    #
    # This granular data enables detailed analysis of the interplay between semantic search
    # and LLM results, informing future optimizations.
    sig do
      params(
        batch_result: BatchResult,
        tags: T::Array[String]
      ).void
    end
    def instrument_score_correlation_metrics(batch_result, tags:)
      batch_result.results.each do |result|
        next unless result.classification.llm_processed

        semantic_score = result.issue.score
        llm_confidence = result.classification.confidence_score
        is_duplicate = result.classification.is_duplicate

        score_tags = tags + [
          "semantic_score_bucket:#{bucket_similarity_score(semantic_score)}",
          "llm_confidence_bucket:#{bucket_confidence_score(llm_confidence)}",
          "is_duplicate:#{is_duplicate}"
        ]

        # Track individual scores for correlation analysis
        if semantic_score
          GitHub.dogstats.histogram("issues.duplicate_detection.semantic_score",
            semantic_score, tags: score_tags)
        end

        GitHub.dogstats.histogram("issues.duplicate_detection.llm_confidence_score",
          llm_confidence, tags: score_tags)

        # Track score difference (LLM confidence - semantic score) when both available
        if semantic_score
          score_difference = llm_confidence - semantic_score
          GitHub.dogstats.histogram("issues.duplicate_detection.score_difference",
            score_difference, tags: score_tags)
        end

        # Count by score bucket combinations for pattern analysis
        GitHub.dogstats.increment("issues.duplicate_detection.score_bucket_combination",
          tags: score_tags)
      end
    end

    # Builds standardized instrumentation tags for metrics collection
    #
    # This method creates consistent tag sets for all duplicate detection metrics,
    # enabling detailed analysis and filtering across different dimensions. Tags
    # provide essential context for understanding metric patterns and performance
    # characteristics.
    #
    # Standard tags include:
    # - Processing context (API endpoint, batch job, etc.)
    # - LLM enablement status for feature comparison
    # - Text length buckets for performance correlation
    # - Repository visibility for usage pattern analysis
    #
    # Consistent tagging enables:
    # - Cross-dimensional metric analysis (context × performance)
    # - Feature flag impact assessment (LLM vs non-LLM)
    # - Resource usage optimization (text length correlation)
    # - Usage pattern identification (public vs private repos)
    sig do
      params(
        context: String,
        llm_enabled: T::Boolean,
        llm_model: String,
        prompt_text_length_bucket: String,
        total_input_length_bucket: String
      ).returns(T::Array[String])
    end
    def build_instrumentation_tags(context:, llm_enabled:, llm_model:, prompt_text_length_bucket:, total_input_length_bucket:)
      [
        "context:#{context}",
        "llm_enabled:#{llm_enabled}",
        "llm_model:#{llm_model}", # Include LLM model for detailed analysis based on model type/version
        "prompt_text_length_bucket:#{prompt_text_length_bucket}",
        "total_input_length_bucket:#{total_input_length_bucket}",
        "repo_visibility:#{repo_visibility_tag}"
      ]
    end
  end
end
