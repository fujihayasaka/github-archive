# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::SuggestionAcceptanceAnalyzer
  class Analyzer
    include GitHub::Memoizer
    include PullRequests::Copilot::CodeReview::LlmBatching

    MODEL = "gpt-5.4-mini"
    MAX_TOKENS = 1000
    REASONING_EFFORT = "low"
    CAPI_INITIATOR = "agent"
    COMMENT_SAMPLE_SIZE = 10

    def initialize(pull_request:, request_id: nil)
      @pull_request = pull_request
      @user = pull_request&.user
      @request_id = request_id || GitHub.context[:request_id] || SecureRandom.uuid
    end

    sig { void }
    def analyze
      return if pull_request.nil?
      return unless async_llm_analysis_enabled? && pr_author_is_human?

      start_time = GitHub::Dogstats.monotonic_time

      copilot_comments = pull_request.review_comments.authored_by_copilot.includes(:automated_review_comment).filter { |c| !c.reply? }.to_a.sample(COMMENT_SAMPLE_SIZE)
      comments_to_analyze = copilot_comments

      if analyze_all_comments_enabled?
        non_copilot_comments = pull_request.review_comments.includes(:automated_review_comment).filter { |c| !c.reply? && c.user_id != copilot_bot_id }.to_a
        bot_comments = non_copilot_comments.select { |c| c.user&.bot? }
        human_comments = non_copilot_comments.reject { |c| c.user&.bot? }

        # Prioritize non-Copilot bot comments, fill remaining slots with human comments
        sampled = bot_comments.sample(COMMENT_SAMPLE_SIZE)
        remaining_slots = COMMENT_SAMPLE_SIZE - sampled.size
        sampled.concat(human_comments.sample(remaining_slots)) if remaining_slots > 0 && analyze_human_comments_enabled?

        comments_to_analyze = comments_to_analyze.concat(sampled)
      end

      if refined_prompt_enabled?
        analyze_comments_with_llm(comments_to_analyze)
      else
        # Legacy path: pre-skip comments whose original_commit_id matches the
        # current head (no diff since the comment was left), marking them as
        # ignored without an LLM call.
        ignored_comments, remaining_comments = comments_to_analyze.partition do |comment|
          comment.original_commit_id == pull_request.head_sha
        end

        ignored_comments.each do |comment|
          comment_source = comment.user&.bot? ? comment.user.display_login : "human"
          reasoning = redact_comment_details?(comment) ? nil : "skipped due to empty diff"
          payload = base_payload(comment).merge(comment_source: comment_source, llm_judgment: "ignored", llm_reasoning: reasoning)
          GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
        end

        analyze_comments_with_llm(remaining_comments)
      end

      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("pr_comment_llm_analysis.total_duration", elapsed)
    end

    private

    attr_reader :pull_request

    sig { returns(T::Boolean) }
    def analyze_all_comments_enabled?
      FeatureFlag.vexi.enabled?(:pr_comment_llm_analysis_all_comments, @user, default: false)
    end

    sig { returns(T::Boolean) }
    def analyze_human_comments_enabled?
      FeatureFlag.vexi.enabled?(:pr_comment_llm_analysis_human_comments, @user, default: false)
    end

    sig { returns(T::Boolean) }
    def refined_prompt_enabled?
      FeatureFlag.vexi.enabled?(:pr_comment_llm_analysis_refined_prompt, @user, default: false)
    end

    memoize def copilot_bot_id
      copilot_pull_request_reviewer_app&.bot&.id
    end

    sig { returns(T::Boolean) }
    def async_llm_analysis_enabled?
      FeatureFlag.vexi.enabled?(:pr_comment_llm_analysis_async, @user, default: false)
    end

    sig { returns(T::Boolean) }
    def pr_author_is_human?
      @user.present? && @user.user?
    end

    sig { params(comments: T::Array[T.untyped]).void }
    def analyze_comments_with_llm(comments)
      return if comments.empty?

      run_llm_batched(comments) do |comment|
        perform_llm_judgment_async(comment)
      end
    end

    sig { params(comment: T.untyped).returns(Promise[T::Boolean]) }
    def perform_llm_judgment_async(comment)
      start_time = GitHub::Dogstats.monotonic_time
      comment_source = comment.user&.bot? ? comment.user.display_login : "human"
      payload = base_payload(comment).merge(comment_source: comment_source)
      create_llm_request(comment).then do |response|
        result = parse_llm_response(response)
        payload[:llm_judgment] = result["judgment"]
        payload[:llm_reasoning] = redact_comment_details?(comment) ? nil : result["reasoning"]
        record_llm_metrics(start_time, true)
        GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
        true
      end.rescue do |e|
        payload[:llm_error] = redact_comment_details?(comment) ? "error" : e.message
        record_llm_metrics(start_time, false)
        GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
        false
      end
    end

    sig { params(comment: T.untyped).returns(Promise[T.untyped]) }
    def create_llm_request(comment)
      copilot_api_client.async_create_response(
        model: MODEL,
        input: [{ role: "user", content: build_user_prompt(comment) }],
        instructions: system_prompt,
        max_output_tokens: MAX_TOKENS,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => "pr_comment_llm_analysis" },
      )
    end

    sig { params(comment: T.untyped).returns(String) }
    def build_user_prompt(comment)
      thread = comment.pull_request_review_thread
      return "" if thread.nil?

      thread_text = thread.comments.map { |c| "#{c.user.display_login}: #{encode_utf8(c.body)}" }.join("\n")
      thread_text = "#{thread_text}\n" unless thread_text.empty?

      reaction_counts = comment.reactions_count

      comment_author = comment.user&.display_login || "unknown"
      pr_author = pull_request.user&.display_login || "unknown"

      user_prompt(
        filepath: comment.path || "",
        diff_hunk: encode_utf8(comment.diff_hunk),
        comment: encode_utf8(comment.body),
        comment_author: comment_author,
        pr_author: pr_author,
        line_number: comment.async_line.sync || 0,
        thread: thread_text,
        len_thread: thread.comments.size,
        num_thumbs_up: reaction_counts["+1"] || 0,
        num_thumbs_down: reaction_counts["-1"] || 0,
        resolved: thread.resolved?,
        merged_diff: pull_request_diff_text(comment),
      )
    end

    sig { params(response: T.untyped).returns(T::Hash[String, T.untyped]) }
    def parse_llm_response(response)
      response = response.sync if response.is_a?(ConcurrentFaraday::FutureResponse)

      message = PullRequests::Copilot::CodeReview::LlmResponseParser.extract_text(response)
      message = message.gsub(/\A```\s*json\n*|\n*```\n*\z/, "")

      JSON.parse(message)
    end

    sig { params(start_time: Float, succeeded: T::Boolean).void }
    def record_llm_metrics(start_time, succeeded)
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("pr_comment_llm_analysis.duration", elapsed, tags: ["success:#{succeeded}"])
    end

    sig { params(comment: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def base_payload(comment)
      if redact_comment_details?(comment)
        {
          request_id: @request_id,
        }
      else
        {
          request_id: @request_id,
          organization_id: pull_request.owner&.id,
          repository_id: pull_request.repository.id,
          pull_request_id: pull_request.id,
          comment_id: comment.id.to_s,
          # CCRA-generated comment identifier (mirrors `comment_identifier`
          # on `copilot.reviews.v0.ReviewComment`), persisted on the
          # associated `AutomatedReviewComment` at comment-creation time.
          # Nil for human comments and any pre-AutomatedReviewComment-era
          # rows; dropped via `metadata.compact` downstream. Enables
          # cross-event correlation with CCRA-emitted ReviewComment events
          # without a join. Subject to the same `redact_comment_details?`
          # gate as `comment_id`.
          comment_identifier: comment.automated_review_comment&.resource_id,
          analytics_tracking_id: pull_request.user&.analytics_tracking_id,
          review_id: comment.pull_request_review_id,
        }
      end
    end

    sig { params(comment: T.untyped).returns(T::Boolean) }
    def redact_comment_details?(comment)
      !pull_request.repository.public? && comment.user_id != copilot_bot_id
    end

    sig { params(comment: T.untyped).returns(String) }
    def pull_request_diff_text(comment)
      diffs = pull_request.build_comparison(head_commit_oid: pull_request.head_sha, base_commit_oid: comment.original_commit_id).diffs
      entries = diffs.map do |diff_entry|
        # gather some debugging stats if any of the texts are nil
        if diff_entry.header_text.nil? || diff_entry.extended_header_text.nil? || diff_entry.unicode_text.nil?
          GitHub.logger.warn(
            "SuggestionAcceptanceAnalyzer: missing diff entry texts",
            header_text_empty: diff_entry.header_text.nil?,
            extended_header_text_empty: diff_entry.extended_header_text.nil?,
            unicode_text_empty: diff_entry.unicode_text.nil?,
          )
        end
        "#{diff_entry.header_text}#{diff_entry.extended_header_text}#{diff_entry.unicode_text}"
      end

      return "" if entries.empty?

      entries.join("\n") + "\n"
    end

    sig { params(str: T.nilable(String)).returns(String) }
    def encode_utf8(str)
      return "" if str.nil?

      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    def copilot_pull_request_reviewer_app
      return @app if defined?(@app)
      @app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    end

    memoize def copilot_api_client
      new_access = copilot_pull_request_reviewer_app.grant(@user, entry_point: :pull_requests_copilot_code_review_suggestion_acceptance_analyzer)
      access, _ = new_access.redeem(extended_expiry: true)
      token = Copilot::DecryptedToken.from(access)

      ::Copilot::User.copilot_api(
        user: @user,
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        request_id: @request_id,
        token: token,
      )
    end

    sig { returns(String) }
    def system_prompt
      <<~PROMPT
You are evaluating whether a pull request (PR) review comment was addressed before the pull request was merged.

Label each comment with exactly one of the following:

1. **addressed** - The content was changed in a way that addresses the underlying problem or concern raised in the comment. If the content was not changed, but the developer or another participant indicated the comment was valid and will be addressed later or in another PR, then also choose this option.
2. **false_positive** - The developer or another participant commented or otherwise indicated that the comment was incorrect, invalid, or unnecessary.
3. **ignored** - The comment was neither addressed nor indicated to be incorrect, invalid, or unnecessary. The content was not changed in any way that was influenced by the comment, and no one indicated an intention to address the comment now or in the future.

Respond with this exact JSON format:
{
  "reasoning": "<a brief explanation of your judgment>",
  "judgment": "<one of: addressed, false_positive, ignored>"
}

You will be provided with the following information:
- The pull request author
- The diff hunk that was commented on
- The review comment and its author
- The replies to the comment from the developer and others
- The reactions to the comment from the developer and others
- Whether the comment was marked as resolved
- The diff between the initial pull request and the final merged code
      PROMPT
    end

    sig { params(filepath: String, diff_hunk: String, comment: String, comment_author: String, pr_author: String, line_number: Integer, thread: String, len_thread: Integer, num_thumbs_up: Integer, num_thumbs_down: Integer, resolved: T::Boolean, merged_diff: String).returns(String) }
    def user_prompt(filepath:, diff_hunk:, comment:, comment_author:, pr_author:, line_number:, thread:, len_thread:, num_thumbs_up:, num_thumbs_down:, resolved:, merged_diff:)
      merged_diff_section = if refined_prompt_enabled?
        merged_diff.empty? ? "There were no commits between when the comment was left and when the PR was merged, so there is no merged diff to inspect." : "The diff between the initial pull request and the final merged code is:\n\n#{merged_diff}"
      else
        "The diff between the initial pull request and the final merged code is:\n\n#{merged_diff}"
      end

      <<~PROMPT
<context>
The pull request was authored by #{pr_author}.
</context>

<filepath>
The file that was commented on is:

#{filepath}
</filepath>

<diff_hunk>
The diff hunk that was commented on is:

#{diff_hunk}
</diff_hunk>

<comment>
#{comment_author} left the following review comment on line #{line_number} of the diff hunk:

#{comment}
</comment>

<thread>
The comment received the following #{len_thread} replies, ordered from earliest to most recent, from the developer and others:

#{thread}
</thread>

<reactions>
The comment received the following reactions from the developer and others:

Number of thumbs up: #{num_thumbs_up}
Number of thumbs down: #{num_thumbs_down}
</reactions>

<resolved>
#{resolved ? "The comment was marked as resolved." : "The comment was not marked as resolved."}
</resolved>

<merged_diff>
#{merged_diff_section}
</merged_diff>
      PROMPT
    end
  end
end
