# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::SuggestionAcceptanceAnalyzer
  class Analyzer
    include GitHub::Memoizer

    MODEL = "gpt-5-mini"
    MAX_TOKENS = 1000
    TEMPERATURE = 0.2
    CAPI_INITIATOR = "agent"
    SUGGESTION_REGEX = /```suggestion\n(.*?)```/m

    def initialize(pull_request:, request_id: nil)
      @pull_request = pull_request
      @user = pull_request&.user
      @request_id = request_id || GitHub.context[:request_id] || SecureRandom.uuid
    end

    sig { void }
    def analyze
      return if pull_request.nil?

      pull_request.review_comments.authored_by_copilot.each do |comment|
        analyze_suggestion_acceptance(comment)
      end

      return unless async_llm_analysis_enabled? && pr_author_is_human?

      start_time = GitHub::Dogstats.monotonic_time

      comments_to_analyze = pull_request.review_comments.authored_by_copilot.filter { |c| !c.reply? }.to_a.sample(10)

      if analyze_all_comments_enabled?
        comments_to_analyze.concat(pull_request.review_comments.filter { |c| !c.reply? && c.user_id != copilot_bot_id  }.to_a.sample(10))
      end

      # If a comment's original_commit_id matches the current head, it can't
      # influence any changes (no diff since comment). Mark it as ignored and
      # exclude it from LLM analysis.
      ignored_comments, remaining_comments = comments_to_analyze.partition do |comment|
        comment.original_commit_id == pull_request.head_sha
      end

      ignored_comments.each do |comment|
        comment_source = comment.user&.bot? ? comment.user.display_login : "human"
        payload = base_payload(comment).merge(comment_source: comment_source, llm_judgment: "ignored", llm_reasoning: "skipped due to empty diff")
        GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
      end

      analyze_comments_with_llm(remaining_comments)

      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("pr_comment_llm_analysis.total_duration", elapsed)
    end

    private

    attr_reader :pull_request

    sig { returns(T::Boolean) }
    def analyze_all_comments_enabled?
      FeatureFlag.vexi.enabled?(:pr_comment_llm_analysis_all_comments, @user, default: false) && pull_request.repository.public?
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

      first_comment, *remaining_comments = comments

      # Execute one request synchronously first to allow prompt caching to take effect
      perform_llm_judgment_async(first_comment).sync

      return if remaining_comments.empty?

      # Fire off the remaining LLM calls concurrently
      promises = remaining_comments.map do |comment|
        perform_llm_judgment_async(comment)
      end

      Promise.all(promises).sync
    end

    sig { params(comment: T.untyped).returns(Promise[T::Boolean]) }
    def perform_llm_judgment_async(comment)
      start_time = GitHub::Dogstats.monotonic_time
      comment_source = comment.user&.bot? ? comment.user.display_login : "human"
      payload = base_payload(comment).merge(comment_source: comment_source)
      copilot_api_client.async_create_chat_completion(
        model: MODEL,
        messages: build_messages(comment),
        max_tokens: MAX_TOKENS,
        temperature: TEMPERATURE,
        initiator: CAPI_INITIATOR,
      ).then do |response|
        result = parse_llm_response(response)
        payload[:llm_judgment] = result["judgment"]
        payload[:llm_reasoning] = result["reasoning"]
        record_llm_metrics(start_time, true)
        GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
        true
      end.rescue do |e|
        payload[:llm_error] = e.message
        record_llm_metrics(start_time, false)
        GlobalInstrumenter.instrument("copilot.reviews.v0.CommentAnalysis", payload)
        false
      end
    end

    sig { params(comment: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
    def build_messages(comment)
      [
        { role: "developer", content: system_prompt },
        { role: "user", content: build_user_prompt(comment) },
      ]
    end

    sig { params(comment: T.untyped).returns(String) }
    def build_user_prompt(comment)
      thread = comment.pull_request_review_thread
      return "" if thread.nil?

      thread_text = thread.comments.map { |c| "#{c.user.display_login}: #{encode_utf8(c.body)}" }.join("\n")
      thread_text = "#{thread_text}\n" unless thread_text.empty?

      reaction_counts = comment.reactions_count

      user_prompt(
        filepath: comment.path || "",
        diff_hunk: encode_utf8(comment.diff_hunk),
        comment: encode_utf8(comment.body),
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

      message = response.dig("choices", 0, "message", "content") || ""
      message = message.gsub(/\A```\s*json\n*|\n*```\n*\z/, "")

      JSON.parse(message)
    end

    sig { params(start_time: Float, succeeded: T::Boolean).void }
    def record_llm_metrics(start_time, succeeded)
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("pr_comment_llm_analysis.duration", elapsed, tags: ["success:#{succeeded}"])
    end

    sig { params(comment: T.untyped).void }
    def analyze_suggestion_acceptance(comment)
      return unless comment.body_may_contain_suggestion? && comment.outdated?

      suggestion_content = extract_suggestion(comment.body)
      return unless suggestion_content

      diff_entry = pull_request_diff.with_path(comment.path)
      payload = base_payload(comment).merge(language: detect_language(diff_entry))

      if suggestion_fully_applied?(diff_entry, suggestion_content, comment)
        payload[:fully_applied] = true
      else
        unless diff_entry.nil?
          payload[:levenshtein_distance] = GitHub::Levenshtein.similarity(encode_utf8(diff_entry.b_blob), suggestion_content)
        end
      end

      GlobalInstrumenter.instrument("copilot.reviews.v0.SuggestionAnalysis", payload)
    end

    sig { params(body: String).returns(T.nilable(String)) }
    def extract_suggestion(body)
      match = body.match(SUGGESTION_REGEX)
      match&.[](1)&.rstrip
    end

    sig { params(diff_entry: T.untyped, suggestion_content: String, comment: T.untyped).returns(T::Boolean) }
    def suggestion_fully_applied?(diff_entry, suggestion_content, comment)
      diff_entry && encode_utf8(diff_entry.text).include?(suggestion_content) && !comment.left_blob
    end

    sig { params(diff_entry: T.untyped).returns(String) }
    def detect_language(diff_entry)
      return "" unless diff_entry&.b_path

      language = Linguist::Language.find_by_filename(diff_entry.b_path)&.first ||
                 Linguist::Language.find_by_extension(diff_entry.b_path)&.first
      language&.name || ""
    end

    sig { params(comment: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def base_payload(comment)
      {
        request_id: @request_id,
        organization_id: pull_request.owner&.id,
        repository_id: pull_request.repository.id,
        pull_request_id: pull_request.id,
        comment_id: comment.id.to_s,
        analytics_tracking_id: pull_request.user&.analytics_tracking_id,
      }
    end

    memoize def pull_request_diff
      pull_request.diffs
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
- The diff hunk that was commented on
- The review comment left on the diff hunk
- The replies to the comment from the developer and others
- The reactions to the comment from the developer and others
- Whether the comment was marked as resolved
- The diff between the initial pull request and the final merged code
      PROMPT
    end

    sig { params(filepath: String, diff_hunk: String, comment: String, line_number: Integer, thread: String, len_thread: Integer, num_thumbs_up: Integer, num_thumbs_down: Integer, resolved: T::Boolean, merged_diff: String).returns(String) }
    def user_prompt(filepath:, diff_hunk:, comment:, line_number:, thread:, len_thread:, num_thumbs_up:, num_thumbs_down:, resolved:, merged_diff:)
      <<~PROMPT
<filepath>
The file that was commented on is:

#{filepath}
</filepath>

<diff_hunk>
The diff hunk that was commented on is:

#{diff_hunk}
</diff_hunk>

<comment>
The reviewer left the following comment on line #{line_number} of the diff hunk:

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
The diff between the initial pull request and the final merged code is:

#{merged_diff}
</merged_diff>
      PROMPT
    end
  end
end
