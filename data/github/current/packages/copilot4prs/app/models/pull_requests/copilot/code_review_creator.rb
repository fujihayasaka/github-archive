# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewCreator
    extend T::Sig

    NO_COMMENTS_BODY = "Copilot did not find any suggestions for this pull request"

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
      ).void
    end
    def initialize(pull:, repo:, comments:, commit_id:, body:, diff_start_commit_oid:, diff_end_commit_oid:, diff_base_commit_oid:)
      @pull = pull
      @repo = repo
      @comments = comments
      @commit_id = commit_id
      @body = body
      @diff_start_commit_oid = diff_start_commit_oid
      @diff_end_commit_oid = diff_end_commit_oid
      @diff_base_commit_oid = diff_base_commit_oid
    end

    sig { returns(T::Boolean) }
    def create
      start_time = GitHub::Dogstats.monotonic_time
      success = T.let(true, T::Boolean)

      bot = Apps::Internal.integration(:copilot_pull_request_reviewer).bot

      ActiveRecord::Base.connected_to(role: :writing) do
        review = pull.pending_review_for(user: bot, head_sha: commit_id)
        review.variant_type = T.must(PullRequestReview.variant_types[:copilot])
        if body.present?
          review.body = body
        end

        if comments.empty?
          if body.present?
            review.comment!
          elsif pull.user&.feature_enabled?(:copilot_pr_reviews_submit_empty_reviews)
            # Reviews currently can't be submitted with no body, so we need to add a comment.
            review.body = NO_COMMENTS_BODY
            review.comment!
          else
            GitHub.logger.info(
              "Empty Copilot review, skipping submission.",
              "gh.pull_request.id": pull.id,
            )
          end
        else
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

              success = false
              review.destroy

              break
            end
          end
        end
      end

      success
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

    def symbolize_input_with_default(input:, default:)
      input.present? ? input.to_sym : default
    end

    def integerize_input_with_default(input:, default:)
      return default unless input.present?
      input > 0 ? input.to_i : default
    end
  end
end
