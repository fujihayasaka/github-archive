# typed: true
# frozen_string_literal: true

class MinimizeAllCommentsOnRepoJob < ApplicationJob
  queue_as :minimize_all_comments_on_repo
  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(org, user, actor, minimize_reason)
    user_id = user.id

    org.repositories.pluck(:id).each do |repository_id|
      IssueComment.where(repository: repository_id, user_id: user_id).find_each(batch_size: BATCH_SIZE) do |comment|
        with_write { comment.set_minimized(actor, minimize_reason, minimize_reason, user) }
      end

      CommitComment.where(repository: repository_id, user_id: user_id).find_each(batch_size: BATCH_SIZE) do |comment|
        with_write { comment.set_minimized(actor, minimize_reason, minimize_reason, user) }
      end

      PullRequestReviewComment.joins(:pull_request)
        .where("pull_request_review_comments.user_id = ? and pull_requests.repository_id = ? ", user_id, repository_id)
        .find_each(batch_size: BATCH_SIZE) do |comment|
        with_write { comment.set_minimized(actor, minimize_reason, minimize_reason, user) }
      end

      # discussions expects the minimize_reason to be lowercased
      discussion_minimize_reason = T.must(Platform::Enums::ReportedContentClassifiers.values[minimize_reason]).value
      DiscussionComment.where(repository: repository_id, user_id: user_id).find_each(batch_size: BATCH_SIZE) do |comment|
        with_write { comment.set_minimized(actor, discussion_minimize_reason, discussion_minimize_reason, user) }
      end
    end
  end
end
