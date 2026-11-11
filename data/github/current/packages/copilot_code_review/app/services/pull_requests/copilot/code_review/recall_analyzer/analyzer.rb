# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::RecallAnalyzer
  class Analyzer
    include GitHub::Memoizer
    include PullRequests::Copilot::CodeReview::LlmBatching

    DOGSTATS_PREFIX = "pr_recall_llm_analysis"
    MODEL = "gpt-5.4-mini"
    MAX_TOKENS = 1024
    MAX_TOKENS_D5 = 2048
    # Per-diff character cap for D5 extraction prompts. Diffs longer than this
    # are truncated; the diff_fn.truncated metric tracks how often that happens
    # so we can quantify FN undercounting on large PRs.
    MAX_DIFF_CHARS = 15_000
    # Valid extraction confidence levels. The LLM is prompted to return one of
    # these; anything else is bucketed as "unknown" to keep Datadog tag
    # cardinality bounded.
    CONFIDENCE_LEVELS = T.let(%w[high medium low].freeze, T::Array[String])
    REASONING_EFFORT = "low"
    CAPI_INITIATOR = "agent"

    # Lightweight eligibility check for gating job enqueue.
    # No LLM calls, no git operations — just FF + DB reads.
    #
    # subject_user_id is the bot under evaluation (CCR by default). The "other"
    # pool against which the subject is measured is everyone-except-subject —
    # so for CCR that's humans + competitor bots, and for a competitor bot
    # that's humans + CCR + other competitors.
    sig { params(pull_request: PullRequest, subject_user_id: T.nilable(Integer)).returns(T::Boolean) }
    def self.eligible?(pull_request, subject_user_id = nil)
      user = pull_request.user
      return false if user.nil?
      return false unless user.user?

      subject_user_id ||= ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id
      return false if subject_user_id.nil?

      has_subject_review = pull_request.reviews
        .where(user_id: subject_user_id)
        .where.not(submitted_at: nil)
        .exists?
      return false unless has_subject_review

      has_other_comments = pull_request.review_comments
        .where.not(user_id: subject_user_id)
        .exists?
      has_diff_fn = FeatureFlag.vexi.enabled?(:pr_recall_diff_fn_analysis, user, default: false)
      return false unless has_other_comments || has_diff_fn

      true
    end

    sig { params(pull_request: PullRequest, request_id: T.nilable(String), subject_user_id: T.nilable(Integer)).void }
    def initialize(pull_request:, request_id: nil, subject_user_id: nil)
      @pull_request = pull_request
      @user = pull_request.user
      @request_id = request_id || GitHub.context[:request_id] || SecureRandom.uuid
      @subject_user_id_override = subject_user_id
    end

    sig { void }
    def analyze
      return unless pr_author_is_human?
      return if subject_user_id.nil?
      return unless user_has_copilot_access?

      start_time = GitHub::Dogstats.monotonic_time

      subject_reviews = find_subject_reviews
      return if subject_reviews.empty?

      # Use earliest review for noise filter timing and as the default for base_payload
      @subject_review = T.must(subject_reviews.first)

      all_comments = @pull_request.review_comments.to_a
      # Collect subject comments from ALL reviews for the dedup comparison
      subject_review_ids = Set.new(subject_reviews.map(&:id))
      subject_comments = all_comments.select { |c| subject_review_ids.include?(c.pull_request_review_id) && c.path.present? }
      return if subject_comments.empty?

      other_comments = all_comments.select { |c| c.user_id != subject_user_id && c.path.present? }

      eligible_count = 0
      sha_eligible_count = 0

      # D1–D3 + subject passes: reviewer-based FN detection (only when other reviewers commented)
      if other_comments.any?
        # Noise filter uses earliest subject review's submitted_at (most permissive)
        eligible_comments = noise_filter(other_comments, @subject_review)
        eligible_count = eligible_comments.size

        eligible_comments.each do |comment|
          publish_recall_event(comment, stage: "noise_filter", outcome: "passed")
        end

        # SHA eligibility: pass if ANY subject review's diff included the file
        sha_eligible_comments = sha_eligibility_filter_multi(eligible_comments, subject_reviews)
        sha_eligible_count = sha_eligible_comments.size

        sha_eligible_comments.each do |comment|
          publish_recall_event(comment, stage: "sha_eligibility", outcome: "passed")
        end

        addressed_comments = analyze_addressed(sha_eligible_comments)

        # Apply the same noise filter to subject comments that we apply to the
        # non-subject pool, so dedup (FN signal) and the subject self-judge pass
        # (TP signal) operate on a consistent eligible set.
        subject_eligible_comments = noise_filter(subject_comments, @subject_review, publish_events: false)

        analyze_dedup(addressed_comments, subject_eligible_comments)

        if addressed_comments.any?
          analyze_addressed(subject_eligible_comments)
        end
      end

      # D5: Diff-based FN detection — identify issues fixed in post-review
      # commits that the subject never flagged. Unlike D1–D3 which rely on
      # other reviewers' comments as ground truth, D5 uses the post-review
      # diff itself. FNs from both sources coexist (tagged by stage) so the
      # dashboard can show reviewer-based recall, diff-based recall, or both.
      if diff_fn_enabled?
        analyze_diff_fns(subject_reviews, subject_comments)
      end

      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.duration", elapsed)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.eligible_comments", eligible_count)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.sha_eligible_comments", sha_eligible_count)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.total_other_comments", other_comments.size)
    end

    private

    sig { returns(T::Boolean) }
    def pr_author_is_human?
      @user.present? && @user.user?
    end

    sig { returns(T::Boolean) }
    def user_has_copilot_access?
      user = @user
      return false if user.nil?

      copilot_user = ::Copilot::Public::User.for(user)
      has_access = copilot_user.has_copilot_access?
      unless has_access
        GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.skipped", tags: ["reason:no_copilot_access"])
      end
      has_access
    end

    # Find all subject-bot reviews on this PR, ordered earliest first.
    # SHA eligibility is checked against all reviews (union).
    # See github/copilot-code-review#2460 for the methodology rationale.
    sig { returns(T::Array[PullRequestReview]) }
    def find_subject_reviews
      return [] if subject_user_id.nil?

      @pull_request.reviews
        .where(user_id: subject_user_id)
        .where.not(submitted_at: nil)
        .order(submitted_at: :asc)
        .to_a
    end

    # Noise filter — deterministic eligibility stage.
    #
    # Drops comments that are:
    # 1. Replies to other comments (in_reply_to_id set)
    # 2. Written by the PR author
    # 3. Shorter than 20 characters
    # 4. Posted by another reviewer before the subject's review was submitted
    #    (the subject could not have addressed something they had not yet seen).
    #    Comments from the subject themselves are exempt from this rule — a
    #    review's own comments trivially predate its submitted_at timestamp by
    #    construction (e.g. CCR creates all comments then sets submitted_at in
    #    one transaction), so the ordering check is meaningless for them.
    #
    # When publish_events is false, drops happen silently. Used by the
    # subject self-judge pass to avoid shifting the dashboard funnel counts,
    # which are scoped to the non-subject comment pool.
    sig { params(comments: T::Array[PullRequestReviewComment], subject_review: PullRequestReview, publish_events: T::Boolean).returns(T::Array[PullRequestReviewComment]) }
    def noise_filter(comments, subject_review, publish_events: true)
      pr_author_id = @pull_request.user_id
      subject_user_id = subject_review.user_id
      subject_submitted_at = subject_review.submitted_at

      comments.select do |comment|
        reason = noise_filter_reason(comment, pr_author_id, subject_user_id, subject_submitted_at)
        if reason
          if publish_events
            publish_recall_event(comment, stage: "noise_filter", outcome: reason)
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.dropped", tags: ["stage:noise_filter", "reason:#{reason}"])
          end
          false
        else
          true
        end
      end
    end

    sig { params(comment: PullRequestReviewComment, pr_author_id: T.nilable(Integer), subject_user_id: T.nilable(Integer), subject_submitted_at: T.nilable(Time)).returns(T.nilable(String)) }
    def noise_filter_reason(comment, pr_author_id, subject_user_id, subject_submitted_at)
      return "reply" if comment.reply?
      return "pr_author" if comment.user_id == pr_author_id
      return "too_short" if comment.body.to_s.strip.length < 20
      if subject_submitted_at && comment.user_id != subject_user_id && comment.created_at < subject_submitted_at
        return "pre_subject_review"
      end
      nil
    end

    # SHA eligibility across multiple subject reviews.
    #
    # A comment is eligible if ANY subject review's diff included its file.
    # This implements the union-based eligibility from the research notebook:
    # each non-subject comment is checked against every subject review's
    # head_sha, and passes if eligible against any of them.
    sig { params(comments: T::Array[PullRequestReviewComment], subject_reviews: T::Array[PullRequestReview]).returns(T::Array[PullRequestReviewComment]) }
    def sha_eligibility_filter_multi(comments, subject_reviews)
      # Build the union of diff paths across all subject reviews
      all_diff_paths = Set.new
      any_diff_succeeded = T.let(false, T::Boolean)

      subject_reviews.each do |review|
        paths = subject_review_diff_paths(review)
        next if paths.nil?

        any_diff_succeeded = true
        all_diff_paths.merge(paths)
      end

      unless any_diff_succeeded
        comments.each do |comment|
          publish_recall_event(comment, stage: "sha_eligibility", outcome: "diff_unavailable")
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.dropped", tags: ["stage:sha_eligibility", "reason:diff_unavailable"])
        end
        return []
      end

      comments.select do |comment|
        if all_diff_paths.include?(comment.path || "")
          true
        else
          publish_recall_event(comment, stage: "sha_eligibility", outcome: "file_not_in_subject_diff")
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.dropped", tags: ["stage:sha_eligibility", "reason:file_not_in_subject_diff"])
          false
        end
      end
    end

    # Build the set of file paths that were in the diff the subject reviewed.
    # Uses the subject review's merge_base_sha (falling back to the PR's
    # current base_sha) and the review's head SHA to reconstruct the reviewed
    # diff.
    sig { params(subject_review: PullRequestReview).returns(T.nilable(T::Set[String])) }
    def subject_review_diff_paths(subject_review)
      subject_head_sha = subject_review.head_sha
      return nil if subject_head_sha.blank?

      base_sha = subject_review.merge_base_sha || @pull_request.base_sha

      comparison = @pull_request.build_comparison(
        head_commit_oid: subject_head_sha,
        base_commit_oid: base_sha,
      )
      return nil if comparison.nil?

      paths = Set.new
      comparison.diffs.each do |diff_entry|
        paths << diff_entry.path
      end
      paths
    rescue StandardError => e
      GitHub.logger.warn("recall_analyzer: failed to build subject review diff",
        "gh.pull_request.id" => @pull_request.id,
        "error" => e.message,
      )
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.dropped", tags: ["stage:sha_eligibility", "reason:diff_error"])
      nil
    end

    # D2: Addressed judge — LLM pass
    #
    # Determines whether a comment was addressed before merge. Runs on both:
    #
    # - Non-subject comments (called after SHA eligibility). Only "addressed"
    #   comments are potential false negatives — they're returned so they can
    #   be passed to D3 dedup.
    # - The subject's own comments (called after D3 dedup). These are the
    #   per-subject TP signal for recall. The returned array is unused in
    #   this mode; only the published events matter.
    #
    # Disambiguate the two cohorts at query time via `comment_source` vs
    # `subject_reviewer_login` on the published event (subject pass:
    # comment_source == subject_reviewer_login, non-subject pass: !=).
    sig { params(comments: T::Array[PullRequestReviewComment]).returns(T::Array[PullRequestReviewComment]) }
    def analyze_addressed(comments)
      return [] if comments.empty?

      results = run_llm_batched(comments) do |comment|
        perform_addressed_judgment_async(comment)
      end

      # Return only comments where the LLM judged addressed=true
      comments.zip(results).filter_map { |comment, addressed| comment if addressed }
    end

    sig { params(comment: PullRequestReviewComment).returns(Promise[T::Boolean]) }
    def perform_addressed_judgment_async(comment)
      start_time = GitHub::Dogstats.monotonic_time

      request = create_addressed_llm_request(comment)
      if request.nil?
        publish_recall_event(comment, stage: "addressed", outcome: "llm_error")
        record_llm_metrics(start_time, false, stage: "addressed")
        return Promise.new.fulfill(false)
      end

      request.then do |response|
        result = parse_llm_response(response)
        judgment = result["addressed"]
        confidence = result["confidence"]
        comment_type = result["type"]
        severity = result["severity"]

        publish_recall_event(comment, stage: "addressed", outcome: judgment.to_s,
          llm_judgment: judgment,
          llm_confidence: confidence,
          llm_comment_type: comment_type,
          llm_severity: severity,
          llm_reasoning: result["reason"],
        )
        record_llm_metrics(start_time, true, stage: "addressed")
        judgment == true
      end.rescue do |e|
        publish_recall_event(comment, stage: "addressed", outcome: "llm_error")
        record_llm_metrics(start_time, false, stage: "addressed")
        GitHub.logger.warn("recall_analyzer: addressed judge LLM error",
          "gh.pull_request.id" => @pull_request.id,
          "error" => e.message,
        )
        false
      end
    end

    sig { params(comment: PullRequestReviewComment).returns(T.nilable(Promise[T.untyped])) }
    def create_addressed_llm_request(comment)
      client = copilot_api_client
      return nil if client.nil?

      client.async_create_response(
        model: MODEL,
        input: [{ role: "user", content: build_addressed_user_prompt(comment) }],
        instructions: addressed_system_prompt,
        max_output_tokens: MAX_TOKENS,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => DOGSTATS_PREFIX },
      )
    end

    sig { returns(String) }
    def addressed_system_prompt
      <<~PROMPT
        You are an expert code reviewer analyzing whether a PR review comment was addressed in subsequent commits. You will be given:
        1. The review comment (body, file path, line number, diff hunk)
        2. Reply thread from other reviewers (if any)
        3. Subsequent commits that touched the relevant file (if any)
        4. The diff of the relevant file between the review commit and the merged commit

        A comment is "addressed" if:
        - A subsequent commit changed the relevant code to fix the issue described
        - A reply from the PR author or another reviewer acknowledges the finding as valid, even if the fix is deferred to a follow-up PR/issue

        A comment is NOT addressed if:
        - A reply dismisses or disagrees with the comment ("this isn't an issue", "intentional", "won't fix")
        - No relevant changes were made and no acknowledgment exists
        - The changes are ambiguous and don't clearly relate to the comment

        Confidence guidelines:
        - "high": The diff clearly shows a targeted fix for the exact issue described, OR a reply explicitly acknowledges with clear intent (e.g., "fixed", "good catch, will update")
        - "medium": The diff contains changes in the right area that likely address the comment, but the connection is not unambiguous (e.g., a broader refactor that also happens to fix the issue)
        - "low": The comment describes an issue that COULD have been addressed in a different file, a later commit with a generic message (e.g., "address PR feedback"), or through changes you cannot fully verify from the provided context. Also use "low" when the only evidence is indirect — such as the problematic code being deleted or moved without clear indication of where it went, or when the fix might exist outside the scope of the file diff provided.

        When in doubt, prefer "low" confidence over guessing. A "low" confidence addressed result is more useful than a wrong "high" confidence one.

        ## Classification

        Independently of the addressed verdict, also label the comment with a `type` and a `severity`. These labels describe the *reviewer's comment itself* — not whether it was addressed. Pick exactly one value from each list.
        This taxonomy mirrors the one CCR uses for its own comments, so the labels are directly comparable across the TP (CCR) and FN (reviewer) sides.

        `type` (what kind of issue is the reviewer flagging):
        - "bug": Only include errors where the code logic is clearly broken, e.g., unreachable code, misuse of APIs, or operations guaranteed to produce an unintended outcome or result in inaccurate behavior.
        - "naming": Highlight newly introduced variables, classes, functions, or test cases that have inconsistent, ambiguous, or unclear names.
        - "error_message": Point out unclear or unhelpful new or updated error messages.
        - "spelling": Identify spelling or grammatical errors in newly added or updated code, comments, error messages, or documentation.
        - "test_coverage": Highlight behavior in new or updated code that lacks adequate test coverage. Link your comment to the line where the uncovered behavior is introduced. Only do this if there is test coverage for other functions in the same file as the new or updated code, or if the new code is in a new file and other similar files have test coverage.
        - "performance": Code changes that could impact performance through inefficient algorithms, unnecessary computations, N+1 query patterns, or potential bottlenecks in resource usage.
        - "documentation": Highlight critical issues related to code documentation including incorrect, outdated, or unclear comments/docstrings for functions, classes, modules, or public APIs. This includes insufficient explanation of complex logic, undocumented assumptions, or inconsistencies between code and its documentation.
        - "maintainability": Issues affecting code maintainability including duplicated logic, excessive complexity, unexplained magic numbers, or unclear control flow. Assess how changes might affect future development, and comment on potential issues that could arise from these changes. Describe alternative approaches that would be more maintainable.
        - "operational_implications": Consider scalability, reliability, and other operational implications of the changes. If the changes will have a detrimental effect on any of these aspects, explain why and how, and suggest alternatives.
        - "api_design": Problems with API design such as breaking changes, inconsistent parameter patterns, poorly designed interfaces, missing input validation, or ambiguous return values that could confuse API consumers.
        - "security": Security concerns including inadequate input validation, missing authentication/authorization checks, potential data exposure, CSRF/XSS vulnerabilities, or insecure default configurations.
        - "concurrency": Concurrency-related issues such as potential race conditions, deadlock scenarios, thread safety problems, or inefficient resource sharing patterns in multi-threaded code.
        - "best_practices": Violations of established best practices, deviations from project style guides, implementation of known anti-patterns, or incorrect usage of framework features.
        - "accessibility": Accessibility concerns that impact users with disabilities, such as missing screen reader support, keyboard navigation issues, or insufficient color contrast in UI elements.
        - "nonexistent_version": Versions of packages that do not exist, or are not valid. This includes versions of libraries, languages, or tools that you are not aware of.
        - "braces": Comments about incorrectly placed, extra or missing brackets or parentheses.
        - "discrepancy_with_pr_description": If there are significant discrepancies between the PR description and the code changes, note them in a comment. Associate this comment with a specific line in the diff, even if it's not directly related to that line. If you can determine whether it is the PR description or the code changes that are incorrect, please note that in the comment.
        - "future_dates": Comments about dates being in the future.
        - "unprofessional": Comments about code, comments, or naming being unprofessional.

        `severity` (how impactful the comment is if left unaddressed). Must be one of: "nit", "moderate", "critical".
        - "nit": A minor problem or style/preference suggestion that does not impact functionality.
        - "moderate": A problem that should be addressed.
        - "critical": A problem that must be addressed.

        Respond with a single fenced JSON block. Output nothing else.
        ```json
        {
          "addressed": true,
          "confidence": "high",
          "reason": "brief explanation",
          "type": "bug",
          "severity": "critical"
        }
        ```
      PROMPT
    end

    sig { params(comment: PullRequestReviewComment).returns(String) }
    def build_addressed_user_prompt(comment)
      thread = comment.pull_request_review_thread
      reply_text = if thread
        replies = thread.comments.reject { |c| c.id == comment.id }
        replies.map { |c| "**#{c.user&.display_login || 'unknown'}**: #{encode_utf8(c.body)}" }.join("\n")
      end

      diff_text = addressed_diff_text(comment)
      line_number = T.unsafe(comment).async_line.sync || T.unsafe(comment).async_original_line.sync
      hunk = T.unsafe(comment).async_diff_hunk.sync

      parts = [
        "## Review Comment",
        "**File**: #{comment.path}",
        "**Line**: #{line_number || '?'}",
        "**Body**:\n#{encode_utf8(comment.body)}",
      ]

      if hunk.present?
        parts << "\n**Diff hunk at time of review**:\n```\n#{hunk}\n```"
      end

      parts << "\n## Reply Thread"
      parts << (reply_text.present? ? reply_text : "(no replies)")

      if diff_text.present?
        parts << "\n## File Diff (review commit → branch tip)\n```diff\n#{diff_text}\n```"
      else
        parts << "\n## File Diff\nNo changes to this file between the review and the branch tip."
      end

      parts << "\nWas this comment addressed before merge? Respond with the JSON block."
      parts.join("\n")
    end

    # Build the diff between the comment's commit and the merged HEAD,
    # scoped to the file the comment was left on.
    sig { params(comment: T.untyped).returns(String) }
    def addressed_diff_text(comment)
      original_commit = comment.original_commit_id || comment.commit_id
      return "" if original_commit.blank?

      comparison = @pull_request.build_comparison(
        head_commit_oid: @pull_request.head_sha,
        base_commit_oid: original_commit,
      )
      return "" if comparison.nil?

      relevant_diffs = comparison.diffs.select { |d| d.path == comment.path }
      return "" if relevant_diffs.empty?

      relevant_diffs.map { |d| "#{d.header_text}#{d.extended_header_text}#{d.unicode_text}" }.join("\n")
    rescue StandardError => e
      GitHub.logger.warn("recall_analyzer: failed to build addressed diff",
        "gh.pull_request.id" => @pull_request.id,
        "error" => e.message,
      )
      ""
    end

    # D3: Dedup judge — LLM pass
    #
    # Determines whether a non-subject reviewer's comment duplicates something
    # the subject already flagged. If it's a duplicate, the subject didn't
    # "miss" it, so it's not a false negative.
    sig { params(comments: T::Array[PullRequestReviewComment], subject_comments: T::Array[PullRequestReviewComment]).void }
    def analyze_dedup(comments, subject_comments)
      return if comments.empty? || subject_comments.empty?

      subject_comments_block = format_subject_comments_block(subject_comments)

      run_llm_batched(comments) do |comment|
        perform_dedup_judgment_async(comment, subject_comments_block)
      end
    end

    sig { params(comment: PullRequestReviewComment, subject_comments_block: String).returns(Promise[T::Boolean]) }
    def perform_dedup_judgment_async(comment, subject_comments_block)
      start_time = GitHub::Dogstats.monotonic_time

      request = create_dedup_llm_request(comment, subject_comments_block)
      if request.nil?
        publish_recall_event(comment, stage: "dedup", outcome: "llm_error")
        record_llm_metrics(start_time, false, stage: "dedup")
        return Promise.new.fulfill(false)
      end

      request.then do |response|
        result = parse_llm_response(response)
        duplicate = result["duplicate"]
        # Prompt asks for "subject_comment_id"; legacy "ccr_comment_id" key
        # is read as a fallback so an in-flight CCR-tuned prompt response
        # doesn't drop the dedup hit ID on the floor during the rollout.
        subject_comment_id = (result["subject_comment_id"] || result["ccr_comment_id"])&.to_s
        confidence = result["confidence"]

        publish_recall_event(comment, stage: "dedup", outcome: duplicate ? "duplicate" : "unique",
          llm_judgment: duplicate,
          llm_confidence: confidence,
          llm_reasoning: result["reason"],
          llm_subject_comment_id: subject_comment_id,
        )
        record_llm_metrics(start_time, true, stage: "dedup")
        true
      end.rescue do |e|
        publish_recall_event(comment, stage: "dedup", outcome: "llm_error")
        record_llm_metrics(start_time, false, stage: "dedup")
        GitHub.logger.warn("recall_analyzer: dedup judge LLM error",
          "gh.pull_request.id" => @pull_request.id,
          "error" => e.message,
        )
        false
      end
    end

    sig { params(comment: PullRequestReviewComment, subject_comments_block: String).returns(T.nilable(Promise[T.untyped])) }
    def create_dedup_llm_request(comment, subject_comments_block)
      client = copilot_api_client
      return nil if client.nil?

      client.async_create_response(
        model: MODEL,
        input: [{ role: "user", content: build_dedup_user_prompt(comment, subject_comments_block) }],
        instructions: dedup_system_prompt,
        max_output_tokens: MAX_TOKENS,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => DOGSTATS_PREFIX },
      )
    end

    sig { returns(String) }
    def dedup_system_prompt
      subject = subject_display_name
      <<~PROMPT
        You are an expert code reviewer deciding whether a reviewer's comment substantively duplicates one of the comments #{subject} already posted on the same pull request.

        The "reviewer" may be a human or another automated review tool (e.g. Cursor, CodeRabbit, Greptile, Copilot Code Review). Treat all of them the same way.

        Two comments duplicate each other if they identify the same underlying issue in the same code, even if their wording differs. They do NOT duplicate just because they touch the same file or function — the underlying defect must match.

        You will be given:
        1. The reviewer's comment (body, file, line, diff hunk).
        2. The complete list of #{subject} comments on this PR (each with file, line, body).

        Decide:
        - Whether any #{subject} comment substantively duplicates the reviewer comment.
        - If yes, which #{subject} comment (by id).
        - Confidence in your judgment.

        Respond with a single fenced JSON block. Output nothing else.
        ```json
        {
          "duplicate": true,
          "subject_comment_id": 123,
          "confidence": "high",
          "reason": "brief explanation"
        }
        ```
        If no #{subject} comment duplicates the reviewer comment, set `duplicate` to false and `subject_comment_id` to null.
      PROMPT
    end

    sig { params(comment: PullRequestReviewComment, subject_comments_block: String).returns(String) }
    def build_dedup_user_prompt(comment, subject_comments_block)
      line_number = T.unsafe(comment).async_line.sync || T.unsafe(comment).async_original_line.sync
      hunk = T.unsafe(comment).async_diff_hunk.sync

      parts = [
        "## Reviewer comment",
        "**File**: #{comment.path}",
        "**Line**: #{line_number || '?'}",
        "**Body**:\n#{encode_utf8(comment.body)}",
      ]

      if hunk.present?
        parts << "\n**Diff hunk**:\n```\n#{hunk}\n```"
      end

      parts << "\n## #{subject_display_name} comments on this PR\n#{subject_comments_block}"
      parts << "\nDoes any #{subject_display_name} comment substantively duplicate the reviewer comment? Respond with the JSON block."
      parts.join("\n")
    end

    sig { params(subject_comments: T::Array[PullRequestReviewComment]).returns(String) }
    def format_subject_comments_block(subject_comments)
      return "(none)" if subject_comments.empty?

      blocks = subject_comments.map do |c|
        subject_line = T.unsafe(c).async_line.sync || T.unsafe(c).async_original_line.sync
        "### #{subject_display_name} comment id=#{c.id}  file=#{c.path}  line=#{subject_line || '?'}\n#{encode_utf8(c.body)}"
      end
      blocks.join("\n\n")
    end

    sig { params(response: T.untyped).returns(T::Hash[String, T.untyped]) }
    def parse_llm_response(response)
      response = response.sync if response.is_a?(ConcurrentFaraday::FutureResponse)
      response = response.value if response.is_a?(Promise)

      message = PullRequests::Copilot::CodeReview::LlmResponseParser.extract_text(response)
      message = message.gsub(/\A```\s*json\n*|\n*```\n*\z/, "")

      JSON.parse(message)
    end

    sig { params(start_time: Float, succeeded: T::Boolean, stage: String).void }
    def record_llm_metrics(start_time, succeeded, stage:)
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.llm_duration", elapsed, tags: ["stage:#{stage}", "success:#{succeeded}"])
    end

    memoize def copilot_api_client
      return nil if @user.nil?

      integration = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
      return nil if integration.nil?

      new_access = integration.grant(T.must(@user), entry_point: :pull_requests_copilot_code_review_recall_analyzer)
      access, _ = new_access.redeem(extended_expiry: true)
      token = Copilot::DecryptedToken.from(access)

      ::Copilot::User.copilot_api(
        user: T.must(@user),
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        request_id: @request_id,
        token: token,
      )
    end

    sig { params(comment: PullRequestReviewComment, stage: String, outcome: String, llm_judgment: T.nilable(T::Boolean), llm_confidence: T.nilable(String), llm_comment_type: T.nilable(String), llm_severity: T.nilable(String), llm_reasoning: T.nilable(String), llm_subject_comment_id: T.nilable(String)).void }
    def publish_recall_event(comment, stage:, outcome:, llm_judgment: nil, llm_confidence: nil, llm_comment_type: nil, llm_severity: nil, llm_reasoning: nil, llm_subject_comment_id: nil)
      payload = base_payload(comment).merge(
        stage: stage,
        outcome: outcome,
      )
      payload[:llm_judgment] = llm_judgment unless llm_judgment.nil?
      payload[:llm_confidence] = llm_confidence if llm_confidence
      payload[:llm_comment_type] = llm_comment_type if llm_comment_type
      payload[:llm_severity] = llm_severity if llm_severity
      if llm_subject_comment_id
        payload[:llm_subject_comment_id] = llm_subject_comment_id unless redact_competitor_details?
        # Mirror to the legacy llm_ccr_comment_id key only when the subject is
        # CCR, so the v0 dashboard query continues to read populated values
        # without changing during the rollout. For non-CCR subjects we leave
        # llm_ccr_comment_id unset — the dashboard will read the new field.
        payload[:llm_ccr_comment_id] = llm_subject_comment_id if subject_is_ccr?
      end
      payload[:llm_reasoning] = llm_reasoning unless llm_reasoning.nil? || redact_comment_details?(comment)
      GlobalInstrumenter.instrument("copilot.reviews.v0.RecallAnalysis", payload)
    end

    # Redact llm_reasoning on private-repo events to avoid leaking code the
    # reasoning may quote.
    #
    # CCR-subject runs preserve llm_reasoning on the subject pass (judging
    # CCR's own comments) so we keep debugging visibility into CCR's
    # self-judgment in production. The non-subject pass still redacts because
    # the reasoning there quotes a human's comment + the diff.
    #
    # Competitor-subject runs in private repos always redact regardless of
    # which pass emitted the event — see redact_competitor_details? for the
    # full rationale.
    sig { params(comment: PullRequestReviewComment).returns(T::Boolean) }
    def redact_comment_details?(comment)
      return false unless private_repo?
      return true unless subject_is_ccr?
      comment.user_id != subject_user_id
    end

    # Stricter gate applied only to competitor-subject runs in private repos:
    # tells base_payload to omit repo/org/PR/comment-author identifiers so
    # that competitor recall telemetry from private repos cannot be joined
    # back to a specific customer repository. Applies to both passes — the
    # subject pass's events identify the competitor's own comments, which
    # would otherwise leak repo identity for private competitor reviews.
    # CCR-subject behavior is unchanged because subject_is_ccr? short-
    # circuits this to false.
    sig { returns(T::Boolean) }
    def redact_competitor_details?
      !subject_is_ccr? && private_repo?
    end

    sig { returns(T::Boolean) }
    def private_repo?
      !T.must(@pull_request.repository).public?
    end

    sig { params(comment: PullRequestReviewComment).returns(T::Hash[Symbol, T.untyped]) }
    def base_payload(comment)
      comment_source = if comment.user&.bot?
        T.must(comment.user).display_login
      else
        "human"
      end

      # Competitor-subject runs in private repos emit only the fields the
      # recall funnel + per-subject dashboards need: request_id, comment_id
      # (dedup key), comment_source (FN attribution), subject_reviewer_login
      # (per-subject slice). Org/repo/PR/analytics-tracking IDs are dropped to
      # avoid joining competitor analytics back to specific customer repos.
      if redact_competitor_details?
        return {
          request_id: @request_id,
          comment_id: comment.id.to_s,
          comment_source: comment_source,
          subject_reviewer_login: subject_login,
        }
      end

      payload = {
        request_id: @request_id,
        organization_id: @pull_request.owner&.id,
        repository_id: T.must(@pull_request.repository).id,
        pull_request_id: @pull_request.id,
        comment_id: comment.id.to_s,
        comment_source: comment_source,
        subject_reviewer_login: subject_login,
        analytics_tracking_id: @pull_request.user&.analytics_tracking_id,
      }
      # ccr_review_id is the dual-publish lookup key — it only resolves to a
      # CcrDecisionRun when the review under analysis is CCR's, so only emit
      # the payload key for CCR-subject runs.
      payload[:ccr_review_id] = @subject_review&.id if subject_is_ccr?
      payload
    end

    # The bot user_id under evaluation. Defaults to CCR's bot id when no
    # explicit subject was passed to the constructor.
    sig { returns(T.nilable(Integer)) }
    memoize def subject_user_id
      @subject_user_id_override || copilot_bot_id
    end

    sig { returns(T::Boolean) }
    def subject_is_ccr?
      subject_user_id == copilot_bot_id && !copilot_bot_id.nil?
    end

    # The display login of the subject bot (e.g. "copilot"). Resolved from the
    # User record when a custom subject was passed, falling back to the
    # hardcoded "copilot" for the CCR default to avoid an extra DB read on the
    # hot path.
    sig { returns(String) }
    memoize def subject_login
      if subject_is_ccr?
        "copilot"
      else
        User.find_by(id: subject_user_id)&.display_login || "unknown"
      end
    end

    # Human-readable name used in LLM prompts (e.g. "Copilot Code Review (CCR)").
    sig { returns(String) }
    def subject_display_name
      if subject_is_ccr?
        "Copilot Code Review (CCR)"
      else
        subject_login
      end
    end

    sig { returns(T::Boolean) }
    def diff_fn_enabled?
      return false if @user.nil?

      FeatureFlag.vexi.enabled?(:pr_recall_diff_fn_analysis, @user, default: false)
    end

    # D5: Diff-based FN detection
    #
    # For each review interval (review N → review N+1, or last review → merge),
    # builds the post-interval diff, asks an LLM to extract code issues that
    # were fixed, then checks whether the subject flagged each one.
    #
    # Per-review anchoring ensures issues CCR missed in review #1 that were
    # fixed before review #2 are still caught — using only the latest review
    # would collapse those earlier windows.
    #
    # Emits stage="diff_fn" events. These are additive to D3 "unique" FNs —
    # both sources coexist so the dashboard can slice by FN source.
    sig { params(subject_reviews: T::Array[PullRequestReview], subject_comments: T::Array[PullRequestReviewComment]).void }
    def analyze_diff_fns(subject_reviews, subject_comments)
      merged_head_sha = @pull_request.head_sha
      return if merged_head_sha.blank?

      subject_comments_block = format_subject_comments_block(subject_comments)
      issue_index = 0

      # Build review intervals: each review's head_sha → next review's head_sha
      # (or merged head_sha for the last review)
      subject_reviews.each_with_index do |review, review_idx|
        review_head_sha = review.head_sha
        next if review_head_sha.blank?

        # End of this interval is the next review's head_sha, or merge for the last
        next_sha = if review_idx < subject_reviews.size - 1
          subject_reviews[review_idx + 1]&.head_sha || merged_head_sha
        else
          merged_head_sha
        end
        next if next_sha.blank? || review_head_sha == next_sha

        base_sha = review.merge_base_sha || @pull_request.base_sha
        review_time_diff = build_diff_text(base_sha, review_head_sha)
        post_review_diff = build_diff_text(review_head_sha, next_sha)
        next if post_review_diff.blank?

        extracted_issues = extract_issues_from_diff(review_time_diff, post_review_diff)
        GitHub.dogstats.distribution("#{DOGSTATS_PREFIX}.diff_fn.extracted_issues", extracted_issues.size,
          tags: ["review_idx:#{review_idx}"])
        next if extracted_issues.empty?

        match_results = match_issues_to_subject(extracted_issues, subject_comments_block)

        # Validate match results
        expected_ids = Set.new(extracted_issues.map { |i| i["id"] })
        returned_ids = Set.new(match_results.grep(Hash).map { |m| m["issue_id"] })
        if match_results.empty? || returned_ids != expected_ids
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.match_id_mismatch")
          extracted_issues.each_with_index do |issue, idx|
            publish_diff_fn_event(issue, issue_index + idx, outcome: "llm_error",
              llm_comment_type: issue["type"], llm_severity: issue["severity"])
          end
          issue_index += extracted_issues.size
          next
        end

        extracted_issues.each_with_index do |issue, idx|
          match = match_results.find { |m| m["issue_id"] == issue["id"] }
          matched = match&.dig("matched") == true
          subject_comment_id = match&.dig("subject_comment_id")&.to_s
          outcome = matched ? "matched" : "missed"

          # Emit extraction confidence tied to outcome so we can see whether
          # low-confidence (speculative) extractions disproportionately become
          # "missed" FNs — Zack's concern that a confident matcher can mask a
          # weak extraction. Lets us calibrate a confidence gate later.
          # Scope: matched/missed outcomes only; the match-ID-mismatch path
          # emits llm_error separately and is excluded here by design.
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.extract_confidence",
            tags: ["confidence:#{normalize_confidence(issue["confidence"])}", "outcome:#{outcome}"])

          publish_diff_fn_event(issue, issue_index + idx,
            outcome: outcome,
            llm_confidence: match&.dig("confidence"),
            llm_comment_type: issue["type"],
            llm_severity: issue["severity"],
            llm_reasoning: match&.dig("reason"),
            llm_subject_comment_id: matched ? subject_comment_id : nil,
          )
        end

        issue_index += extracted_issues.size
      end
    end

    # Normalize an LLM-provided confidence string to a known level, bucketing
    # anything unexpected as "unknown" so Datadog tag cardinality stays bounded.
    sig { params(value: T.untyped).returns(String) }
    def normalize_confidence(value)
      level = value.to_s.strip.downcase
      CONFIDENCE_LEVELS.include?(level) ? level : "unknown"
    end

    # Build a diff between two SHAs, formatted for LLM consumption.
    sig { params(base_sha: String, head_sha: String).returns(String) }
    def build_diff_text(base_sha, head_sha)
      comparison = @pull_request.build_comparison(
        head_commit_oid: head_sha,
        base_commit_oid: base_sha,
      )
      return "" if comparison.nil?

      comparison.diffs.map { |d| "## #{d.path}\n#{d.header_text}#{d.extended_header_text}#{d.unicode_text}" }.join("\n\n")
    rescue StandardError => e
      GitHub.logger.warn("recall_analyzer: failed to build diff",
        "gh.pull_request.id" => @pull_request.id,
        "error" => e.message,
      )
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.diff_error")
      ""
    end

    # Step 1: Extract issues from post-review commits that already existed
    # at review time.
    # Returns an array of hashes: [{id:, description:, file:, type:, severity:}, ...]
    sig { params(review_time_diff: String, post_review_diff: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def extract_issues_from_diff(review_time_diff, post_review_diff)
      start_time = GitHub::Dogstats.monotonic_time
      client = copilot_api_client
      return [] if client.nil?

      response = client.async_create_response(
        model: MODEL,
        input: [{ role: "user", content: build_extract_issues_prompt(review_time_diff, post_review_diff) }],
        instructions: extract_issues_system_prompt,
        max_output_tokens: MAX_TOKENS_D5,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => DOGSTATS_PREFIX },
      )

      result = parse_llm_response(response)
      issues = result["issues"]
      record_llm_metrics(start_time, true, stage: "diff_fn_extract")
      return [] unless issues.is_a?(Array)

      issues
    rescue StandardError => e
      GitHub.logger.warn("recall_analyzer: diff_fn extract_issues LLM error",
        "gh.pull_request.id" => @pull_request.id,
        "error" => e.message,
      )
      record_llm_metrics(start_time, false, stage: "diff_fn_extract")
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.extract_error")
      []
    end

    # Step 2: Match ALL extracted issues against the subject's comments in a
    # single LLM call. Returns an array of match results, one per issue.
    sig { params(issues: T::Array[T::Hash[String, T.untyped]], subject_comments_block: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def match_issues_to_subject(issues, subject_comments_block)
      start_time = GitHub::Dogstats.monotonic_time
      client = copilot_api_client
      return [] if client.nil?

      response = client.async_create_response(
        model: MODEL,
        input: [{ role: "user", content: build_match_issues_prompt(issues, subject_comments_block) }],
        instructions: match_issues_system_prompt,
        max_output_tokens: MAX_TOKENS_D5,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => DOGSTATS_PREFIX },
      )

      result = parse_llm_response(response)
      matches = result["matches"]
      record_llm_metrics(start_time, true, stage: "diff_fn_match")
      return [] unless matches.is_a?(Array)

      matches
    rescue StandardError => e
      GitHub.logger.warn("recall_analyzer: diff_fn match LLM error",
        "gh.pull_request.id" => @pull_request.id,
        "error" => e.message,
      )
      record_llm_metrics(start_time, false, stage: "diff_fn_match")
      GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.match_error")
      []
    end

    # Emit a diff_fn event. Uses a synthetic comment_id (PR-scoped index)
    # since there's no real PullRequestReviewComment for extracted issues.
    # Redaction: on private repos, omit llm_reasoning (may contain code).
    # llm_judgment is intentionally omitted from D5 — use outcome as canonical.
    sig { params(issue: T::Hash[String, T.untyped], index: Integer, outcome: String, llm_confidence: T.nilable(String), llm_comment_type: T.nilable(String), llm_severity: T.nilable(String), llm_reasoning: T.nilable(String), llm_subject_comment_id: T.nilable(String)).void }
    def publish_diff_fn_event(issue, index, outcome:, llm_confidence: nil, llm_comment_type: nil, llm_severity: nil, llm_reasoning: nil, llm_subject_comment_id: nil)
      is_public = T.must(@pull_request.repository).public?

      # Competitor-subject runs in private repos emit only the fields the
      # recall funnel + per-subject dashboards need, matching base_payload
      # redaction. Org/repo/PR/analytics-tracking IDs are dropped.
      if redact_competitor_details?
        payload = {
          request_id: @request_id,
          comment_id: "diff_fn_#{index}",
          comment_source: "post_review_diff",
          subject_reviewer_login: subject_login,
          stage: "diff_fn",
          outcome: outcome,
        }
      else
        payload = {
          request_id: @request_id,
          organization_id: @pull_request.owner&.id,
          repository_id: T.must(@pull_request.repository).id,
          pull_request_id: @pull_request.id,
          comment_id: "diff_fn_#{index}",
          comment_source: "post_review_diff",
          subject_reviewer_login: subject_login,
          analytics_tracking_id: @pull_request.user&.analytics_tracking_id,
          stage: "diff_fn",
          outcome: outcome,
        }
        payload[:llm_subject_comment_id] = llm_subject_comment_id if llm_subject_comment_id
      end

      payload[:llm_confidence] = llm_confidence if llm_confidence
      payload[:llm_comment_type] = llm_comment_type if llm_comment_type
      payload[:llm_severity] = llm_severity if llm_severity
      payload[:llm_reasoning] = llm_reasoning if llm_reasoning && is_public
      GlobalInstrumenter.instrument("copilot.reviews.v0.RecallAnalysis", payload)
    end

    sig { returns(String) }
    def extract_issues_system_prompt
      <<~PROMPT
        You are an expert code reviewer analyzing two diffs from a pull request:
        1. The **review-time diff** — the code changes the review bot saw when it reviewed
        2. The **post-review diff** — changes made after the review, before merge

        Your job is to identify code issues in the post-review diff that were **fixes for problems that already existed in the review-time diff**. These are issues the review bot should have caught but missed.

        Only extract issues where:
        - The problem was visible in the review-time diff (the code was already wrong when the bot reviewed it)
        - A subsequent commit fixed it in the post-review diff
        - The fix addresses a genuine bug, security issue, performance problem, or correctness issue

        Do NOT extract:
        - Fixes for problems introduced AFTER the review (not the bot's fault)
        - New feature additions
        - Pure refactors with no behavioral change
        - Formatting, whitespace, or import changes
        - Comment-only changes
        - Test additions that don't fix a bug

        For each issue, provide:
        - A unique ID (F1, F2, ...)
        - A description of the **issue that was fixed** (what was wrong, not what was done)
        - The file path where the fix was applied
        - The type: bug, security, performance, naming, error_message, test_coverage, documentation, maintainability, api_design, concurrency, best_practices, or other
        - The severity: nit, moderate, or critical
        - Your confidence that this was a genuine pre-existing issue the bot should have caught: high, medium, or low. Use `low` when the fix is ambiguous or you are inferring intent.

        Respond with a single fenced JSON block:
        ```json
        {
          "issues": [
            {"id": "F1", "description": "...", "file": "...", "type": "bug", "severity": "moderate", "confidence": "high"},
            ...
          ]
        }
        ```
        If no qualifying issues were fixed, return `{"issues": []}`.
      PROMPT
    end

    sig { params(review_time_diff: String, post_review_diff: String).returns(String) }
    def build_extract_issues_prompt(review_time_diff, post_review_diff)
      parts = []

      if review_time_diff.present?
        parts << "## Review-time diff (what the bot saw when it reviewed)\n\n```diff\n#{truncate_diff_for_prompt(review_time_diff, "review_time")}\n```"
      else
        parts << "## Review-time diff\n(not available)"
      end

      parts << "\n## Post-review diff (changes made after the review)\n\n```diff\n#{truncate_diff_for_prompt(post_review_diff, "post_review")}\n```"

      parts << "\nIdentify code issues fixed in the post-review diff that already existed in the review-time diff. Respond with the JSON block."
      parts.join("\n")
    end

    # Truncate a diff to the prompt cap, recording diff_fn.truncated when content
    # is dropped so we can quantify FN undercounting on large PRs. Kept next to
    # the truncation itself so the cap and the metric can't drift apart.
    sig { params(diff: String, side: String).returns(String) }
    def truncate_diff_for_prompt(diff, side)
      if diff.length > MAX_DIFF_CHARS
        GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.diff_fn.truncated", tags: ["diff:#{side}"])
      end
      diff[0, MAX_DIFF_CHARS] || ""
    end

    sig { returns(String) }
    def match_issues_system_prompt
      <<~PROMPT
        You are deciding which of a code review bot's comments (if any) flagged issues that were later fixed in post-review commits.

        You will receive:
        1. A list of code issues extracted from post-review fixes
        2. The complete list of comments the review bot posted

        For EACH issue, determine whether any bot comment flagged that same problem. A comment "matches" if it identified the same underlying concern, even if worded differently.

        Respond with a single fenced JSON block:
        ```json
        {
          "matches": [
            {"issue_id": "F1", "matched": true, "subject_comment_id": 123, "confidence": "high", "reason": "brief explanation"},
            {"issue_id": "F2", "matched": false, "subject_comment_id": null, "confidence": "high", "reason": "no comment addresses this"},
            ...
          ]
        }
        ```
        Include one entry per issue. Set `matched` to false and `subject_comment_id` to null when no comment matches.
      PROMPT
    end

    sig { params(issues: T::Array[T::Hash[String, T.untyped]], subject_comments_block: String).returns(String) }
    def build_match_issues_prompt(issues, subject_comments_block)
      issues_block = issues.map { |i| "- **#{i['id']}** (#{i['file']}): #{i['description']} [#{i['type']}/#{i['severity']}]" }.join("\n")

      parts = [
        "## Issues fixed in post-review commits",
        issues_block,
        "\n## #{subject_display_name} comments on this PR",
        subject_comments_block,
        "\nFor each issue above, did any #{subject_display_name} comment flag it? Respond with the JSON block.",
      ]
      parts.join("\n")
    end

    memoize def copilot_bot_id
      ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id
    end

    sig { params(str: T.nilable(String)).returns(String) }
    def encode_utf8(str)
      return "" if str.nil?

      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
