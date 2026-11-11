# typed: strict
# frozen_string_literal: true

module Issues
  # LLM-assisted duplicate detection that enhances semantic similarity results
  module DuplicateDetectionLlmDependency
    extend T::Helpers
    include DuplicateDetectionTypes
    include DuplicateDetectionLlmInstrumentation

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

    # Retrieves the model name from environment variable or uses default
    # This allows configuring the model via Vault without requiring a deploy
    sig { returns(String) }
    def model_name
      ENV.fetch("DUPLICATE_DETECTION_LLM_MODEL", "").strip.presence || DEFAULT_MODEL
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
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Calculate text lengths for telemetry
      target_text_length = target_data.title.length + (target_data.body || "").length
      candidates_text_length = candidates.sum { |candidate| candidate.issue.title.length + (candidate.issue.body_text || "").length }
      total_input_length = target_text_length + candidates_text_length

      prompt_text_length_bucket = bucket_text_length(target_text_length)
      total_input_length_bucket = bucket_text_length(total_input_length)
      input_calculation_end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      input_calculation_time_ms = (input_calculation_end_time - start_time) * 1_000
      unless llm_enabled
        results = candidates.map do |candidate|
          Result.new(
            issue: candidate,
            classification: fallback_classification("LLM evaluation disabled")
          )
        end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        processing_time_ms = (end_time - start_time) * 1_000

        return BatchResult.new(
          results:,
          llm_enabled: false,
          total_candidates: candidates.length,
          processed_candidates: candidates.length,
          processing_metrics: ProcessingMetrics.new(
            prompt_text_length_bucket:,
            total_input_length_bucket:,
            input_calculation_time_ms:,
            processing_time_ms:
          )
        )
      end

      # Process candidates with LLM concurrently
      processed_count = 0
      llm_usage = nil

      # Limit batch size to prevent timeouts, but ensure all candidates get results
      candidates_to_process = candidates.first(MAX_BATCH_SIZE)

      # Use CopilotAPI's async_create_chat_completion with individual message prompts
      # This processes each candidate as a separate message for clearer evaluation
      if candidates_to_process.any?
        llm_call_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
        llm_call_end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        llm_call_time_ms = (llm_call_end_time - llm_call_start) * 1_000

        log_llm_flow("llm_batch_processing_complete", context:, data: { "batch_result.class": batch_result.class.name })

        if batch_result.success
          results.concat(batch_result.results)
          processed_count += batch_result.processed_count
          llm_usage = batch_result.usage
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
      fallback_processing_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      remaining_candidates = candidates.drop(MAX_BATCH_SIZE)
      remaining_candidates.each do |candidate|
        results << Result.new(
          issue: candidate,
          classification: fallback_classification("Batch size limit exceeded")
        )
      end

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fallback_processing_time_ms = (end_time - fallback_processing_start) * 1_000
      processing_time_ms = (end_time - start_time) * 1_000

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

      # Build token usage if LLM provided usage data
      token_usage = parse_token_usage(llm_usage)

      BatchResult.new(
        results:,
        llm_enabled: true,
        model: model_name,
        total_candidates: candidates.length,
        processed_candidates: processed_count,
        processing_metrics: ProcessingMetrics.new(
          prompt_text_length_bucket:,
          total_input_length_bucket:,
          input_calculation_time_ms:,
          processing_time_ms:,
          token_usage:,
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
      batch_prompt = build_batch_duplicate_detection_prompt(target: target_data, candidates:)

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
        model: model_name,
        messages: [{ role: "developer", content: batch_prompt }],
        max_tokens: [DEFAULT_MAX_TOKENS, BASE_TOKENS + TOKENS_PER_CANDIDATE * candidates.length].min, # Ensure adequate tokens for JSON overhead + per-candidate content
        temperature: DEFAULT_TEMPERATURE,
        initiator: CAPI_INITIATOR
      )

      log_llm_flow("llm_promise_created", context:, data: { "promise.class": promise.class.name })

      promise.then do |response|
        log_llm_flow("llm_response_received", context:, data: {
          "llm.request_id": copilot_api.request_id,
          "response_type": response.class.name
        })

        # Success case - parse responses for all candidates
        parse_result = parse_llm_response(response:, target: target_data, candidates:, context:)
        AsyncEvaluationResult.new(
          success: true,
          results: parse_result.results,
          processed_count: parse_result.results.length,
          usage: parse_result.usage
        )
      end.catch do |error|
        safe_error = error.is_a?(StandardError) ? error : StandardError.new(error.to_s)
        log_llm_flow("llm_evaluation_failed", context:, data: { "error": safe_error.message, "llm.request_id": copilot_api.request_id })
        log_llm_error(safe_error, context:, reason: "CopilotAPI async_create_chat_completion failed")
        AsyncEvaluationResult.new(success: false, error: safe_error)
      end
    rescue StandardError => error
      log_llm_flow("llm_evaluation_failed", context:, data: { "error": error.message })
      log_llm_error(error, context:, reason: "Exception raised in evaluate_multiple_duplicates_async")
      Promise.resolve(AsyncEvaluationResult.new(success: false, error:))
    end

    private

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
      ).returns(ParsedLlmResponse)
    end
    def parse_llm_response(response:, target:, candidates:, context:)
      log_llm_flow("parsing_llm_response", context:, data: { "response_type": response.class.name })
      response = response.sync if response.is_a?(ConcurrentFaraday::FutureResponse)

      # Extract usage data for token tracking
      # Convert to plain Hash and cast to expected type for Sorbet runtime checks
      # (handles HashWithIndifferentAccess from Rails JSON parsing)
      # Azure OpenAI returns nested hashes for details like completion_tokens_details, prompt_tokens_details
      usage = T.cast(response["usage"]&.to_h, T.nilable(T::Hash[String, T.any(Integer, T::Hash[String, Integer])]))

      # Log raw LLM response for debugging and analysis
      log_llm_flow("raw_llm_response_received",
        context:,
        data: {
          "response.model": response["model"],
          "response.choices_count": response["choices"]&.length || 0,
          "response.usage": usage,
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

      ParsedLlmResponse.new(results:, usage:)
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
        You are an expert at identifying duplicate GitHub issues. Your task is to determine which (IF ANY) of the candidate issues are TRUE duplicates of the target issue.

        #{target_section.strip}

        CANDIDATES TO EVALUATE:
        #{candidates_section.strip}

        DEFINITIONS:
        - **TRUE DUPLICATE**: Same core problem, same root cause, would be resolved by the same fix. Must share specific technical details.
        - **RELATED**: Similar topic, component, or area but different specific problem or use case. NOT a duplicate.
        - **NOT DUPLICATE**: Different problems entirely.

        EXAMPLES:
        Example 1 — TRUE DUPLICATE (should flag):
          Query: "App crashes with OOM on startup when loading >100 plugins"
          Candidate: "Out of memory error during plugin initialization with large plugin count"
          Why: Same root cause (OOM during plugin loading at scale), same fix would resolve both.
          Shared details: OOM error, plugin loading, startup, large plugin count.

        Example 2 — RELATED but NOT duplicate (do NOT flag):
          Query: "App crashes with OOM on startup when loading >100 plugins"
          Candidate: "App is slow when loading many plugins"
          Why: Same component (plugin loading) but different problem (crash vs performance).
          Different root cause, different fix needed.

        Example 3 — SIMILAR SYMPTOMS but NOT duplicate (do NOT flag):
          Query: "App crashes with OOM on startup"
          Candidate: "App crashes with segfault on startup"
          Why: Same symptom (crash on startup) but different cause (OOM vs segfault).
          Different underlying bug, different fix.

        Example 4 — SAME AREA but NOT duplicate (do NOT flag):
          Query: "Login page returns 500 error when using SSO"
          Candidate: "Login page CSS is broken on mobile"
          Why: Same page (login) but completely different problems (server error vs styling).

        EVALUATION CRITERIA FOR EACH CANDIDATE:
        1. **SHARED ROOT CAUSE**: What specific root cause do both issues share? Name it concretely (e.g., "race condition in connection pool cleanup"). If you cannot identify a specific shared root cause, it is NOT a duplicate.
        2. **SAME FIX**: Would a single code change resolve both issues? If different fixes are needed, they are NOT duplicates.
        3. **DISTINGUISHING DETAILS**: Are there specific details (error codes, versions, affected platforms, reproduction steps, stack traces) that prove these are DIFFERENT problems despite surface similarity? If yes, they are NOT duplicates.

        A candidate is a TRUE DUPLICATE only if:
          ✅ You can name a specific shared root cause
          ✅ The same fix would resolve both
          ✅ No distinguishing details prove them to be different problems

        IMPORTANT RULES:
        - When uncertain, do NOT flag as duplicate. False positives are worse than false negatives.
        - Related issues are NOT duplicates. Similar symptoms are NOT duplicates.
        - You MUST cite specific shared technical details in your reasoning. Generic reasoning like "exact match", "identical issue", or "same core problem" is NOT acceptable — name the actual shared details.
        #{target.number ? "" : "- The target issue only has a title/brief description. Be EXTRA conservative. Titles are often ambiguous and similar titles frequently describe different underlying problems."}

        You **must** respond with valid JSON containing results for ALL candidates in this exact format:
        {
          "results": [
            {
              "repository_nwo": "#{current_repository.name_with_display_owner}",
              "issue_number": #{candidates.first&.issue&.number || 123},
              "is_duplicate": true,
              "confidence_score": 0.85,
              "shared_root_cause": "Connection pool exhaustion due to unclosed database connections in batch processing",
              "same_fix": true,
              "distinguishing_details_found": false,
              "reasoning": "Both issues report connection timeout errors after processing large batches, stack traces show the same connection pool cleanup bug, and both mention PostgreSQL specifically"
            },
            {
              "repository_nwo": "#{current_repository.name_with_display_owner}",
              "issue_number": #{candidates.last&.issue&.number || 124},
              "is_duplicate": false,
              "confidence_score": 0.2,
              "shared_root_cause": null,
              "same_fix": false,
              "distinguishing_details_found": true,
              "reasoning": "Different root causes: target issue involves database timeouts during batch processing, while this candidate reports UI rendering timeouts with no database involvement"
            }
          ]
        }

        Field Definitions:
        - `is_duplicate`: Boolean - true only if all three criteria are met (shared root cause + same fix + no distinguishing details)
        - `confidence_score`: Float between 0.0 and 1.0
          * 0.9-1.0: Very confident (same root cause, same fix clearly identified, multiple shared technical details)
          * 0.7-0.9: Confident (clear shared root cause, same fix likely)
          * 0.5-0.7: Somewhat confident (possible shared root cause, some uncertainty)
          * 0.0-0.5: Low confidence (uncertain, insufficient evidence, or NOT a duplicate)
        - `shared_root_cause`: String or null - Specific technical root cause description; null if different or unknown
        - `same_fix`: Boolean - Would a single code change fix both? False if different fixes needed
        - `distinguishing_details_found`: Boolean - Are there specific details proving these are different problems?
        - `reasoning`: String - For duplicates: cite specific shared technical details. For non-duplicates: explain why they differ

        IMPORTANT: Include a result for EVERY candidate issue listed above, using the exact repository_nwo and issue_number values. Most candidates should be classified as is_duplicate: false with low confidence scores.
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
        shared_root_cause: nil,
        same_fix: nil,
        distinguishing_details_found: nil,
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
      shared_root_cause = parsed_response["shared_root_cause"]&.to_s&.strip.presence
      same_fix = parsed_response["same_fix"].nil? ? nil : coerce_boolean(parsed_response["same_fix"])
      distinguishing_details_found = parsed_response["distinguishing_details_found"].nil? ? nil : coerce_boolean(parsed_response["distinguishing_details_found"])

      DuplicateClassification.new(
        is_duplicate:,
        confidence_score:,
        reasoning:,
        shared_root_cause:,
        same_fix:,
        distinguishing_details_found:,
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

    # Extracts token usage metrics from LLM response hash
    #
    # This method handles the complexity of extracting token counts and detailed
    # breakdowns from Azure OpenAI API responses. It safely handles type checking
    # for both simple Integer values and nested Hash structures using flow-sensitive
    # typing with local variables.
    #
    # Azure OpenAI returns:
    # - Direct Integer values: prompt_tokens, completion_tokens, total_tokens, reasoning_tokens
    # - Nested Hash values: prompt_tokens_details, completion_tokens_details
    #
    # @param llm_usage [Hash] The usage hash from Azure OpenAI response
    # @return [TokenUsage, nil] Structured token metrics or nil if no usage data
    sig { params(llm_usage: T.nilable(T::Hash[String, T.any(Integer, T::Hash[String, Integer])])).returns(T.nilable(TokenUsage)) }
    def parse_token_usage(llm_usage)
      return nil unless llm_usage

      # Extract values to local variables for proper Sorbet flow-sensitive typing
      prompt_tokens_value = llm_usage["prompt_tokens"]
      completion_tokens_value = llm_usage["completion_tokens"]
      total_tokens_value = llm_usage["total_tokens"]
      reasoning_tokens_value = llm_usage["reasoning_tokens"]

      # Extract nested detail hashes
      prompt_details = llm_usage["prompt_tokens_details"]
      prompt_details_hash = prompt_details.is_a?(Hash) ? prompt_details : {}
      cached_tokens_value = prompt_details_hash["cached_tokens"]

      completion_details = llm_usage["completion_tokens_details"]
      completion_details_hash = completion_details.is_a?(Hash) ? completion_details : {}
      accepted_prediction_tokens_value = completion_details_hash["accepted_prediction_tokens"]
      rejected_prediction_tokens_value = completion_details_hash["rejected_prediction_tokens"]

      TokenUsage.new(
        prompt_tokens: prompt_tokens_value.is_a?(Integer) ? prompt_tokens_value : nil,
        completion_tokens: completion_tokens_value.is_a?(Integer) ? completion_tokens_value : nil,
        total_tokens: total_tokens_value.is_a?(Integer) ? total_tokens_value : nil,
        cached_tokens: cached_tokens_value.is_a?(Integer) ? cached_tokens_value : nil,
        reasoning_tokens: reasoning_tokens_value.is_a?(Integer) ? reasoning_tokens_value : nil,
        accepted_prediction_tokens: accepted_prediction_tokens_value.is_a?(Integer) ? accepted_prediction_tokens_value : nil,
        rejected_prediction_tokens: rejected_prediction_tokens_value.is_a?(Integer) ? rejected_prediction_tokens_value : nil
      )
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
  end
end
