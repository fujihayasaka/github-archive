# typed: false
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module GistComment::NewsiesAdapter

  # Implementation of SubscribableThread interface
  def async_notifications_list
    async_gist.then(&:async_notifications_list)
  end

  def notifications_thread
    gist
  end

  def notifications_author
    user
  end

  def author_subscribe_reason
    "comment"
  end

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns a Newsies::Response instance .
  def get_notification_summary
    list = Newsies::List.to_object(notifications_list)
    thread = Newsies::List.to_object(notifications_thread)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end

  # Overrides NotificationsContent#unsubscribable_users
  def unsubscribable_users(users)
    commenter_ids = Set.new(
      self.class.where(gist_id: gist_id).distinct.pluck(:user_id),
    )
    users.reject { |user| commenter_ids.include?(user.id) }
  end

  # Newsies::Emails::Message assumes this exists.
  def message_id
    "<#{gist.name_with_title}/comments/#{id}@#{GitHub.urls.host_name}>"
  end

  # Newsies::Emails::Message assumes this exists.
  def entity
    async_entity.sync
  end

  # Returns the entity (user) required by GitHub::UserContent which seems to be
  # used when rendering email notifications.
  def async_entity
    async_gist.then(&:async_entity)
  end

  # Newsies::Emails::Message#url assumes this exists.
  def permalink
    "#{gist.permalink}##{anchor}"
  end
end
