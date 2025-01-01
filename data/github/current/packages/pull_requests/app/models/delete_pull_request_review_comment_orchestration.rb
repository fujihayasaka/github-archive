# typed: true
# frozen_string_literal: true

class DeletePullRequestReviewCommentOrchestration < PullRequestReviewCommentOrchestration
  include PullRequests::Orchestrations::DataAttributes

  def only_save_on_orchestration_end? = true

  data :actor, User
  data :comment_user, User

  step :validate_deletion do
    if comment.code_scanning? && !comment.pull_destroyed?
      comment.errors.add(:base, "Comment cannot be deleted during code scanning.")
      # rubocop:disable Style/RedundantReturn
      return :skipped, "Failed to delete comment: #{comment.errors.full_messages}."
    end
  end

  step :generate_webhook_payloads do
    delivery_system&.generate_hookshot_payloads
  end

  step :destroy_comment do
    transaction do
      comment.skip_destroy_callbacks = true
      comment.destroy!
      comment.pull_request_review_thread&.destroy_if_empty
    end
  end

  step :queue_webhook_delivery do
    delivery_system&.deliver_later
  end

  step :instrument_deletion do
    return unless repository = self.repository

    comment.instrument :delete, repo: repository, actor: actor, author: actor

    GlobalInstrumenter.instrument("pull_request_review_comment.delete", {
      actor: actor,
      pull_request: pull_request,
      repository: repository,
      review_comment: comment,
      pull_request_review: comment.pull_request_review,
      pull_request_review_thread: comment.pull_request_review_thread,
    })
  end

  step :clean_up_review_and_review_thread do
    comment.pull_request_review&.destroy_if_empty
  end

  step :unresolve_thread_if_not_conversation do
    if comment.pull_request_review_thread&.resolved? & !comment.pull_request_review_thread&.conversation?
      comment.pull_request_review_thread&.unresolve(unresolver: Apps::Internal.integration(:code_scanning).bot)
    end
  end

  step :reparent_replies do
    GitHub.dogstats.time("pull_request_review_comment", tags: ["action:reparent_replies"]) do
      new_parent_id = comment.class.connection.select_value(Arel.sql(<<-SQL, pull_request_id: comment.pull_request_id, reply_to_id: comment.id))
      SELECT id FROM pull_request_review_comments
      WHERE pull_request_id = :pull_request_id AND reply_to_id = :reply_to_id
      ORDER BY created_at
      LIMIT 1
      SQL

      return unless new_parent_id

      comment.class.connection.update(Arel.sql(<<-SQL, new_parent_id: new_parent_id, pull_request_id: comment.pull_request_id, reply_to_id: comment.id))
        UPDATE pull_request_review_comments
        SET reply_to_id = :new_parent_id
        WHERE pull_request_id = :pull_request_id AND reply_to_id = :reply_to_id AND id != :reply_to_id
      SQL

      comment.class.connection.update(Arel.sql(<<-SQL, id: new_parent_id))
        UPDATE pull_request_review_comments
        SET reply_to_id = NULL
        WHERE id = :id
      SQL
    end
  end

  step :touch_pull_request_after_commit do
    return unless pull_request = self.pull_request

    pull_request.touch
  end

  # Steps called after job_start run asynchronously.
  # Adding steps with new names after job_start may cause invalid step name
  # orchestration errors.
  # When migrating syncrhonous steps to run asynchronously, it is recommended to
  # rename the existing step rather than adding a new step after job_start:

  # step :temporary_renamed_X
  # job_start
  # step :X

  job_start

  step :generate_issue_event do
    issue = pull_request.try(:issue)
    if issue && actor != comment_user
      issue.events.create \
        event: "comment_deleted",
        actor: actor,
        subject: comment_user
    end
  end

  # `pull_request.update_review_comments_count` triggers the recalculation
  # of the values for the review_comments_with_body_count and
  # reviews_with_body_count columns on the pull request record. Right now
  # the action of deleting a pull request review comment in production
  # does not invoke any hook to update the count of comments displayed to
  # a user on the pull pull request files page; the count only changes on
  # a page refresh. There is also no api contract for returning the updated
  # count of total comments associated to the pull request either in the
  # REST api or graphql API. This step has successfully been tested as
  # running in the background across 100% of actors in the dotcom env
  step :update_pull_request_counters do
    return unless pull_request = self.pull_request

    pull_request.update_review_comments_count

    if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
      Platform::Schema.subscriptions.trigger(
        :pull_request_comments_updated,
        { id: pull_request.global_relay_id }
      )
    end
  end

  step :notify_pull_request_channel do
    return unless pull_request = self.pull_request

    if pull_request.requires_review_thread_resolution?
      channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
      GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
    end
  end

  sig { returns(T::Boolean) }
  def skip_pull_request_id_validation = true

  sig { returns(T::Boolean) }
  def skip_pull_request_review_comment_id_validation = true

  sig { returns(PullRequestReviewComment) }
  def comment
    @comment ||= self.pull_request_review_comment
  end

  sig { returns(T.nilable(Hook::DeliverySystem)) }
  def delivery_system
    @delivery_system ||= if !comment.user_hidden? && !comment.pending? && !actor.spammy?
      event = Hook::Event::PullRequestReviewCommentEvent.new(
        action: :deleted,
        pull_request_review_comment_id: comment.id,
        actor_id: actor.id,
        triggered_at: Time.now)
      Hook::DeliverySystem.new(event)
    else
      nil
    end
  end
end
