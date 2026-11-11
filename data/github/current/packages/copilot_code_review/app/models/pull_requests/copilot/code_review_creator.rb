# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewCreator
    ERROR_COMMENTS = "Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."
    ERROR_COPILOT_UNAVAILABLE = "Copilot is currently unavailable to review this pull request. Please try again later."
    ERROR_BILLING = "Copilot encountered an error: Your billing is not configured or you have Copilot licenses from multiple standalone organizations or enterprises. To use premium requests, select a billing entity via the GitHub site, under [Settings > Copilot > Features](/settings/copilot/features)."
    ERROR_QUOTA = "Copilot was unable to review this pull request because the user who requested the review has reached their quota limit."
    ERROR_TOO_MANY_FILES = "Copilot wasn't able to review this pull request because it exceeds the maximum number of files (300). Try reducing the number of changed files and requesting a review from Copilot again."
    ERROR_TOO_MANY_LINES = "Copilot wasn't able to review this pull request because it exceeds the maximum number of lines (20,000). Try reducing the number of changed lines and requesting a review from Copilot again."
    ERROR_PR_TOO_LARGE = "Copilot wasn't able to review this pull request because it exceeds the maximum diff size. Try reducing the number of changed files and lines, and requesting a review from Copilot again."
    ERROR_CONTENT_EXCLUDED = "Copilot wasn't able to review this pull request because all changed files are excluded by your Copilot content exclusion settings. See [Excluding content from Copilot](https://docs.github.com/en/copilot/how-tos/configure-content-exclusion/exclude-content-from-copilot) for details."
    ACTOR_INELIGIBLE = "Copilot was unable to review this pull request because the user who requested the review is ineligible. To be eligible to request a review, you need a paid Copilot license, or your organization must enable Copilot code review."

    # Actionable environment-error messages owned by dotcom that mirror the
    # verbatim text CCRA forwards from sweagentd (see
    # github/sweagentd internal/jobutils/jobutils.go and
    # internal/launcher/actions.go). These describe Actions/billing/runner
    # configuration problems the customer can fix themselves, so we surface them
    # instead of overwriting with generic copy. Kept byte-for-byte in sync with
    # sweagentd's strings since classification matches on the incoming message.
    ENVIRONMENT_ERROR_MESSAGES = T.let(
      [
        "The job was not started because the account is locked due to a billing issue.",
        "The job was not started because recent GitHub Actions payments have failed or your spending limit needs to be increased.",
        "The job was not started because a GitHub Actions budget is preventing further Actions use.",
        "The job failed because GitHub Actions hosted runners are disabled for this repository.",
        "The job was cancelled because the repository was archived.",
        "The `runs-on` setting in your `copilot-setup-steps.yml` file points to a GitHub Actions runner with an unsupported operating system. Only Linux and Windows runners are supported. For more information, see https://gh.io/cca-runner-os.",
        "The `runs-on` label resolved to a different operating system than the one detected on the runner. Make sure the runner labels in `copilot-setup-steps.yml` and your runner registration agree. For more information, see https://gh.io/cca-runner-os.",
        "The agent firewall is enabled, but firewall is not supported for self-hosted runners. You must disable the agent firewall in the repository's settings to use self-hosted runners. For more information, see https://gh.io/cca-self-hosted-disable-firewall.",
        "The agent firewall is enabled, but firewall is not supported on Windows runners. You must disable the agent firewall in the repository's settings to use Windows runners. For more information, see https://gh.io/cca-disable-firewall.",
      ].freeze,
      T::Array[String],
    )

    # Matches the dynamic setup-step failure message sweagentd sends, where the
    # step name is interpolated in double quotes (Go %q):
    #   The "<step name>" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.
    SETUP_STEP_FAILURE_PATTERN = T.let(
      %r{\AThe "(?<step>.*)" custom setup step from your \.github/workflows/copilot-setup-steps\.yml file failed\.\z},
      Regexp,
    )

    # Matches the dotcom-rendered setup-step body (step name wrapped in a code
    # span) so error_review_body? recognizes it for feedback-widget suppression.
    SETUP_STEP_DISPLAY_PATTERN = T.let(
      %r{\AThe `[^`]*` custom setup step from your \.github/workflows/copilot-setup-steps\.yml file failed\.\z},
      Regexp,
    )

    ERROR_REVIEW_BODIES = T.let(
      Set.new([
        ERROR_COMMENTS,
        ERROR_COPILOT_UNAVAILABLE,
        ERROR_BILLING,
        ERROR_QUOTA,
        ERROR_TOO_MANY_FILES,
        ERROR_TOO_MANY_LINES,
        ERROR_PR_TOO_LARGE,
        ERROR_CONTENT_EXCLUDED,
        ACTOR_INELIGIBLE,
        *ENVIRONMENT_ERROR_MESSAGES,
      ]).freeze,
      T::Set[String],
    )

    sig { params(body: T.nilable(String)).returns(T::Boolean) }
    def self.error_review_body?(body)
      return false if body.blank?
      # Exact-match bodies (including ones containing URLs) are checked first and
      # returned early so they never reach the regex below; only the dynamic
      # setup-step body needs pattern matching.
      return true if ERROR_REVIEW_BODIES.include?(body)

      SETUP_STEP_DISPLAY_PATTERN.match?(body)
    end

    # Returns the dotcom-owned, customer-actionable body for an environment
    # error message forwarded from sweagentd, or nil if the message is not a
    # recognized environment error. Static messages are echoed back verbatim
    # (dotcom now owns a copy); the setup-step message is re-rendered with the
    # user-controlled step name in a code span to neutralize markdown/mentions.
    sig { params(message: T.nilable(String)).returns(T.nilable(String)) }
    def self.environment_error_body_for(message)
      return nil if message.blank?
      return message if ENVIRONMENT_ERROR_MESSAGES.include?(message)

      match = SETUP_STEP_FAILURE_PATTERN.match(message)
      return nil unless match

      step = T.must(match[:step]).delete("`")
      "The `#{step}` custom setup step from your .github/workflows/copilot-setup-steps.yml file failed."
    end

    REASON_BILLING = "billing"
    REASON_TOO_MANY_FILES = "too_many_files"
    REASON_TOO_MANY_LINES = "too_many_lines"
    REASON_PR_TOO_LARGE = "pr_too_large"
    REASON_COPILOT_UNAVAILABLE = "copilot_unavailable"
    REASON_CONTENT_EXCLUDED = "content_excluded"
    REASON_ENVIRONMENT_ERROR = "environment_error"
    PERSISTENCE_ERROR_KV_WRITE_FAILURE = "kv_write_failure"
    PERSISTENCE_ERROR_MISSING_RESPONSE_REQUEST_ID = "missing_response_request_id"
    CODING_GUIDELINE_PROBLEM_TYPE = "custom"

    REVIEW_SEVERITY_NONE = AutomatedReviewComment.severities[:severity_none]
    REVIEW_SEVERITY_NIT = "nit"
    REVIEW_SEVERITY_MODERATE = "moderate"
    REVIEW_SEVERITY_CRITICAL = "critical"

    SEVERITIES_FOR_AUTOMATED_REVIEW = T.let({
      REVIEW_SEVERITY_NIT => AutomatedReviewComment.severities[:severity_nit],
      REVIEW_SEVERITY_MODERATE => AutomatedReviewComment.severities[:severity_medium],
      REVIEW_SEVERITY_CRITICAL => AutomatedReviewComment.severities[:severity_high],
    }, T::Hash[String, Integer])

    sig do
      params(
        pull: PullRequest,
        repo: Repository,
        comments: T::Array[T::Hash[T.untyped, T.untyped]],
        commit_id: String,
        body: T.nilable(String),
        diff_start_commit_oid: String,
        diff_end_commit_oid: String,
        diff_base_commit_oid: String,
        review_event: Symbol,
        return_with_error: T::Boolean,
        error_reason: T.nilable(String),
        error_review_body: T.nilable(String),
        response_request_id: T.nilable(String),
        approval_readiness_code: T.nilable(String),
        experiment_flags: T.nilable(T::Hash[Symbol, T.untyped]),
        experiment_assignment_context: T.nilable(String),
        decision_assessment_required: T::Boolean,
      ).void
    end
    def initialize(pull:, repo:, comments:, commit_id:, body:, diff_start_commit_oid:, diff_end_commit_oid:, diff_base_commit_oid:, review_event: :comment, return_with_error: false, error_reason: nil, error_review_body: nil, response_request_id: nil, approval_readiness_code: nil, experiment_flags: nil, experiment_assignment_context: nil, decision_assessment_required: false)
      @pull = pull
      @repo = repo
      @comments = comments
      @commit_id = commit_id
      @body = body
      @diff_start_commit_oid = diff_start_commit_oid
      @diff_end_commit_oid = diff_end_commit_oid
      @diff_base_commit_oid = diff_base_commit_oid
      @review_event = review_event
      @return_with_error = return_with_error
      @error_reason = error_reason
      @error_review_body = error_review_body
      @response_request_id = response_request_id
      @approval_readiness_code = approval_readiness_code
      @experiment_flags = experiment_flags
      @experiment_assignment_context = experiment_assignment_context
      @decision_assessment_required = decision_assessment_required
    end

    sig { returns(T::Boolean) }
    def create
      start_time = GitHub::Dogstats.monotonic_time

      bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
      variant_type = :automated

      Audit.context.push(actor: bot)
      ActiveRecord::Base.connected_to(role: :writing) do
        review = pull.pending_review_for(user: bot, head_sha: commit_id)
        review.variant_type = T.must(PullRequestReview.variant_types[variant_type])
        review.body = @body

        if return_with_error
          # this metric is used to track whether the review was "successful" which we already know it wasn't if return_with_error is true,
          # so we can emit this before attempting to create comments
          emit_success_metric(success: false, reason: @error_reason || "return_with_error")
          if @error_reason == PullRequests::Copilot::CodeReviewAccess::Reason.actor_ineligible.reason.to_s
            review.body = ACTOR_INELIGIBLE
          elsif @error_reason == PullRequests::Copilot::CodeReviewAccess::Reason.actor_has_no_quota_remaining.reason.to_s
            review.body = ERROR_QUOTA
          elsif @error_reason == REASON_BILLING
            review.body = ERROR_BILLING
          elsif @error_reason == REASON_TOO_MANY_FILES
            review.body = ERROR_TOO_MANY_FILES
          elsif @error_reason == REASON_TOO_MANY_LINES
            review.body = ERROR_TOO_MANY_LINES
          elsif @error_reason == REASON_PR_TOO_LARGE
            review.body = ERROR_PR_TOO_LARGE
          elsif @error_reason == REASON_COPILOT_UNAVAILABLE
            review.body = ERROR_COPILOT_UNAVAILABLE
          elsif @error_reason == REASON_CONTENT_EXCLUDED
            review.body = ERROR_CONTENT_EXCLUDED
          elsif @error_reason == REASON_ENVIRONMENT_ERROR
            review.body = @error_review_body.presence || ERROR_COMMENTS
          else
            review.body = ERROR_COMMENTS
          end
          review.comment!
          if review.commented?
            emit_persistence_metric(success: true)
            return true
          else
            emit_persistence_metric(success: false, error_types: "comment_persistence")
            return false
          end
        elsif comments.empty?
          if review.body.present?
            submit_review_transition(review)
            if review_submitted_with_expected_state?(review)
              persistence_error_type = persist_ccr_decision_run_error_type(review)
              emit_success_metric(success: true)
              emit_persistence_metric(success: persistence_error_type.nil?, error_types: persistence_error_type)
              return true
            else
              emit_success_metric(success: false, reason: "comment_persistence")
              emit_persistence_metric(success: false, error_types: "comment_persistence")
              return false
            end
          end
          emit_success_metric(success: false, reason: "no_body")
          return false
        end

        comments.each do |comment|
          # Use commit OID from the comment if provided, otherwise fall back to the diff end commit OID
          commit_oid = comment[:commit_id] || diff_end_commit_oid

          # Build positioning hash from comment fields
          positioning = if comment[:start_line].present? && comment[:start_line] > 0
            # Multiline comment
            {
              type: "multiline",
              start_line: comment[:start_line],
              start_path: comment[:path],
              start_commit_oid: commit_oid,
              end_line: comment[:line],
              end_path: comment[:path],
              end_commit_oid: commit_oid,
              base_commit_oid: diff_start_commit_oid,
              head_commit_oid: commit_oid,
            }
          else
            # Single line comment
            {
              type: "line",
              line: comment[:line],
              path: comment[:path],
              commit_oid: commit_oid,
              base_commit_oid: diff_start_commit_oid,
              head_commit_oid: commit_oid,
            }
          end

          result = PullRequests::ReviewComments::Create.create_from_parameters(
            pull_request: pull,
            review: review,
            review_event: nil,
            body: comment[:body],
            actor: bot,
            destination_base_commit_oid: diff_start_commit_oid,
            destination_head_commit_oid: commit_oid,
            parameters: {
              positioning: positioning,
            }.compact
          )

          if result.is_a?(PullRequests::ReviewComments::Create::Error)
            GitHub.dogstats.increment("copilot_api.code_review.failed", tags: ["reason:review_submission", "mode:review"])
            GitHub.logger.error(
              "Failed to create review comment",
              "exception.message": result.errors.inspect,
              "gh.pull_request.id": pull.id,
              "gh.request_id": GitHub.context[:request_id],
            )

            # emit data for the "join" table so we can link generated reviews even if it failed generating
            payload = { generated_comment_uuid: comment[:comment_identifier], comment_creation_status: false, pull_request_id: pull.id }
            GlobalInstrumenter.instrument("copilot.reviews.v0.ReviewCommentPersistenceMapping", payload)
            GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping", payload)

            next
          end

          review_comment = result.comment

          begin
            create_review_comment_references(comment, review_comment)
          rescue => e
            GitHub.dogstats.increment("copilot_api.code_review.failed", tags: ["reason:review_submission", "mode:review"])
            GitHub.logger.error(
              "Failed to create review comment references",
              "exception.message": e.message,
              "gh.pull_request.id": pull.id,
              "gh.pull_request_review_comment.id": review_comment.id,
              "gh.request_id": GitHub.context[:request_id],
            )
          end

          comment_type = "automated"
          has_suggestion = comment[:autofix_diff].present?
          GitHub.dogstats.increment("copilot.code_review.comment_created", tags: ["type:#{comment_type}", "has_suggestion:#{has_suggestion}"])

          # emit data for the "join" table so we can link generated reviews
          payload = { generated_comment_uuid: comment[:comment_identifier], comment_id: review_comment.id.to_s, comment_creation_status: true, pull_request_id: pull.id, thread_id: review_comment.pull_request_review_thread_id }
          GlobalInstrumenter.instrument("copilot.reviews.v0.ReviewCommentPersistenceMapping", payload)
          GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping", payload)
        end

        # Submit the review and all pending comments in a single transaction
        # so the browser doesn't receive a WS notification before all comments
        # are visible. submit_pending_comments is a safety net in case
        # comment! callbacks don't submit them.
        GitHub.logger.info(
          "Submitting copilot review",
          "gh.pull_request.id": pull.id,
          "gh.pull_request_review.id": review.id,
          "gh.pull_request_review.state": review.current_state.name,
          "gh.request_id": GitHub.context[:request_id],
        )
        # Service sets skip_review_callbacks during comment creation;
        # reset it so the comment action guard, after_submission, and
        # after_commit callbacks fire correctly on the submit transition.
        review.skip_review_callbacks = false
        PullRequestReview.transaction do
          review.submitted_at = Time.zone.now
          submit_review_transition(review)
          submit_pending_comments(review)
        end
        if review_submitted_with_expected_state?(review)
          persistence_error_type = persist_ccr_decision_run_error_type(review)
          emit_persistence_metric(success: persistence_error_type.nil?, error_types: persistence_error_type)
          emit_success_metric(success: true)
          return true
        else
          emit_persistence_metric(success: false, error_types: "comment_persistence")
          emit_success_metric(success: false, reason: "comment_persistence")
          return false
        end
      end
    ensure
      GitHub.dogstats.distribution_timing_since("copilot_api.code_review.step.duration", start_time, tags: ["step:submit_review", "mode:review"])
    end

    private

    sig { returns(PullRequest) }
    attr_reader :pull

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    attr_reader :comments

    sig { returns(String) }
    attr_reader :commit_id

    sig { returns(T.nilable(String)) }
    attr_reader :body

    sig { returns(String) }
    attr_reader :diff_start_commit_oid, :diff_end_commit_oid, :diff_base_commit_oid

    sig { returns(Repository) }
    attr_reader :repo

    sig { returns(T::Boolean) }
    attr_reader :return_with_error

    sig { returns(Symbol) }
    attr_reader :review_event

    sig { returns(T.nilable(String)) }
    attr_reader :response_request_id

    sig { returns(T.nilable(String)) }
    attr_reader :approval_readiness_code

    sig { returns(T.nilable(String)) }
    attr_reader :experiment_assignment_context

    sig { returns(T::Boolean) }
    attr_reader :decision_assessment_required

    sig { params(success: T::Boolean, error_types: T.nilable(String)).void }
    def emit_persistence_metric(success:, error_types: nil)
      tags = ["success:#{success}"]
      tags << "error_types:#{error_types}" if error_types.present?
      GitHub.dogstats.increment("copilot.code_review.persistence", tags: tags)
    end

    sig { params(success: T::Boolean, reason: T.nilable(String)).void }
    def emit_success_metric(success:, reason: nil)
      tags = ["success:#{success}"]
      tags << "reason:#{reason}" if reason.present?
      GitHub.dogstats.increment("copilot.code_review.completed", tags: tags)
    end

    def submit_pending_comments(review)
      pending_comments = review.review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)
    end

    sig { params(review: PullRequestReview).returns(T::Boolean) }
    def submit_review_transition(review)
      case review_event
      when :approve
        review.approve!
      when :request_changes
        review.request_changes!
      else
        review.comment!
      end

      review_submitted_with_expected_state?(review)
    end

    sig { params(review: PullRequestReview).returns(T::Boolean) }
    def review_submitted_with_expected_state?(review)
      case review_event
      when :approve
        review.approved?
      when :request_changes
        review.changes_requested?
      else
        review.commented?
      end
    end

    sig { params(review: PullRequestReview).returns(T.nilable(String)) }
    def persist_ccr_decision_run_error_type(review)
      request_id = response_request_id
      if request_id.blank?
        GitHub.logger.warn(
          "Skipping CCR decision run persistence due to missing response request id",
          "gh.pull_request.id": pull.id,
          "gh.pull_request_review.id": review.id,
          "gh.request_id": GitHub.context[:request_id],
        )
        return PERSISTENCE_ERROR_MISSING_RESPONSE_REQUEST_ID
      end

      PullRequests::Copilot::CcrDecisionRunStore.record(
        response_request_id: T.must(request_id),
        pull_request_id: pull.id,
        repository_id: repo.id,
        pull_request_review_id: review.id,
        submitted_at: review.submitted_at || review.created_at,
        head_sha: review.head_sha,
        approval_readiness_code: approval_readiness_code,
        review_submission_event: review_event.to_s,
        experiment_assignment_context: experiment_assignment_context,
        decision_assessment_required: decision_assessment_required,
      )
      nil
    rescue => e
      GitHub.logger.error(
        "Failed to persist CCR decision run",
        "exception.message": e.message,
        "gh.pull_request.id": pull.id,
        "gh.pull_request_review.id": review.id,
        "gh.request_id": GitHub.context[:request_id],
      )
      PERSISTENCE_ERROR_KV_WRITE_FAILURE
    end

    def create_review_comment_references(comment, review_comment)
      GitHub.logger.info(
        "Create AutomatedReviewComment references",
        "comment": comment,
        "review_comment": review_comment
      )
      suggestion = nil

      if comment[:autofix_diff].present?
        GitHub.logger.info(
          "AutomatedReviewComment suggestion present",
          "comment": comment
        )
        suggestion = ReviewComments::Suggestion.new(
          commit_sha: commit_id,
          files: [
            ReviewComments::Suggestion::File.new(
              path: comment[:path],
              diff_content: comment[:autofix_diff]
            )
          ]
        )
      else
        GitHub.logger.info(
          "AutomatedReviewComment suggestion NOT present",
          "comment": comment
        )
      end

      automated_review_comment = AutomatedReviewComment.create!(
        pull_request: pull,
        repository: repo,
        pull_request_review_comment: review_comment,
        source: :source_copilot,
        resource_id: comment[:comment_identifier].presence || "copilot-#{review_comment.id}",
        message: comment[:body],
        suggestion: suggestion,
        suggestion_state: suggestion.present? ? :suggestion_state_present : :suggestion_state_no_suggestion,
        severity: comment[:severity].present? ? SEVERITIES_FOR_AUTOMATED_REVIEW[comment[:severity]] : REVIEW_SEVERITY_NONE,
        problem_type: comment[:problem_type],
      )

      GitHub.logger.info(
        "Create AutomatedReviewComment created",
        "automated_review_comment": automated_review_comment
      )

      return unless comment.has_key?(:guideline_id)
      return unless comment[:problem_type] == CODING_GUIDELINE_PROBLEM_TYPE

      comment_reference_id = comment[:guideline_id].to_i
      copilot_instruction_type = nil

      if comment_reference_id == PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_ORG_INSTRUCTIONS_ID
        copilot_instruction_type = "org"
      elsif comment_reference_id == PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_REPO_INSTRUCTIONS_ID || comment_reference_id >= PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_INSTRUCTIONS_MD_BASE_ID
        copilot_instruction_type = "repo"
      end

      return if copilot_instruction_type.nil?

      PullRequests::Copilot::CodeReviewComment.create!(
        subject: review_comment,
        repository_id: repo.id,
        copilot_instruction_type: copilot_instruction_type,
      )
    end
  end
end
