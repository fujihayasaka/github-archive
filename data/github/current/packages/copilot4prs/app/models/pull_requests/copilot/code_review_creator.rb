# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewCreator
    ERROR_COMMENTS = "Copilot encountered an error and was unable to review this pull request. You can try again by re-requesting a review."
    CODING_GUIDELINE_PROBLEM_TYPE = "custom"

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
        return_with_error: T::Boolean,
      ).void
    end
    def initialize(pull:, repo:, comments:, commit_id:, body:, diff_start_commit_oid:, diff_end_commit_oid:, diff_base_commit_oid:, return_with_error: false)
      @pull = pull
      @repo = repo
      @comments = comments
      @commit_id = commit_id
      @body = body
      @diff_start_commit_oid = diff_start_commit_oid
      @diff_end_commit_oid = diff_end_commit_oid
      @diff_base_commit_oid = diff_base_commit_oid
      @return_with_error = return_with_error
      @copilot_repo_instructions_id = PullRequests::Copilot::CodeReviewGenerator::COPILOT_REPO_INSTRUCTIONS_ID
    end

    sig { returns(T::Boolean) }
    def create
      start_time = GitHub::Dogstats.monotonic_time
      generated_comment_results = T.let([], T::Array[T::Boolean])

      bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
      previously_reviewed = pull.latest_non_pending_review_for(bot)

      ActiveRecord::Base.connected_to(role: :writing) do
        review = pull.pending_review_for(user: bot, head_sha: commit_id)
        review.variant_type = T.must(PullRequestReview.variant_types[:copilot])
        review.body = @body

        if return_with_error
          review.body = ERROR_COMMENTS
          review.comment!
          return review.commented? ? true : false
        elsif comments.empty?
          if review.body.present?
            review.comment!
            minimize_review(previously_reviewed, bot)
            return review.commented? ? true : false
          end
          return false
        end

        comments.each_with_index do |comment, i|
          result = PullRequests::ReviewComments::Create.create(
              author: bot,
              body: comment[:body],
              diff_start_commit_oid:,
              diff_end_commit_oid:,
              diff_base_commit_oid:,
              line: comment[:line],
              path: comment[:path],
              pull_request: pull,
              review: review,
              repository: repo,
              side: comment[:side].parameterize.underscore.to_sym,
              start_line: integerize_input_with_default(input: comment[:start_line], default: nil),
              start_side: symbolize_input_with_default(input: comment[:start_side], default: :right),
              subject_type: symbolize_input_with_default(input: nil, default: :line),
              submit_review: i == comments.size - 1,
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

            generated_comment_results << false
            next
          end

          review_comment = result.comment
          if generated_from_repo_custom_instruction?(comment)
            PullRequests::Copilot::CodeReviewComment.create!(
              subject: review_comment,
              repository_id: repo.id,
              copilot_instruction_type: "repo",
            )
          elsif generated_from_coding_guideline?(comment)
            PullRequests::Copilot::CodeReviewComment.create!(
              subject: review_comment,
              repository_id: repo.id,
              copilot_coding_guideline_id: comment[:guideline_id]
            )
          end

          generated_comment_results << true

          # emit data for the "join" table so we can link generated reviews
          payload = { generated_comment_uuid: comment[:comment_identifier], comment_id: review_comment.id.to_s, comment_creation_status: true }
          GlobalInstrumenter.instrument("copilot.reviews.v0.ReviewCommentPersistenceMapping", payload)
          GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping", payload)
        end

        if generated_comment_results.none?
          review.destroy
          GitHub.logger.error(
            "No Copilot review comments were posted",
            "gh.pull_request.id": pull.id,
            "gh.request_id": GitHub.context[:request_id],
          )
          return false
        end

        # edge case: failed on the last comment therefore review wasn't submitted
        # we need to submit all the pending comments one by one
        unless review.commented?
          GitHub.logger.info(
            "Review wasn't posted, submitting pending comments",
            "gh.pull_request.id": pull.id,
            "gh.request_id": GitHub.context[:request_id],
          )
          PullRequestReview.transaction do
            review.submitted_at = Time.zone.now
            review.comment!
            submit_pending_comments(review)
          end
        end
        minimize_review(previously_reviewed, bot)
        review.commented? ? true : false
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

    def symbolize_input_with_default(input:, default:)
      input.present? ? input.to_sym : default
    end

    def integerize_input_with_default(input:, default:)
      return default unless input.present?
      input > 0 ? input.to_i : default
    end

    def generated_from_coding_guideline?(copilot_api_comment)
      return false unless copilot_api_comment[:problem_type] == CODING_GUIDELINE_PROBLEM_TYPE
      copilot_api_comment[:guideline_id].present? && copilot_api_comment[:guideline_id].to_i != @copilot_repo_instructions_id
    end

    def generated_from_repo_custom_instruction?(copilot_api_comment)
      return false unless copilot_api_comment[:problem_type] == CODING_GUIDELINE_PROBLEM_TYPE
      copilot_api_comment[:guideline_id].present? && copilot_api_comment[:guideline_id].to_i == @copilot_repo_instructions_id
    end

    def submit_pending_comments(review)
      pending_comments = review.review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)
    end

    def minimize_review(review, actor)
      return unless review
      return if review.minimized?
      return unless @repo.feature_enabled?(:copilot_code_review_hide_previous_review)

      review.set_minimized(actor, nil, "OUTDATED", actor)
    end
  end
end
