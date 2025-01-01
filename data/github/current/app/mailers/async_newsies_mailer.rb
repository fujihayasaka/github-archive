# typed: false
# frozen_string_literal: true

class AsyncNewsiesMailer < NewsiesMailer
  class MissingArgumentsError < StandardError; end
  self.delivery_job = AsyncNewsiesDeliveryJob

  def notification_from_ids(summary_id, comment_class, comment_id, user_id, options)
    ActiveRecord::Base.connected_to(role: :reading) do
      summary = NotificationSummary.find_by_id(summary_id)
      comment = comment_class.constantize.find_by_id(comment_id)

      # Summary and comment are read from replica and could be recently created
      # We can't proceed without having both parameters,
      # so we throw error here and retry in AsyncNewsiesDeliveryJob
      if summary.nil? || comment.nil?
        raise MissingArgumentsError
      end

      settings_user = User.find_by_id(user_id)

      return if settings_user.nil?

      settings_response = GitHub.newsies.settings(settings_user)
      delivery = Newsies::Delivery.new(summary, comment)

      # Some comments (like IssueEventNotification and RepositoryAdvisoryEvent) need to know who they are being delivered to
      # as delivery is happening.
      #
      # We duplicated this logic from deliver_notifications_job.rb
      # register_recipient should be changed as it does extra user lookup.
      # See issue: https://github.com/github/notifications/issues/806
      if delivery.comment.respond_to?(:register_recipient)
        delivery.comment.register_recipient settings_user.id
      end

      message = Newsies::Emails::MessageResolver.message_for(delivery, settings_response.value!, options)
      notification(message)
    end
  end
end
