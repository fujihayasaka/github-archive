# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class PullRequestPostProcessor < BasePostProcessor
      def joins
        %i(issue review_comments)
      end

      # Public: Post processing a pull request does the following:
      #
      #   1. Rewrites urls referencing other issues in review comment bodies.
      #   2. Rewrites @mentions in review comment bodies.
      #   3. Post processes the associated issue.
      #   4. Update the comment count
      def process(pull_request, attributes, batch_load_associations: false)
        if batch_load_associations
          review_comment_ids = pull_request.review_comments.pluck(:id)

          review_comment_ids.each_slice(BATCH_SIZE) do |review_comment_batch_ids|
            # batch update updated_at, fix for referred_at
            PullRequestReviewComment.where(id: review_comment_batch_ids).update_all("pull_request_review_comments.updated_at = pull_request_review_comments.created_at")

            # Rewrite body content
            PullRequestReviewComment.where(id: review_comment_batch_ids).find_each do |review_comment|
              rewrite_comment(review_comment)
            end
          end
        else
          # fix for referred_at
          pull_request.review_comments.update_all("pull_request_review_comments.updated_at = pull_request_review_comments.created_at")
          pull_request.review_comments.each do |review_comment|
            rewrite_comment(review_comment)
          end
        end

        issue_post_processor.process(pull_request.issue, attributes)
      end

      private

      # Internal: Memoized GitHub::Migrator::IssuePostProcessor instance for
      # processing the Issue associated with a PullRequest.
      #
      # Returns a GitHub::Migrator::IssuePostProcessor.
      def issue_post_processor
        @issue_post_processor ||= \
          GitHub::Migrator::IssuePostProcessor.new(post_processor_options)
      end
    end
  end
end
