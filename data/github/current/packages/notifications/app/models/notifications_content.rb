# typed: true
# frozen_string_literal: true

module NotificationsContent
  extend T::Helpers
  include GitHub::UserContent
  include Notifications::Mentionable
  include Notifications::SubscribableThread
  include Notifications::Summarizable

  requires_ancestor { ActiveRecord::Base }

  DELAY_TO_AVOID_DUPLICATE_DELIVERIES = 5.seconds

  # Public: Include this module in your model if you want to handle
  # subscriptions and deliveries manually.
  module WithoutCallbacks
    extend ActiveSupport::Concern

    include NotificationsContent
  end

  # Public: Include this module in your model if you want subscriptions and
  # deliveries to be handled automatically.
  # manually.
  module WithCallbacks
    extend ActiveSupport::Concern
    extend T::Helpers

    include NotificationsContent

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.class_of(ActiveRecord::Base))

      # Use the following callbacks on your model to handle subscribe and notify
      # via a background job.
      #
      # after_commit :subscribe_and_notify, on: :create
      # after_commit :update_subscriptions_and_notify, on: :update

      after_commit :update_notification_summary, on: :update, if: :update_notification_summary?
      before_update :get_changed_attributes_for_summary
      after_commit :destroy_notification_summary, on: :destroy, if: :related_repo_exists_when_defined
    end
  end

  def self.included(base)
    raise <<~ERR.squish
      Please include either NotificationsContent::WithCallbacks or
      NotificationsContent::WithoutCallbacks rather than including
      NotificationsContent directly; this clarifies intent.
      ERR
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo.  Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of Users that can be unsubscribed.
  def unsubscribable_users(users)
    raise NotImplementedError, self.class.name
  end

  # If the author of the model should be subscribed as part of the background jobs this method
  # should be overridden to return the subscribe reason
  def author_subscribe_reason
    nil
  end

  # Override this method and return true to defer loading mentions until the worker runs.
  def defer_loading_mentions?
    false
  end

  def subscribe_and_notify
    if defer_loading_mentions?
      SubscribeAndNotifyJob.perform_later( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        self,
        load_mentioned_users: true,
        load_mentioned_teams: true,
        previous_body: try(:body_previous_change),
        deliver_notifications: ::GitHub.send_notifications? && deliver_notifications?,
        author: self.try(:user),
        author_subscribe_reason: author_subscribe_reason,
        subscriber_reasons_and_ids: self.try(:subscriber_reasons_and_ids),
      )
    else
      SubscribeAndNotifyJob.perform_later(
        self,
        mentioned_user_ids: mentioned_users.map(&:id),
        mentioned_team_ids: mentioned_teams.map(&:id),
        deliver_notifications: ::GitHub.send_notifications? && deliver_notifications?,
        author: self.try(:user),
        author_subscribe_reason: author_subscribe_reason,
        subscriber_reasons_and_ids: self.try(:subscriber_reasons_and_ids),
      )
    end
  end

  def update_subscriptions_and_notify
    return unless try(:body_previously_changed?)

    job_class = UpdateSubscriptionsAndNotifyJob
    spam_check_delay_served = false
    wait_period = 0

    # If the subject was created within the last 5 seconds we want to delay the job.
    # A short delay will allow the DeliverNotificationsJob for the creation event to run first.
    # Without a delay, the UpdateSubscriptionsAndNotifyJob can add subscriptions for mentions,
    # which the creation event's DeliverNotificationsJob will then send notifications for.
    # This can result in duplicate notification deliveries.
    if try(:created_at) && try(:created_at) >= DELAY_TO_AVOID_DUPLICATE_DELIVERIES.ago
      wait_period += DELAY_TO_AVOID_DUPLICATE_DELIVERIES
    end

    # Wait for a short period to give async spam checks time to finish https://github.com/github/notifications/issues/296
    spam_check_delay_served = GitHub::SpamChecker.external_spamminess_check_enabled?
    if spam_check_delay_served
      wait_period += GitHub::SpamChecker::DELAY_FOR_EXTERNAL_CHECKS
    end

    if wait_period > 0
      job_class = job_class.set(wait: wait_period)
    end

    job_class.perform_later( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      subject: self,
      previous_body: try(:body_previous_change),
      deliver_notifications: ::GitHub.send_notifications?,
      spam_check_delay_served: spam_check_delay_served,
    )
  end
end
