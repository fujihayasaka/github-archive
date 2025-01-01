# typed: true
# frozen_string_literal: true

class RecalculateUserDiscussionsJob < ApplicationJob
  queue_as :recalculate_user_discussions

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(user, last_processed_comment_id: nil)
    return unless user.spammy? || user.suspended?

    discussion_spotlight_ids = user.discussions.joins(:spotlight).pluck("discussion_spotlights.id")

    if discussion_spotlight_ids.any?
      with_write { DiscussionSpotlight.destroy_by(id: discussion_spotlight_ids) }
    end

    chosen_comments = user.discussion_comments.chosen_answers.limit(BATCH_SIZE).order(:id)
    if last_processed_comment_id
      chosen_comments = chosen_comments.where("discussion_comments.id > ?", last_processed_comment_id)
    end
    if chosen_comments.load.any?
      with_write { DiscussionComment.unmark_as_answers(chosen_comments) }
      RecalculateUserDiscussionsJob.perform_later(user, last_processed_comment_id: chosen_comments.last.id)
    end
  end
end
