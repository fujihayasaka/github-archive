# typed: true
# frozen_string_literal: true

module NotificationsContent
  extend T::Helpers
  include GitHub::UserContent
  include Notifications::Mentionable
  include Notifications::SubscribableThread
  include Notifications::Summarizable

  requires_ancestor { ActiveRecord::Base }

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
      SubscribeAndNotifyJob.perform_later(
        self,
        load_mentioned_users: true,
        load_mentioned_teams: true,
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

    UpdateSubscriptionsAndNotifyJob.perform_later(
      subject: self,
      previous_body: try(:body_previous_change),
      deliver_notifications: ::GitHub.send_notifications?,
    )
  end
end
