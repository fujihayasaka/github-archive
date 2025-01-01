# typed: false
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module Gist::NewsiesAdapter
  include Notifications::SubscribableThread

  # Implementation of SubscribableThread interface
  def async_notifications_list
    async_user.then do |user|
      user || User.ghost
    end
  end

  def notifications_thread
    self
  end

  def notifications_author
    notifications_list
  end

  # Overrides SubscribableThread#subscribable_by
  def subscribable_by?(user, author = nil)
    super(user, author)
  end

  # Newsies::Emails::Message assumes this exists.
  def message_id
    "<#{name_with_title}@#{GitHub.urls.host_name}>"
  end

  # Newsies::Emails::Message assumes this exists.
  def entity
    async_entity.sync
  end

  # Returns the entity (user) required by GitHub::UserContent which seems to be
  # used when rendering email notifications.
  def async_entity
    async_notifications_list
  end
end
