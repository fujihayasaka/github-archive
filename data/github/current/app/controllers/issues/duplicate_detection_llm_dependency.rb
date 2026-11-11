# typed: strict
# frozen_string_literal: true

module Issues
  # LLM-assisted duplicate detection that enhances semantic similarity results
  module DuplicateDetectionLlmDependency
    extend T::Helpers
    include DuplicateDetectionTypes

    requires_ancestor { AbstractRepositoryController }

    abstract!

    class DuplicateDetectionLlmError < StandardError; end

    # Default model for duplicate detection
    DEFAULT_MODEL = "gpt-5.2"
    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_TEMPERATURE = 0.1

    # Batch processing limits
    MAX_BATCH_SIZE = 3

    # Token allocation for JSON structure overhead (wrapper, keys)
    BASE_TOKENS = 100

    # Token allocation per candidate for JSON response
    TOKENS_PER_CANDIDATE = 200

    # Maximum length for issue body text in prompts
    MAX_ISSUE_BODY_LENGTH = 1000

    CAPI_INITIATOR = "agent"

    sig { abstract.returns(T.nilable(User)) }
    def current_user; end

    sig { abstract.returns(String) }
    def remote_ip; end

    sig { abstract.returns(T.nilable(UserSession)) }
    def user_session; end

    sig { abstract.returns(Repository) }
    def current_repository; end

    # Buckets similarity score into coarse ranges for metrics analysis
    #
    # This method enables analysis of semantic search score distributions and correlation
    # with LLM confidence scores. Bucketed scores prevent high-cardinality metrics while
    # still providing meaningful insights for performance analysis.
    #
    # Score Ranges (semantic similarity from Elasticsearch):
    # - "0.0-0.2": Very low similarity
    # - "0.2-0.4": Low similarity
    # - "0.4-0.6": Medium similarity
    # - "0.6-0.8": High similarity
    # - "0.8-1.0": Very high similarity
    # - "null": No score available
    #
    # Usage:
    #   bucket_similarity_score(0.15)  # => "0.0-0.2"
    #   bucket_similarity_score(0.75)  # => "0.6-0.8"
    #   bucket_similarity_score(nil)   # => "null"
    #
    sig { params(score: T.nilable(Float)).returns(String) }
    def bucket_similarity_score(score)
      return "null" if score.nil?

      case score
      when 0.0..0.2
        "0.0-0.2"
      when 0.2..0.4
        "0.2-0.4"
      when 0.4..0.6
        "0.4-0.6"
      when 0.6..0.8
        "0.6-0.8"
      else
        "0.8-1.0"
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
    # the LLM found the decision more ambiguous.
    #
    # Score Ranges (LLM confidence from duplicate detection):
    # - "0.0-0.2": Very low confidence (highly uncertain decisions)
    # - "0.2-0.4": Low confidence (uncertain decisions)
    # - "0.4-0.6": Medium confidence (moderately certain decisions)
    # - "0.6-0.8": High confidence (fairly certain decisions)
    # - "0.8-1.0": Very high confidence (highly certain decisions)
    #
    # Usage:
    #   bucket_confidence_score(0.15)  # => "0.0-0.2"
    #   bucket_confidence_score(0.85)  # => "0.8-1.0"
    #
    sig { params(score: Float).returns(String) }
    def bucket_confidence_score(score)
      case score
      when 0.0..0.2
        "0.0-0.2"
      when 0.2..0.4
        "0.2-0.4"
      when 0.4..0.6
        "0.4-0.6"
      when 0.6..0.8
        "0.6-0.8"
      else
        "0.8-1.0"
      end
    end

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

    # Returns repository visibility as a string for metrics tagging
    sig { returns(String) }
    def repo_visibility_tag
      current_repository.private? ? "private" : "public"
    end

    # Evaluates a batch of candidates against a target to determine if any are duplicates
    # using LLM-assisted analysis.
    #
    # This method processes multiple candidates in a single batch operation, with built-in
    # error handling and fallback mechanisms. When LLM processing is disabled, it returns
    # non-duplicate classifications for all candidates. When enabled, it processes each candidate
    # individually through the LLM, with a maximum batch size limit to prevent timeouts.
    #
    # @note Processing is limited to MAX_BATCH_SIZE candidates to prevent timeouts
    # @note Candidates beyond MAX_BATCH_SIZE receive fallback classifications to maintain 1:1 correspondence
    # @note Failed individual evaluations are handled gracefully with fallback classifications
    sig do
      params(
        target: T.any(Issue, TargetIssueData),
        candidates: T::Array[Search::Queries::SimilarIssueResult],
        context: String,
        llm_enabled: T::Boolean
      ).returns(BatchResult)
    end
    def evaluate_batch_duplicates(target:, candidates:, context:, llm_enabled: true)
      results = T.let([], T::Array[Result])
      target_data = target.is_a?(Issue) ? TargetIssueData.from_issue(target) : target
      start_time = Time.current

      # Calculate text lengths for telemetry (with timing tracking)
      input_calculation_start = Time.current
      target_text_length = target_data.title.length + (target_data.body || "").length
      candidates_text_length = candidates.sum { |candidate| candidate.issue.title.length + (candidate.issue.body_text || "").length }
      total_input_length = target_text_length + candidates_text_length

      # Remove separate processing_input_metrics variable since it's now consolidated
      prompt_text_length_bucket = bucket_text_length(target_text_length)
      total_input_length_bucket = bucket_text_length(total_input_length)
      input_calculation_time_ms = (Time.current - input_calculation_start) * 1000
      unless llm_enabled
        results = candidates.map do |candidate|
          Result.new(
            issue: candidate,
            classification: fallback_classification("LLM evaluation disabled")
          )
        end

        return BatchResult.new(
          results:,
          llm_enabled: false,
          total_candidates: candidates.length,
          processed_candidates: candidates.length,
          processing_metrics: ProcessingMetrics.new(
            prompt_text_length_bucket:,
            total_input_length_bucket:,
            processing_time_ms: (Time.current - start_time) * 1000
          )
        )
      end

      # Process candidates with LLM concurrently
      processed_count = 0

      # Limit batch size to prevent timeouts, but ensure all candidates get results
      candidates_to_process = candidates.first(MAX_BATCH_SIZE)

      # Use CopilotAPI's async_create_chat_completion with individual message prompts
      # This processes each candidate as a separate message for clearer evaluation
      if candidates_to_process.any?
        llm_call_start = Time.current

        log_llm_flow("initiating_llm_evaluation",
          context:,
          data: {
            "target.issue_number": target_data.number || "new_issue",
            "candidates.count": candidates_to_process.length,
          }
        )
        batch_promise = evaluate_multiple_duplicates_async(
          target: target_data,
          candidates: candidates_to_process,
          context:
        )

        log_llm_flow("llm_evaluation_in_progress", context:)

        batch_result = batch_promise.sync
        llm_call_time_ms = (Time.current - llm_call_start) * 1000

        log_llm_flow("llm_batch_processing_complete", context:, data: { "batch_result.class": batch_result.class.name })

        if batch_result.success
          results.concat(batch_result.results)
          processed_count += batch_result.processed_count
          log_llm_flow("llm_evaluation_completed", context:, data: { "processed_candidates": batch_result.processed_count })
        else
          log_llm_flow("llm_evaluation_failed", context:, data: { "error": batch_result.error&.message || "Unknown error during LLM batch processing" })
          results.concat(
            add_fallback_results_for_candidates(
              candidates: candidates_to_process,
              error: batch_result.error || StandardError.new("Unknown error during LLM batch processing"),
              context:,
              fallback_message: batch_result.error.present? ? "LLM batch processing failed" : "LLM batch processing failed with unknown error"
            )
          )
        end
      end

      # Add fallback classifications for remaining candidates beyond MAX_BATCH_SIZE
      # This ensures results.length == total_candidates for 1:1 correspondence
      fallback_processing_start = Time.current
      remaining_candidates = candidates.drop(MAX_BATCH_SIZE)
      remaining_candidates.each do |candidate|
        results << Result.new(
          issue: candidate,
          classification: fallback_classification("Batch size limit exceeded")
        )
      end

      fallback_processing_time_ms = (Time.current - fallback_processing_start) * 1000
      processing_time_ms = (Time.current - start_time) * 1000

      # Log detailed timing breakdown for performance analysis
      log_llm_flow("batch_processing_timing",
        context:,
        data: {
          "timing.input_calculation_ms": input_calculation_time_ms,
          "timing.llm_call_ms": defined?(llm_call_time_ms) ? llm_call_time_ms : 0,
          "timing.fallback_processing_ms": fallback_processing_time_ms,
          "timing.total_ms": processing_time_ms,
          "performance.candidates_per_second": candidates.length > 0 ? (candidates.length / (processing_time_ms / 1000.0)).round(2) : 0,
          "batch.total_candidates": candidates.length,
          "batch.processed_candidates": processed_count
        }
      )

      BatchResult.new(
        results:,
        llm_enabled: true,
        total_candidates: candidates.length,
        processed_candidates: processed_count,
        processing_metrics: ProcessingMetrics.new(
          prompt_text_length_bucket:,
          total_input_length_bucket:,
          processing_time_ms:
        )
      )
    end

    # Convenience method for comparing raw title/body text against candidates
    #
    # This method provides a streamlined interface for duplicate detection when you have
    # raw issue content (title and body) rather than a persisted Issue object. It's
    # particularly useful for detecting duplicates before an issue is created.
    #
    # The method internally creates a TargetIssueData object from the provided text
    # and delegates to evaluate_batch_duplicates. This abstraction simplifies the
    # calling interface for pre-creation duplicate detection scenarios.
    #
    # Common use cases:
    # - Issue creation forms with duplicate prevention
    # - API endpoints that accept raw issue data
    # - Bulk import processes with duplicate filtering
    sig do
      params(
        candidates: T::Array[Search::Queries::SimilarIssueResult],
        context: String,
        title: String,
        body: T.nilable(String),
        llm_enabled: T::Boolean
      ).returns(BatchResult)
    end
    def evaluate_batch_duplicates_from_text(candidates:, context:, title:, body: nil, llm_enabled: true)
      target_data = TargetIssueData.from_text(title: title, body: body)
      evaluate_batch_duplicates(
        target: target_data,
        candidates:,
        context:,
        llm_enabled:
      )
    end

    # Evaluates multiple candidates against a target using individual message prompts
    #
    # This method processes multiple candidates by creating individual prompts for each
    # candidate and sending them as separate messages in a single API call. This approach
    # provides clear, focused prompts for each evaluation while allowing the CopilotAPI
    # to handle parallelization internally.
    #
    # @raise [DuplicateDetectionLlmError] If user context is missing for LLM evaluation
    # @note Uses async_create_chat_completion with multiple individual messages
    # @note Promise resolves to hash with results for all candidates
    sig do
      params(
        target: T.any(Issue, TargetIssueData),
        candidates: T::Array[Search::Queries::SimilarIssueResult],
        context: String
      ).returns(Promise[AsyncEvaluationResult])
    end
    def evaluate_multiple_duplicates_async(target:, candidates:, context:)
      if current_user.blank? || remote_ip.blank?
        log_llm_flow(
          "llm_evaluation_skipped", context:,
          data: {
            "reason": "Missing user or IP context for LLM evaluation",
            "target.issue_number": target.number || "new_issue",
          }
        )
        return Promise.new.reject(
          DuplicateDetectionLlmError.new(
            "Current user or request IP is missing for LLM evaluation"
          )
        )
      end

      # Convert Issue to TargetIssueData if needed
      target_data = target.is_a?(Issue) ? TargetIssueData.from_issue(target) : target

      # Build single comprehensive prompt for all candidates
      batch_prompt = build_batch_duplicate_detection_prompt(
        target: target_data,
        candidates: candidates
      )

      # Log prompt construction analysis
      log_llm_flow("prompt_construction_analysis",
        context: "prompt_analysis",
        data: {
          "prompt.candidates_count": candidates.length,
          "prompt.length_bucket": bucket_text_length(batch_prompt.length),
          "prompt.total.length": batch_prompt.length,
        }
      )

      copilot_api = Copilot::User.copilot_api(
        user: T.must(current_user),
        integration_id: CopilotAPI::ISSUE_DUPLICATE_DETECTION_INTEGRATION_ID,
        session: user_session,
        real_ip: remote_ip
      )

      log_llm_flow("initiating_async_llm_evaluation", context:, data: {
        "candidates.count": candidates.length,
        "llm.request_id": copilot_api.request_id,
      })

      # Use async_create_chat_completion with single comprehensive message
      promise = copilot_api.async_create_chat_completion(
        model: DEFAULT_MODEL,
        messages: [{ role: "developer", content: batch_prompt }],
        max_tokens: [DEFAULT_MAX_TOKENS, BASE_TOKENS + TOKENS_PER_CANDIDATE * candidates.length].min, # Ensure adequate tokens for JSON overhead + per-candidate content
        temperature: DEFAULT_TEMPERATURE,
        initiator: CAPI_INITIATOR
      )

      log_llm_flow("llm_promise_created", context:, data: { "promise.class": promise.class.name })

      promise.then do |response|
        log_llm_flow("llm_response_received", context:, data: {
          "llm.request_id": copilot_api.request_id, "response_type": response.class.name
        })
        # Success case - parse responses for all candidates
        results = parse_llm_response(response:, target: target_data, candidates:, context:)
        AsyncEvaluationResult.new(success: true, results:, processed_count: results.length, error: nil)
      end.catch do |error|
        safe_error = error.is_a?(StandardError) ? error : StandardError.new(error.to_s)
        log_llm_flow("llm_evaluation_failed", context:, data: { "error": safe_error.message, "llm.request_id": copilot_api.request_id })
        log_llm_error(safe_error, context:, reason: "CopilotAPI async_create_chat_completion failed")
        AsyncEvaluationResult.new(success: false, results: [], processed_count: 0, error: safe_error)
      end
    rescue StandardError => error
      log_llm_flow("llm_evaluation_failed", context:, data: { "error": error.message })
      log_llm_error(error, context:, reason: "Exception raised in evaluate_multiple_duplicates_async")
      Promise.resolve(
        AsyncEvaluationResult.new(success: false, results: [], processed_count: 0, error:)
      )
    end

    private

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

    # Parses a single comprehensive Copilot API response containing results for all candidates
    #
    # This method handles a structured response from a batch prompt that evaluates
    # all candidates together. Results are associated with candidates via issue IDs,
    # providing efficient and clear batch processing.
    sig do
      params(
        response: T.untyped,
        target: TargetIssueData,
        candidates: T::Array[Search::Queries::SimilarIssueResult],
        context: String
      ).returns(T::Array[Result])
    end
    def parse_llm_response(response:, target:, candidates:, context:)
      log_llm_flow("parsing_llm_response", context:, data: { "response_type": response.class.name })
      response = response.sync if response.is_a?(ConcurrentFaraday::FutureResponse)

      # Log raw LLM response for debugging and analysis
      log_llm_flow("raw_llm_response_received",
        context:,
        data: {
          "response.model": response["model"],
          "response.choices_count": response["choices"]&.length || 0,
          "response.usage": response["usage"],
          "response.choice_lengths": response["choices"]&.map { |c| c.dig("message", "content")&.length || 0 },
          "response.has_empty_choices": response["choices"]&.any? { |c| c.dig("message", "content").blank? },
          "response.raw_choices": duplicate_detection_raw_choice_logging_enabled? ? response["choices"] : "[redacted - enable raw choice logging to view]",
          "request.candidates_count": candidates.length
        }
      )

      choices = response.fetch("choices", [])

      if choices.empty?
        raise DuplicateDetectionLlmError, "No choices in response from model for duplicate detection"
      end

      # Get the first (and should be only) choice containing batch results
      choice = choices.first
      content = choice&.dig("message", "content")

      unless content&.present?
        raise DuplicateDetectionLlmError, "Empty response content from LLM"
      end

      begin
        # Parse the batch JSON response
        generated_text = content.gsub(/\A```\s*json\n*|\n*```\n*\z/, "")
        batch_response = JSON.parse(generated_text)

        unless batch_response.is_a?(Hash) && batch_response["results"].is_a?(Array)
          raise DuplicateDetectionLlmError, "Invalid batch response structure"
        end

        # Build results array by matching issue IDs
        results = T.let([], T::Array[Result])
        candidate_lookup = candidates.index_by { |c| c.issue.number }

        batch_response["results"].each do |result_data|
          raw_issue_number = result_data["issue_number"]
          repository_nwo = result_data["repository_nwo"]

          # Normalize issue_number to integer for lookup (LLM may return string/float)
          issue_number = coerce_to_integer(raw_issue_number)
          unless issue_number
            log_llm_flow("invalid_issue_number", context:, data: {
              "raw_issue_number": raw_issue_number,
              "repository_nwo": repository_nwo
            })
            next
          end

          candidate = candidate_lookup[issue_number]

          unless candidate
            log_llm_flow("unmatched_issue_number", context:, data: { "issue_number": issue_number, "repository_nwo": repository_nwo })
            next
          end

          classification = build_duplicate_classification(result_data)
          results << Result.new(issue: candidate, classification:)
        end

        # Add fallback results for any candidates not included in response
        missing_candidates = candidates.reject { |c| results.any? { |r| r.issue.issue.number == c.issue.number } }
        missing_candidates.each do |candidate|
          results << Result.new(
            issue: candidate,
            classification: fallback_classification("Missing result in batch response")
          )
        end

      rescue JSON::ParserError => e
        # Fallback if JSON parsing fails for batch response
        log_llm_error(e, context:, reason: "JSON parsing failed for batch LLM response")
        results = candidates.map do |candidate|
          Result.new(
            issue: candidate,
            classification: fallback_classification("Batch response parsing failed")
          )
        end
      rescue DuplicateDetectionLlmError => e
        log_llm_error(e, context:, reason: "Error processing batch LLM response")
        results = candidates.map do |candidate|
          Result.new(
            issue: candidate,
            classification: fallback_classification("Error processing batch response")
          )
        end
      rescue StandardError => e
        log_llm_error(e, context:, reason: "Unexpected error parsing batch LLM response")
        results = candidates.map do |candidate|
          Result.new(
            issue: candidate,
            classification: fallback_classification("Unexpected processing error")
          )
        end
      end

      log_llm_flow("llm_response_parsed", context:,
        data: {
          "target.issue_number": target.number || "new_issue",
          "candidates.count": candidates.length,
          "results.count": results.length,
          "results.duplicates.count": results.count { |result| result.classification.is_duplicate },
          "results.avg_confidence": results.map { |result| result.classification.confidence_score }.sum / results.length.to_f,
          "results.confidence_buckets": results.group_by { |result| bucket_confidence_score(result.classification.confidence_score) }.transform_values(&:count),
          "results.similarity_buckets": results.group_by { |result| bucket_similarity_score(result.issue.score) }.transform_values(&:count),
          "results.text_length_buckets": results.group_by { |result| bucket_text_length((result.issue.issue.title.length + (result.issue.issue.body_text || "").length)) }.transform_values(&:count),
        }
      )

      results
    end

    # Constructs a comprehensive batch prompt for evaluating multiple candidates
    #
    # This method builds a single prompt that includes information about the target issue
    # and all candidate issues, requesting a structured JSON response with results for each
    # candidate identified by issue ID. This approach is more efficient than individual
    # prompts and provides better context for the LLM.
    sig do
      params(
        target: TargetIssueData,
        candidates: T::Array[Search::Queries::SimilarIssueResult]
      ).returns(String)
    end
    def build_batch_duplicate_detection_prompt(target:, candidates:)
      # Build target section
      if target.number
        target_section = <<~TARGET
          TARGET ISSUE ##{target.number}:
          Title: #{target.title}
          Body: #{truncate_text(target.body || "")}
          State: #{target.state}
          Created: #{target.created_at&.strftime("%Y-%m-%d")}
        TARGET
      else
        target_section = <<~TARGET
          TARGET ISSUE (new issue being created):
          Title: #{target.title}
          Body: #{truncate_text(target.body || "")}
        TARGET
      end

      # Build candidates section
      candidate_blocks = candidates.map do |candidate|
        <<~CANDIDATE
          CANDIDATE ##{candidate.issue.number}:
          Repository: #{candidate.issue.repository&.name_with_display_owner}
          Title: #{candidate.issue.title}
          Body: #{truncate_text(candidate.issue.body_text || "")}
          State: #{candidate.issue.state}
          Created: #{candidate.issue.created_at.strftime("%Y-%m-%d")}
        CANDIDATE
      end
      candidates_section = candidate_blocks.join("\n")

      <<~PROMPT
        You are an expert at identifying duplicate GitHub issues. Evaluate each candidate issue against the target issue to determine if they are duplicates.

        #{target_section.strip}

        CANDIDATES TO EVALUATE:
        #{candidates_section.strip}

        EVALUATION CRITERIA:
        - TRUE DUPLICATE: Same core problem, same root cause, would be resolved by the same fix
        - RELATED: Similar topic/component but different specific issues or use cases
        - NOT DUPLICATE: Different problems entirely

        Consider:
        - Specific technical details and error messages
        - Different manifestations of the same underlying issue
        - Similar symptoms but different causes
        - The exact wording and context of both issues
        #{target.number ? "" : "- Focus primarily on content similarity since the target issue is new"}

        You must respond with valid JSON containing results for ALL candidates in this exact format:
        {
          "results": [
            {
              "repository_nwo": "#{current_repository.name_with_display_owner}",
              "issue_number": #{candidates.first&.issue&.number || 123},
              "is_duplicate": true/false,
              "confidence_score": 0.85,
              "reasoning": "Brief explanation of your decision"
            }
          ]
        }

        The confidence_score should be between 0.0 and 1.0, where:
        - 0.9-1.0: Very confident
        - 0.7-0.9: Confident
        - 0.5-0.7: Somewhat confident
        - 0.0-0.5: Low confidence

        IMPORTANT: Include a result for EVERY candidate issue listed above, using the exact repository_nwo and issue_number values.
      PROMPT
    end

    # Truncates issue body text to prevent LLM prompt length issues
    #
    # This method ensures issue body content stays within reasonable limits for
    # LLM processing. Long issue bodies can cause prompt length errors or
    # degraded performance, so truncation with clear indicators helps maintain
    # consistent behavior.
    #
    # The truncation preserves the most important content (beginning of the text)
    # while clearly marking when truncation occurred. This approach balances
    # content preservation with system reliability.
    sig { params(text: String).returns(String) }
    def truncate_text(text)
      return "" if text.blank?

      if text.length <= MAX_ISSUE_BODY_LENGTH
        text
      else
        "#{text[0, MAX_ISSUE_BODY_LENGTH]}..."
      end
    end

    # Coerces various types to integer for issue number matching
    #
    # Handles type variations that may come from LLM JSON responses:
    # - Integer: returned as-is (with bounds checking)
    # - Float: only whole numbers (2.0 -> 2, rejects 2.5)
    # - String: attempts parsing ("2" or "2.0" -> 2)
    # - Other: returns nil for invalid values
    #
    # Issue numbers are bounded to reasonable ranges (positive, < 1 billion)
    # to prevent overflow issues and catch obvious errors.
    #
    # This ensures reliable lookup matching regardless of JSON parsing quirks.
    sig { params(value: T.untyped).returns(T.nilable(Integer)) }
    def coerce_to_integer(value)
      result = case value
      when Integer
        value
      when Float
        # Only accept whole number floats (2.0 is ok, 2.5 is not)
        value % 1 == 0 ? value.to_i : nil
      when String
        # Parse as float first to handle both "2" and "2.0"
        begin
          float_val = Float(value)
          float_val % 1 == 0 ? float_val.to_i : nil
        rescue ArgumentError, TypeError
          nil
        end
      else
        nil
      end

      # Bounds check: issue numbers should be positive and reasonable
      result && result > 0 && result < 1_000_000_000 ? result : nil
    end

    # Rounds confidence scores to consistent precision for storage and comparison
    #
    # This method standardizes floating-point confidence scores to 3 decimal places.
    # It safely handles nil values by converting them to 0.0, preventing downstream errors.
    #
    # Consistent precision is important for:
    # - Reliable score comparisons and sorting
    # - Consistent serialization and storage
    # - Predictable behavior across different environments
    sig { params(score: T.nilable(Float)).returns(Float) }
    def round_score(score)
      (score || 0.0).round(3).to_f
    end

    # Adds fallback results for a batch of candidates when LLM processing fails
    #
    # This helper method consolidates the common pattern of logging an error
    # and adding fallback classifications for all candidates in a batch.
    # It reduces code duplication while maintaining clear error handling.
    sig do
      params(
        candidates: T::Array[Search::Queries::SimilarIssueResult],
        error: StandardError,
        context: String,
        fallback_message: String
      ).returns(T::Array[Result])
    end
    def add_fallback_results_for_candidates(candidates:, error:, context:, fallback_message:)
      results = T.let([], T::Array[Result])
      log_llm_error(error, context:, reason: fallback_message)

      candidates.each do |candidate|
        results << Result.new(
          issue: candidate,
          classification: fallback_classification(fallback_message)
        )
      end

      results
    end

    # Creates a safe fallback classification when LLM processing fails
    #
    # This method provides a consistent fallback mechanism for scenarios where
    # LLM evaluation cannot be completed (network errors, parsing failures,
    # validation errors, etc.). It ensures we always return valid classification data.
    #
    # Fallback classifications are conservative by design:
    # - Always marked as non-duplicate (false positive prevention)
    # - Zero confidence score (indicates uncertainty)
    # - Clear reasoning explaining the fallback
    # - Marked as not LLM-processed for metrics tracking
    sig { params(reasoning: String).returns(DuplicateClassification) }
    def fallback_classification(reasoning)
      DuplicateClassification.new(
        is_duplicate: false,
        confidence_score: 0.0,
        reasoning:,
        llm_processed: false
      )
    end

    # Constructs a DuplicateClassification from parsed LLM JSON response
    #
    # This method transforms validated JSON response data into a structured
    # DuplicateClassification object. It handles data validation, type conversion,
    # and applies safety constraints to ensure data integrity.
    #
    # Processing includes:
    # - Boolean conversion for is_duplicate field
    # - Confidence score validation and clamping (0.0-1.0 range)
    # - String cleaning and trimming for reasoning text
    # - Precision rounding for consistent score handling
    #
    # The method assumes the JSON has already been parsed and validated,
    # focusing on safe data extraction and object construction.
    sig { params(parsed_response: T.untyped).returns(DuplicateClassification) }
    def build_duplicate_classification(parsed_response)
      is_duplicate = coerce_boolean(parsed_response["is_duplicate"])
      confidence_score = coerce_confidence_score(parsed_response["confidence_score"])
      reasoning = parsed_response["reasoning"]&.to_s&.strip

      DuplicateClassification.new(
        is_duplicate:,
        confidence_score:,
        reasoning:,
        llm_processed: true
      )
    end

    # Safely coerces various boolean representations to actual boolean values
    #
    # Handles common LLM outputs:
    # - Boolean values: true/false -> true/false
    # - String values: "true"/"false" (case insensitive) -> true/false
    # - Truthy/falsy: non-empty strings, numbers -> appropriate boolean
    # - Invalid/nil values -> false (conservative default)
    sig { params(value: T.untyped).returns(T::Boolean) }
    def coerce_boolean(value)
      case value
      when true, false
        value
      when String
        case value.to_s.strip.downcase
        when "true", "1", "yes"
          true
        when "false", "0", "no", ""
          false
        else
          # For unexpected string values, treat as false for safety
          false
        end
      when Numeric
        !value.zero?
      else
        false
      end
    end

    # Safely coerces and validates confidence score values
    #
    # Handles common LLM outputs:
    # - Numeric values: directly clamped to 0.0-1.0 range
    # - String numbers: parsed then clamped
    # - Invalid values: defaults to 0.0
    # - Out of range: clamped to valid range
    sig { params(value: T.untyped).returns(Float) }
    def coerce_confidence_score(value)
      case value
      when Numeric
        round_score(value.clamp(0.0, 1.0))
      when String
        begin
          parsed_value = Float(value)
          round_score(parsed_value.clamp(0.0, 1.0))
        rescue ArgumentError
          0.0
        end
      else
        0.0
      end
    end

    # Serializes batch processing results into structured summary format
    #
    # This method transforms internal BatchResult data into a client-facing
    # DuplicateResultSummary format suitable for API responses. It organizes
    # processing metadata and individual results in a consistent structure.
    #
    # The serialization process includes:
    # - Processing metadata consolidation (timing, counts, metrics)
    # - Individual result transformation and formatting
    # - Confidence-based sorting (highest confidence first)
    # - Clean separation of processing data from results
    #
    # This standardized format enables consistent API responses regardless
    # of the internal processing implementation details.
    sig { params(batch_result: BatchResult).returns(DuplicateResultSummary) }
    def serialize_llm_duplicate_results(batch_result)
      processing_metadata = ProcessingMetadata.new(
        llm_enabled: batch_result.llm_enabled,
        total_candidates: batch_result.total_candidates,
        processed_candidates: batch_result.processed_candidates,
        processing_metrics: batch_result.processing_metrics
      )

      duplicates = batch_result.results.filter_map do |result|
        # Only include results classified as duplicates
        if result.classification.is_duplicate
          serialize_single_duplicate_result(result)
        end
      end.sort_by { |item| -item.duplicate_classification.confidence_score } # Sort by confidence score descending

      DuplicateResultSummary.new(
        processing_metadata:,
        duplicates:
      )
    end

    # Serializes a single duplicate evaluation result for API response
    #
    # This method converts internal Result objects into client-facing
    # SingleDuplicateResult format. It extracts the essential information
    # needed for API consumers while maintaining data consistency.
    #
    # The serialization focuses on:
    # - Issue ID extraction from SimilarIssueResult
    # - Classification data preservation
    # - Consistent field naming and structure
    sig { params(result: Result).returns(SingleDuplicateResult) }
    def serialize_single_duplicate_result(result)
      SingleDuplicateResult.new(
        issue_id: result.issue.issue.id,
        duplicate_classification: result.classification
      )
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
        prompt_text_length_bucket: batch_result.processing_metrics.prompt_text_length_bucket,
        total_input_length_bucket: batch_result.processing_metrics.total_input_length_bucket
      )

      # Processing time
      GitHub.dogstats.histogram("issues.duplicate_detection.processing_time_ms",
        batch_result.processing_metrics.processing_time_ms, tags: tags)

      # Candidate counts
      GitHub.dogstats.histogram("issues.duplicate_detection.total_candidates",
        batch_result.total_candidates, tags: tags)
      GitHub.dogstats.histogram("issues.duplicate_detection.processed_candidates",
        batch_result.processed_candidates, tags: tags)

      # Success rate
      total = batch_result.total_candidates
      success_rate = total.zero? ? 0 : batch_result.processed_candidates.to_f / total
      GitHub.dogstats.histogram("issues.duplicate_detection.success_rate",
        success_rate, tags: tags)

      if batch_result.llm_enabled
        # LLM-specific metrics
        llm_processed_count = batch_result.results.count { |result| result.classification.llm_processed }
        duplicate_count = batch_result.results.count { |result| result.classification.is_duplicate }

        GitHub.dogstats.histogram("issues.duplicate_detection.llm_processed_count", llm_processed_count, tags: tags)
        GitHub.dogstats.histogram("issues.duplicate_detection.duplicates_found", duplicate_count, tags: tags)

        # Delegate to specialized score correlation analysis
        instrument_score_correlation_metrics(batch_result, tags:)
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
        prompt_text_length_bucket: String,
        total_input_length_bucket: String,
      ).returns(T::Array[String])
    end
    def build_instrumentation_tags(context:, llm_enabled:, prompt_text_length_bucket:, total_input_length_bucket:)
      [
        "context:#{context}",
        "llm_enabled:#{llm_enabled}",
        "prompt_text_length_bucket:#{prompt_text_length_bucket}",
        "total_input_length_bucket:#{total_input_length_bucket}",
        "repo_visibility:#{repo_visibility_tag}"
      ]
    end
  end
end
