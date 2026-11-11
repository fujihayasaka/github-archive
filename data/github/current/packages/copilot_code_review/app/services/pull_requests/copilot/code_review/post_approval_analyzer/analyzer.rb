# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::PostApprovalAnalyzer
  class Analyzer
    include GitHub::Memoizer

    MODEL = "gpt-5.4-mini"
    MAX_TOKENS = 1000
    CAPI_INITIATOR = "agent"
    REASONING_EFFORT = "medium"

    MAX_REVIEW_COMMENTS = 10
    MAX_ISSUE_COMMENTS = 10
    MAX_COMMITS = 20
    MAX_DIFF_ENTRIES_PER_COMMIT = 20

    def initialize(pull_request:, approval_review:, window_end_review: nil, request_id: nil)
      @pull_request = pull_request
      @approval_review = approval_review
      @window_end_review = window_end_review
      @user = pull_request&.user
      @request_id = request_id || GitHub.context[:request_id] || SecureRandom.uuid
    end

    sig { void }
    def analyze
      return if pull_request.nil? || approval_review.nil?
      return unless async_llm_analysis_enabled? && pr_author_is_human?

      if post_approval_commit_count == 0 && post_approval_comment_count == 0
        payload = base_payload.merge(
          approval_review_id: approval_review.id.to_s,
          post_approval_commit_count: 0,
          post_approval_comment_count: 0,
          llm_judgment: "yes",
          llm_reasoning: "No post-approval activity detected",
          substantial_commit_shas: [],
        )
        GlobalInstrumenter.instrument("copilot.reviews.v0.PostApprovalAssessment", payload)
        return
      end

      perform_llm_judgment_async.sync
    end

    private

    attr_reader :pull_request, :approval_review, :window_end_review

    sig { returns(T::Boolean) }
    def async_llm_analysis_enabled?
      FeatureFlag.vexi.enabled?(:pr_llm_post_approval_analysis_async, @user, default: false)
    end

    sig { returns(T::Boolean) }
    def pr_author_is_human?
      @user.present? && @user.user?
    end

    sig { returns(Promise[T::Boolean]) }
    def perform_llm_judgment_async
      start_time = GitHub::Dogstats.monotonic_time

      payload = base_payload.merge(
        approval_review_id: approval_review.id.to_s,
        post_approval_commit_count: post_approval_commit_count,
        post_approval_comment_count: post_approval_comment_count,
      )

      copilot_api_client.async_create_response(
        model: MODEL,
        input: build_response_input,
        instructions: system_prompt,
        max_output_tokens: MAX_TOKENS,
        reasoning: { effort: REASONING_EFFORT },
        initiator: CAPI_INITIATOR,
        experiment_headers: { "Copilot-Subsystem-Id" => "pr_post_approval_llm_analysis" },
      ).then do |response|
        result = parse_llm_response(response)
        payload[:llm_judgment] = result["judgment"]
        payload[:llm_reasoning] = result["reasoning"]
        payload[:substantial_commit_shas] = Array(result["substantial_commit_shas"])
        record_llm_metrics(start_time, true)
        GlobalInstrumenter.instrument("copilot.reviews.v0.PostApprovalAssessment", payload)
        true
      end.rescue do |e|
        payload[:llm_error] = e.message
        record_llm_metrics(start_time, false)
        GlobalInstrumenter.instrument("copilot.reviews.v0.PostApprovalAssessment", payload)
        false
      end
    end

    sig { returns(Time) }
    def window_start_time
      approval_review.submitted_at || approval_review.created_at
    end

    sig { returns(Time) }
    def window_end_time
      window_end_review&.submitted_at || Time.current
    end

    sig { returns(T.nilable(String)) }
    def window_start_head
      approval_review.head_sha
    end

    sig { returns(T.nilable(String)) }
    def window_end_head
      window_end_review&.head_sha || pull_request.head_sha
    end

    sig { returns(T.nilable(GitHub::Comparison)) }
    memoize def post_approval_comparison
      start_head = window_start_head
      end_head = window_end_head
      return nil if start_head.blank? || end_head.blank? || start_head == end_head

      pull_request.build_comparison(head_commit_oid: end_head, base_commit_oid: start_head)
    end

    sig { returns(Integer) }
    def post_approval_commit_count
      comparison = post_approval_comparison
      return 0 if comparison.nil?

      comparison.commits.length
    end

    sig { returns(Integer) }
    def post_approval_comment_count
      post_approval_review_comment_count + post_approval_issue_comment_count
    end

    sig { returns(Integer) }
    def post_approval_review_comment_count
      review_comments_scope.count
    end

    sig { returns(Integer) }
    def post_approval_issue_comment_count
      issue_comments_scope.count
    end

    sig { returns(ActiveRecord::Relation) }
    def review_comments_scope
      pull_request.review_comments
        .where("created_at > ? AND created_at <= ?", window_start_time, window_end_time)
    end

    sig { returns(T.untyped) }
    def issue_comments_scope
      return IssueComment.none if pull_request.issue.nil?

      pull_request.issue.comments
        .where("issue_comments.created_at > ? AND issue_comments.created_at <= ?", window_start_time, window_end_time)
    end

    sig { returns(T::Array[T.untyped]) }
    def post_approval_review_comments
      review_comments_scope
        .includes(:user, :pull_request_review_thread)
        .order(:created_at)
        .last(MAX_REVIEW_COMMENTS)
    end

    sig { returns(T::Array[T.untyped]) }
    def post_approval_issue_comments
      issue_comments_scope
        .includes(:user)
        .order(:created_at)
        .last(MAX_ISSUE_COMMENTS)
    end

    sig { returns(String) }
    def post_approval_diff_text
      comparison = post_approval_comparison
      return "" if comparison.nil?

      commits = comparison.commits
      return "" if commits.empty?

      sections = []
      commits.each_with_index do |commit, commit_index|
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

      return "" if sections.empty?

      encode_utf8(sections.join("\n"))
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def build_response_input
      [
        { role: "user", content: build_user_prompt },
      ]
    end

    sig { returns(String) }
    def build_user_prompt
      review_comment_text = post_approval_review_comments.map { |comment| review_comment_summary(comment) }.join("\n\n")
      issue_comment_text = post_approval_issue_comments.map { |comment| issue_comment_summary(comment) }.join("\n\n")

      user_prompt(
        approval_body: encode_utf8(approval_review.body),
        approval_submitted_at: (approval_review.submitted_at || approval_review.created_at).iso8601,
        approval_head_sha: approval_review.head_sha.to_s,
        window_end_at: window_end_time.iso8601,
        window_end_head_sha: window_end_head.to_s,
        post_approval_commit_count: post_approval_commit_count,
        post_approval_comment_count: post_approval_comment_count,
        post_approval_diff: post_approval_diff_text,
        review_comments_summary: review_comment_text,
        issue_comments_summary: issue_comment_text,
        review_comments_total: post_approval_review_comment_count,
        issue_comments_total: post_approval_issue_comment_count,
      )
    end

    sig { params(comment: T.untyped).returns(String) }
    def review_comment_summary(comment)
      thread = comment.pull_request_review_thread
      thread_text = ""
      if thread
        thread_text = thread.comments.map do |thread_comment|
          "#{thread_comment.user&.display_login}: #{encode_utf8(thread_comment.body)}"
        end
        thread_text = thread_text.join("\n")
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
      GitHub.dogstats.distribution("pr_post_approval_llm_analysis.duration", elapsed, tags: ["success:#{succeeded}"])
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def base_payload
      {
        request_id: @request_id,
        organization_id: pull_request.owner&.id,
        repository_id: pull_request.repository.id,
        pull_request_id: pull_request.id,
        comment_id: approval_review.id.to_s,
        analytics_tracking_id: pull_request.user&.analytics_tracking_id,
      }
    end

    memoize def copilot_api_client
      new_access = copilot_pull_request_reviewer_app.grant(@user, entry_point: :pull_requests_copilot_code_review_post_approval_analyzer)
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

    sig { returns(String) }
    def system_prompt
      <<~PROMPT
      Your task is to examine a PR that was approved but then had further comments and/or commits before it was merged. You need to decide whether the PR reviewer was right or wrong to approve the earlier version of the PR.

      To do so, you will examine all changes made in the PR branch between the approval and the merging of the branch. For each subsequent commit, consider whether or not it addresses a SUBSTANTIAL problem that should have prevented the PR from being approved.

      Examples of INSUBSTANTIAL changes that can happen after approval:
      - Merging in the main branch or rebasing on top of main
      - Fixing formatting or linter errors
      - Small additions to test coverage
      - Addressing nits, such as minor improvements in code style or documentation
      - Scope expansions beyond the goals described in the PR title and description

      Examples of SUBSTANTIAL changes that imply the earlier commit should NOT have been approved:
      - Significant bug fixes
      - Major improvements in security, performance, or maintainability
      - Major improvements in test coverage
      - Completion of the PR's stated goals which were not met in the approved commit

      Included to assist in your judgment will be the following data:
      - A header block summarising the PR state at approval time, including approval metadata and the start and end commit SHAs for the change.
      - A short summary including counts of each of post approval commits, total comments, issue comments, and review comments.
      - A detailed breakdown for each comment and commit including the commit diff.

      Review each of these contributions one by one, and then answer the following question:

      Were any of the changes made after the approved commit substantial enough that the reviewer should NOT have approved the commit?

      Respond with this exact JSON format, each field must contain a value as defined in the notation below:
      {
        "reasoning": <a brief explanation of your judgment>,
        "judgment": <Was the reviewer correct to approve the PR? Return a single word, either "yes" or "no">,
        "substantial_commit_shas": <a JSON array of the short SHAs of commits that contained substantial changes, or an empty array if none>
      }
      PROMPT
    end

    sig do
      params(
        approval_body: String,
        approval_submitted_at: String,
        approval_head_sha: String,
        window_end_at: String,
        window_end_head_sha: String,
        post_approval_commit_count: Integer,
        post_approval_comment_count: Integer,
        post_approval_diff: String,
        review_comments_summary: String,
        issue_comments_summary: String,
        review_comments_total: Integer,
        issue_comments_total: Integer,
      ).returns(String)
    end
    def user_prompt(
      approval_body:,
      approval_submitted_at:,
      approval_head_sha:,
      window_end_at:,
      window_end_head_sha:,
      post_approval_commit_count:,
      post_approval_comment_count:,
      post_approval_diff:,
      review_comments_summary:,
      issue_comments_summary:,
      review_comments_total:,
      issue_comments_total:
    )
      <<~PROMPT
      <approval>
      Submitted at: #{approval_submitted_at}
      Head SHA: #{approval_head_sha}
      Body:
      #{approval_body}
      </approval>

      <window>
      Window end: #{window_end_at}
      Window end head SHA: #{window_end_head_sha}
      </window>

      <post_approval_summary>
      Post-approval commit count: #{post_approval_commit_count}
      Post-approval comment count: #{post_approval_comment_count}
      Post-approval review comments total: #{review_comments_total}
      Post-approval issue comments total: #{issue_comments_total}
      </post_approval_summary>

      <post_approval_commits>
      #{post_approval_diff}
      </post_approval_commits>

      <post_approval_review_comments>
      #{review_comments_summary}
      </post_approval_review_comments>

      <post_approval_issue_comments>
      #{issue_comments_summary}
      </post_approval_issue_comments>
      PROMPT
    end

    sig { params(str: T.nilable(String)).returns(String) }
    def encode_utf8(str)
      return "" if str.nil?

      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
