# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewCreator
    ERROR_COMMENTS = "Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."
    ERROR_COPILOT_UNAVAILABLE = "Copilot is currently unavailable to review this pull request. Please try again later."
    ERROR_BILLING = "Copilot encountered an error: Your billing is not configured or you have Copilot licenses from multiple standalone organizations or enterprises. To use premium requests, select a billing entity via the GitHub site, under Settings > Copilot > Billing."
    ERROR_QUOTA = "Copilot was unable to review this pull request because the user who requested the review has reached their quota limit."
    ERROR_TOO_MANY_FILES = "Copilot wasn't able to review this pull request because it exceeds the maximum number of files (300). Try reducing the number of changed files and requesting a review from Copilot again."
    ERROR_TOO_MANY_LINES = "Copilot wasn't able to review this pull request because it exceeds the maximum number of lines (20,000). Try reducing the number of changed lines and requesting a review from Copilot again."
    ERROR_PR_TOO_LARGE = "Copilot wasn't able to review this pull request because it exceeds the maximum diff size. Try reducing the number of changed files and lines, and requesting a review from Copilot again."
    ACTOR_INELIGIBLE = "Copilot was unable to review this pull request because the user who requested the review is ineligible. To be eligible to request a review, you need a paid Copilot license, or your organization must enable Copilot code review."

    REASON_BILLING = "billing"
    REASON_TOO_MANY_FILES = "too_many_files"
    REASON_TOO_MANY_LINES = "too_many_lines"
    REASON_PR_TOO_LARGE = "pr_too_large"
    REASON_COPILOT_UNAVAILABLE = "copilot_unavailable"
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
      ).void
    end
    def initialize(pull:, repo:, comments:, commit_id:, body:, diff_start_commit_oid:, diff_end_commit_oid:, diff_base_commit_oid:, review_event: :comment, return_with_error: false, error_reason: nil)
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
    end

    sig { returns(T::Boolean) }
    def create
      start_time = GitHub::Dogstats.monotonic_time

      bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
      is_automated_review_enabled = FeatureFlag.vexi.enabled?(:ccr_automated_review_comment_migration, pull.repository, default: false)
      variant_type = is_automated_review_enabled ? :automated : :copilot

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
              emit_success_metric(success: true)
              emit_persistence_metric(success: true)
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
            payload = { generated_comment_uuid: comment[:comment_identifier], comment_creation_status: false }
            GlobalInstrumenter.instrument("copilot.reviews.v0.ReviewCommentPersistenceMapping", payload)
            GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping", payload)

            next
          end

          review_comment = result.comment

          begin
            create_review_comment_references(comment, review_comment, is_automated_review_enabled)
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

          # emit data for the "join" table so we can link generated reviews
          payload = { generated_comment_uuid: comment[:comment_identifier], comment_id: review_comment.id.to_s, comment_creation_status: true }
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
          emit_persistence_metric(success: true)
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

    sig { params(success: T::Boolean, error_types: T.nilable(String)).void }
    def emit_persistence_metric(success:, error_types: nil)
      GitHub.dogstats.increment("copilot.code_review.persistence", tags: ["success:#{success}", "error_types:#{error_types}"])
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

    def create_review_comment_references(comment, review_comment, is_automated_review_enabled)
      if is_automated_review_enabled
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
          severity: comment[:severity].present? ? SEVERITIES_FOR_AUTOMATED_REVIEW[comment[:severity]] : REVIEW_SEVERITY_NONE
        )

        GitHub.logger.info(
          "Create AutomatedReviewComment created",
          "automated_review_comment": automated_review_comment
        )
      end

      return unless comment.has_key?(:guideline_id)
      return unless comment[:problem_type] == CODING_GUIDELINE_PROBLEM_TYPE

      comment_reference_id = comment[:guideline_id].to_i
      copilot_instruction_type = nil
      copilot_coding_guideline_id = nil

      if comment_reference_id == PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_ORG_INSTRUCTIONS_ID
        copilot_instruction_type = "org"
      elsif comment_reference_id == PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_REPO_INSTRUCTIONS_ID || comment_reference_id >= PullRequests::Copilot::CodeReview::Reference::Generator::COPILOT_INSTRUCTIONS_MD_BASE_ID
        copilot_instruction_type = "repo"
      else
        copilot_coding_guideline_id = comment[:guideline_id]
      end

      PullRequests::Copilot::CodeReviewComment.create!(
        subject: review_comment,
        repository_id: repo.id,
        copilot_instruction_type:,
        copilot_coding_guideline_id:,
      )
    end
  end
end
