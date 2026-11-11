# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class CcrDecisionAssessmentAnalyzer
    include GitHub::Memoizer

    MODEL = "gpt-5.4-mini"
    PROMPT_VERSION = "v2"
    MAX_TOKENS = 1000
    CAPI_INITIATOR = "agent"
    REASONING_EFFORT = "medium"

    MAX_REVIEW_COMMENTS = 10
    MAX_ISSUE_COMMENTS = 10
    MAX_COMMITS = 20
    MAX_DIFF_ENTRIES_PER_COMMIT = 20

    sig do
      params(
        pull_request: PullRequest,
        decision_run: PullRequests::Copilot::CcrDecisionRunStore::DecisionRun,
        request_id: T.nilable(String),
      ).void
    end
    def initialize(pull_request:, decision_run:, request_id: nil)
      @pull_request = pull_request
      @decision_run = decision_run
      @request_id = request_id || GitHub.context[:request_id] || SecureRandom.uuid
      @user = pull_request.user
    end

    sig { void }
    def analyze
      return if pull_request.nil?

      experiment_attributed_decision = assessable_experiment_attributed_decision?
      return unless experiment_attributed_decision || pr_author_is_human?
      return unless experiment_attributed_decision || async_llm_analysis_enabled?

      if no_follow_up_activity?
        publish(base_payload.merge(
          post_decision_commit_count: 0,
          post_decision_comment_count: 0,
          post_decision_human_changes_requested_count: 0,
          substantial_commit_shas: [],
          analysis_status: "no_activity",
        ))
        return
      end

      perform_llm_judgment_async.sync
    end

    private

    attr_reader :pull_request, :decision_run

    sig { returns(T::Boolean) }
    def async_llm_analysis_enabled?
      feature_flag = assessment_feature_flag
      return false if feature_flag.nil?

      FeatureFlag.vexi.enabled?(feature_flag, @user, default: false)
    end

    sig { returns(T::Boolean) }
    def assessable_experiment_attributed_decision?
      assessment_feature_flag.present? &&
        decision_run.response_request_id.present? &&
        decision_run.decision_assessment_required
    end

    sig { returns(T.nilable(Symbol)) }
    def assessment_feature_flag
      case decision_run.approval_readiness_code
      when "ready"
        :pr_llm_approve_decision_assessment_async
      when "too_complex", "unknown"
        :pr_llm_comment_assessment_async
      when "requires_changes"
        :pr_llm_request_changes_assessment_async
      end
    end

    sig { returns(T::Boolean) }
    def pr_author_is_human?
      @user.present? && @user.user?
    end

    sig { returns(Promise[T::Boolean]) }
    def perform_llm_judgment_async
      start_time = GitHub::Dogstats.monotonic_time
      payload = base_payload.merge(
        post_decision_commit_count: post_decision_commit_count,
        post_decision_comment_count: post_decision_comment_count,
        post_decision_human_changes_requested_count: post_decision_human_changes_requested_count,
        analysis_status: "llm_success",
        llm_model: MODEL,
        prompt_version: PROMPT_VERSION,
      )

      copilot_api_client.async_create_response(
        model: MODEL,
        input: build_response_input,
        instructions: system_prompt,
        max_output_tokens: MAX_TOKENS,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => "pr_ccr_decision_assessment_llm_analysis" },
      ).then do |response|
        result = parse_llm_response(response)
        substantial_commit_shas = Array(result["substantial_commit_shas"])
        payload[:llm_judgment] = result["judgment"]
        payload[:llm_reasoning] = result["reasoning"]
        payload[:substantial_commit_shas] = substantial_commit_shas
        record_llm_metrics(start_time, true)
        publish(payload)
        true
      end.rescue do |error|
        payload[:analysis_status] = "llm_error"
        payload[:llm_error] = error.message
        record_llm_metrics(start_time, false)
        publish(payload)
        false
      end
    end

    sig { params(payload: T::Hash[Symbol, T.untyped]).void }
    def publish(payload)
      GlobalInstrumenter.instrument("copilot.reviews.v0.CcrDecisionAssessment", payload)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def base_payload
      {
        request_id: @request_id,
        organization_id: pull_request.owner&.id,
        repository_id: pull_request.repository.id,
        pull_request_id: pull_request.id,
        comment_id: decision_run.pull_request_review_id.to_s,
        analytics_tracking_id: pull_request.user&.analytics_tracking_id,
        pull_request_review_id: decision_run.pull_request_review_id.to_s,
        response_request_id: decision_run.response_request_id,
        decision_submitted_at: decision_run.submitted_at,
        decision_head_sha: decision_run.head_sha,
        approval_readiness_code: decision_run.approval_readiness_code,
        review_submission_event: decision_run.review_submission_event,
      }.compact
    end

    sig { returns(Time) }
    def window_start_time
      decision_run.submitted_at
    end

    sig { returns(Time) }
    def window_end_time
      pull_request.merged_at || Time.current
    end

    sig { returns(T.nilable(String)) }
    def window_start_head
      decision_run.head_sha
    end

    sig { returns(T.nilable(String)) }
    def window_end_head
      pull_request.head_sha
    end

    sig { returns(T.nilable(GitHub::Comparison)) }
    memoize def post_decision_comparison
      start_head = window_start_head
      end_head = window_end_head
      return nil if start_head.blank? || end_head.blank? || start_head == end_head

      pull_request.build_comparison(head_commit_oid: end_head, base_commit_oid: start_head)
    end

    sig { returns(Integer) }
    def post_decision_commit_count
      comparison = post_decision_comparison
      return 0 if comparison.nil?

      comparison.commits.length
    end

    sig { returns(Integer) }
    def post_decision_comment_count
      post_decision_review_comment_count + post_decision_issue_comment_count
    end

    sig { returns(Integer) }
    def post_decision_human_changes_requested_count
      post_decision_human_changes_requested_reviews_in_window.size
    end

    sig { returns(Integer) }
    def post_decision_review_comment_count
      review_comments_scope.count
    end

    sig { returns(Integer) }
    def post_decision_issue_comment_count
      issue_comments_scope.count
    end

    sig { returns(ActiveRecord::Relation) }
    def review_comments_scope
      pull_request.review_comments.where("created_at > ? AND created_at <= ?", window_start_time, window_end_time)
    end

    sig { returns(T.untyped) }
    def issue_comments_scope
      return IssueComment.none if pull_request.issue.nil?

      pull_request.issue.comments.where("issue_comments.created_at > ? AND issue_comments.created_at <= ?", window_start_time, window_end_time)
    end

    sig { returns(ActiveRecord::Relation) }
    def human_changes_requested_reviews_scope
      pull_request.reviews
        .where(state: PullRequestReview.state_value(:changes_requested))
        .where("COALESCE(submitted_at, created_at) > ? AND COALESCE(submitted_at, created_at) <= ?", window_start_time, window_end_time)
    end

    sig { returns(T::Array[T.untyped]) }
    def post_decision_review_comments
      review_comments_scope.includes(:user, :pull_request_review_thread).order(:created_at).last(MAX_REVIEW_COMMENTS)
    end

    sig { returns(T::Array[T.untyped]) }
    def post_decision_issue_comments
      issue_comments_scope.includes(:user).order(:created_at).last(MAX_ISSUE_COMMENTS)
    end

    sig { returns(T::Array[T.untyped]) }
    memoize def post_decision_human_changes_requested_reviews_in_window
      human_changes_requested_reviews_scope
        .includes(:user)
        .order(Arel.sql("COALESCE(submitted_at, created_at) ASC"))
        .to_a
        .select { |review| review.user&.user? && human_changes_requested_review_matches_decision_window?(review) }
    end

    sig { params(review: T.untyped).returns(T::Boolean) }
    def human_changes_requested_review_matches_decision_window?(review)
      review_head_sha = review.head_sha
      return false if review_head_sha.blank?

      post_decision_allowed_review_head_shas.include?(review_head_sha)
    end

    sig { returns(T::Array[String]) }
    memoize def post_decision_allowed_review_head_shas
      allowed_head_shas = T.let([], T::Array[String])

      start_head = window_start_head
      allowed_head_shas << start_head if start_head.present?

      comparison = post_decision_comparison
      if comparison
        comparison.commits.each do |commit|
          oid = commit.oid
          allowed_head_shas << oid if oid.present?
        end
      end

      allowed_head_shas.uniq
    end

    sig { returns(T::Array[T.untyped]) }
    def post_decision_human_changes_requested_reviews
      post_decision_human_changes_requested_reviews_in_window.last(MAX_REVIEW_COMMENTS)
    end

    sig { returns(String) }
    def post_decision_diff_text
      comparison = post_decision_comparison
      return "" if comparison.nil?

      sections = []
      comparison.commits.each_with_index do |commit, commit_index|
        break if commit_index >= MAX_COMMITS

        parent_oid = commit.parent_oids&.first
        next if parent_oid.blank?

        commit_comparison = pull_request.build_comparison(head_commit_oid: commit.oid, base_commit_oid: parent_oid)
        next if commit_comparison.nil?

        entries = []
        commit_comparison.diffs.each_with_index do |diff_entry, entry_index|
          break if entry_index >= MAX_DIFF_ENTRIES_PER_COMMIT
          entries << "#{diff_entry.header_text}#{diff_entry.extended_header_text}#{diff_entry.unicode_text}"
        end

        commit_message = CGI.escapeHTML(encode_utf8(commit.message.to_s.lines.first&.strip.to_s))
        sections << <<~SECTION
          <commit sha="#{commit.oid}" message="#{commit_message}">
          #{entries.join("\n")}
          </commit>
        SECTION
      end

      encode_utf8(sections.join("\n"))
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def build_response_input
      [
        { role: "user", content: user_prompt },
      ]
    end

    sig { returns(String) }
    def system_prompt
      <<~PROMPT
      Your task is to judge whether GitHub Copilot Code Review (CCR) made the right decision on a pull request.

      You will be given the CCR decision, the pull request state at that time, and the commits/comments and later human reviews requesting changes that happened afterwards until the PR was merged.

      A decision is usually justified when the follow-up activity is insubstantial, such as:
      - merging or rebasing the base branch
      - formatting or lint fixes
      - small documentation updates
      - minor nits or tiny test additions

      A decision may be unjustified when the follow-up activity is substantial, such as:
      - significant bug fixes
      - important security, performance, or maintainability fixes
      - major test improvements
      - work needed to satisfy important pull request goals that were not met at the time of the decision

      Return JSON with this exact shape:
      {
        "reasoning": <brief explanation>,
        "judgment": <single word: "yes" if CCR's decision was justified, otherwise "no">,
        "substantial_commit_shas": <array of substantial commit SHAs, or []>
      }
      PROMPT
    end

    sig { returns(String) }
    def user_prompt
      review_comment_text = post_decision_review_comments.map { |comment| review_comment_summary(comment) }.join("\n\n")
      issue_comment_text = post_decision_issue_comments.map { |comment| issue_comment_summary(comment) }.join("\n\n")
      human_changes_requested_text = post_decision_human_changes_requested_reviews.map { |review| human_changes_requested_review_summary(review) }.join("\n\n")

      <<~PROMPT
      <decision>
      Submitted at: #{decision_run.submitted_at.iso8601}
      Head SHA: #{decision_run.head_sha}
      Review submission event: #{decision_run.review_submission_event}
      Approval readiness code: #{decision_run.approval_readiness_code}
      Body:
      #{encode_utf8(decision_review&.body)}
      </decision>

      <window>
      Window end: #{window_end_time.iso8601}
      Window end head SHA: #{window_end_head}
      </window>

      <post_decision_summary>
      Post-decision commit count: #{post_decision_commit_count}
      Post-decision comment count: #{post_decision_comment_count}
      Post-decision human changes requested count: #{post_decision_human_changes_requested_count}
      Post-decision review comments total: #{post_decision_review_comment_count}
      Post-decision issue comments total: #{post_decision_issue_comment_count}
      </post_decision_summary>

      <post_decision_commits>
      #{post_decision_diff_text}
      </post_decision_commits>

      <post_decision_review_comments>
      #{review_comment_text}
      </post_decision_review_comments>

      <post_decision_issue_comments>
      #{issue_comment_text}
      </post_decision_issue_comments>

      <post_decision_human_changes_requested_reviews>
      #{human_changes_requested_text}
      </post_decision_human_changes_requested_reviews>
      PROMPT
    end

    sig { returns(T.nilable(PullRequestReview)) }
    memoize def decision_review
      PullRequestReview.find_by(id: decision_run.pull_request_review_id)
    end

    sig { params(comment: T.untyped).returns(String) }
    def review_comment_summary(comment)
      thread = comment.pull_request_review_thread
      thread_text = if thread
        thread.comments.map { |thread_comment| "#{thread_comment.user&.display_login}: #{encode_utf8(thread_comment.body)}" }.join("\n")
      else
        ""
      end

      <<~TEXT
      <review_comment>
      File: #{comment.path}
      Line: #{comment.async_line.sync || 0}
      Body: #{encode_utf8(comment.body)}
      Thread (#{thread&.comments&.size || 0}):
      #{thread_text}
      Resolved: #{thread&.resolved? ? "yes" : "no"}
      </review_comment>
      TEXT
    end

    sig { params(comment: T.untyped).returns(String) }
    def issue_comment_summary(comment)
      <<~TEXT
      <issue_comment>
      Body: #{encode_utf8(comment.body)}
      </issue_comment>
      TEXT
    end

    sig { params(review: T.untyped).returns(String) }
    def human_changes_requested_review_summary(review)
      <<~TEXT
      <changes_requested_review>
      Submitted at: #{(review.submitted_at || review.created_at)&.iso8601}
      Reviewer: #{review.user&.display_login}
      Head SHA: #{review.head_sha}
      Body: #{encode_utf8(review.body)}
      </changes_requested_review>
      TEXT
    end

    sig { returns(T::Boolean) }
    def no_follow_up_activity?
      post_decision_commit_count == 0 &&
        post_decision_comment_count == 0 &&
        post_decision_human_changes_requested_count == 0
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
      GitHub.dogstats.distribution("pr_ccr_decision_assessment_llm_analysis.duration", elapsed, tags: ["success:#{succeeded}"])
    end

    memoize def copilot_api_client
      new_access = copilot_pull_request_reviewer_app.grant(@user, entry_point: :pull_requests_copilot_code_review_ccr_decision_assessment)
      access, _ = new_access.redeem(extended_expiry: true)
      token = Copilot::DecryptedToken.from(access)

      ::Copilot::User.copilot_api(
        user: @user,
        integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
        request_id: @request_id,
        token: token,
      )
    end

    def copilot_pull_request_reviewer_app
      return @app if defined?(@app)
      @app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    end

    sig { params(str: T.nilable(String)).returns(String) }
    def encode_utf8(str)
      return "" if str.nil?

      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
