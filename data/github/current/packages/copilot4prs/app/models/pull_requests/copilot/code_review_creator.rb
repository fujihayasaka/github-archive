# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewCreator
    ERROR_COMMENTS = "Copilot encountered an error and was unable to review this pull request. You can try again, by re-requesting a review."

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
    end

    sig { returns(T::Boolean) }
    def create
      start_time = GitHub::Dogstats.monotonic_time
      success = T.let(true, T::Boolean)
      generated_comment_results = T.let([], T::Array[T::Boolean])

      bot = Apps::Privileged.integration(:copilot_pull_request_reviewer).bot

      # make sure that the user didn't cancel their review request
      if @pull.direct_review_request_for(bot).nil?
        GitHub.dogstats.increment("copilot_api.code_review.cancelled", tags: ["mode:review"])
        return false
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        review = pull.pending_review_for(user: bot, head_sha: commit_id)
        review.variant_type = T.must(PullRequestReview.variant_types[:copilot])
        review.body = @body

        if return_with_error && pull.user&.feature_enabled?(:copilot_pr_reviews_submit_error)
          review.body = ERROR_COMMENTS
          review.comment!
          generated_comment_results << true
        elsif comments.empty?
          if review.body.present?
            review.comment!
            generated_comment_results << true
          end
        end

        comments.each_with_index do |comment, i|
          adjusted_body = comment[:body]
          if comment[:problem_type] == "custom"
            adjusted_body += "\n\n_This comment was generated based on a coding guideline created by a repository admin._"
          end

          result = PullRequests::ReviewComments::Create.create(
              author: bot,
              body: adjusted_body,
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

          generated_comment_results << true

          # emit data for the "join" table so we can link generated reviews
          payload = { generated_comment_uuid: comment[:comment_identifier], comment_id: result.comment.id.to_s, comment_creation_status: true }
          GlobalInstrumenter.instrument("copilot.reviews.v0.ReviewCommentPersistenceMapping", payload)
          GlobalInstrumenter.instrument("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping", payload)
        end

        if generated_comment_results.none?
          review.destroy
          success = false
          GitHub.logger.error(
            "No Copilot review comments were posted",
            "gh.pull_request.id": pull.id,
            "gh.request_id": GitHub.context[:request_id],
          )
        end

        success
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
  end
end
