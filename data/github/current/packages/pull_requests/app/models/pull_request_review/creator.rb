# typed: true
# frozen_string_literal: true

class PullRequestReview
  class Creator

    class Result
      attr_accessor :errors
      attr_reader :review

      def initialize(review:, errors: [])
        @review = review
        @errors = errors
      end

      def success?
        @errors.empty?
      end
    end

    def self.execute(pull_request:, user:, body: nil, comments: [], event: nil, pull_comparison: nil)
      new(
        pull_request: pull_request,
        user: user,
        body: body,
        comments: comments,
        event: event,
        pull_comparison: pull_comparison || PullRequest::Comparison.find(
          pull: pull_request,
          start_commit_oid: pull_request.merge_base,
          end_commit_oid: pull_request.head_sha,
          base_commit_oid: pull_request.merge_base,
        ),
      ).execute
    end

    def initialize(pull_request:, user:, body:, comments:, event:, pull_comparison:)
      @pull_request = pull_request
      @user = user
      @body = body
      @comments = comments
      @event = event
      @pull_comparison = pull_comparison
    end

    attr_reader :pull_request, :user, :body, :comments, :event, :pull_comparison

    def execute
      head_sha = pull_comparison.end_commit.oid

      review = pull_request.reviews.build(
        body: body,
        user: user,
        head_sha: head_sha,
        merge_base_sha: pull_request.find_best_merge_base_sha(head_sha: head_sha),
      )
      errors = []

      # If GitHub Actions GITHUB_TOKEN is making the request, check whether
      # Actions workflows are allowed to approve PRs:
      if actions_user_requesting_approval? && disallow_actions_approvals?
        errors << "GitHub Actions is not permitted to approve pull requests."
      end
      async_pr_review_comment_callbacks = GitHub.flipper[:async_pr_review_comment_callbacks].enabled?(user)

      if errors.empty?
        PullRequestReview.transaction do
          unless review.save
            errors.concat(review.errors.full_messages)
            raise ActiveRecord::Rollback
          end

          comments.each do |draft_comment|
            comment = nil

            if parent_id = draft_comment[:in_reply_to]
              parent = pull_request.review_comments.find(parent_id)
              thread = parent.pull_request_review_thread

              comment = thread.build_reply(
                pull_request_review: review,
                user: user,
                body: draft_comment[:body],
              )
            else
              if draft_comment[:line].present?
                thread = review.build_thread
                comment = thread.build_first_comment(
                  user: user,
                  diff: pull_comparison.diffs.only_params,
                  body: draft_comment[:body],
                  path: draft_comment[:path],
                  line: draft_comment[:line],
                  side: draft_comment[:side]&.downcase&.to_sym || :right,
                  start_line: draft_comment[:start_line],
                  start_side: draft_comment[:start_side]&.downcase&.to_sym || :right,
                )
              else
                thread, comment = review.build_thread_with_comment(
                  user: user,
                  body: draft_comment[:body],
                  diff: pull_comparison.diffs.only_params,
                  position: draft_comment[:position],
                  path: draft_comment[:path],
                )
              end
            end

            comment.bulk_creating = true if async_pr_review_comment_callbacks

            unless comment.save
              errors.concat(comment.errors.full_messages)
              raise ActiveRecord::Rollback
            end

            unless thread.save
              errors.concat(thread.errors.full_messages)
              raise ActiveRecord::Rollback
            end
          end

          if event
            unless review.trigger(event)
              errors << review.halted_because if review.halted?
              raise ActiveRecord::Rollback
            end
          end
        end

        ReviewCommentBulkCreationCallbacksJob.perform_later(pull_request_review: review) if async_pr_review_comment_callbacks && review.persisted?
      end

      Result.new(review: review, errors: errors)
    end

    def actions_user_requesting_approval?
      @user.can_have_granular_permissions? &&
      (integration = @user.try(:integration)) &&
      integration.launch_github_app? &&
      event&.to_sym == :approve
    end

    def disallow_actions_approvals?
      !@pull_request.repository.actions_workflow_permission_can_approve_pr? # Actions review does NOT count towards approval
    end
  end
end
