# typed: true
# frozen_string_literal: true

module Reminders
  class CommentReplyFinder
    def self.events(review_comment)
      new(review_comment).events
    end

    attr_reader :actor, :context, :review_comment, :pull_request, :organization, :subject, :type
    def initialize(review_comment)
      @review_comment = review_comment

      @actor = review_comment.user
      @context = { comment_body: review_comment.body, comment_html_url: review_comment.permalink }
      @pull_request = review_comment.pull_request_review.pull_request
      @organization = pull_request.repository.owner
      @subject = review_comment
      @type = :comment_reply
    end

    def reminders
      @reminders ||= PersonalReminder.
        for_remindable(organization).
        for_event_type(type).
        where(user_id: thread_member_ids).
        where.not(user_id: review_comment.user_id)
    end

    def thread_member_ids
      thread_member_ids = review_comment.in_reply_to.submitted_replies.distinct.pluck(:user_id)
      thread_member_ids << review_comment.in_reply_to.user_id

      thread_member_ids.uniq
    end

    def valid?
      review_comment&.reply? && \
      review_comment.user_id && \
      review_comment.in_reply_to
    end

    def events
      return [] unless valid?

      reminders.map do |reminder|
        Reminders::RealTimeEvent.new(
          actor: actor,
          context: context,
          type: type,
          reminder: reminder,
          pull_request_ids: [pull_request.id],
          repository_id: pull_request.repository_id,
          subject: review_comment,
        )
      end
    end
  end
end
