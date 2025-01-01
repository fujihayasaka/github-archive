# typed: false
# frozen_string_literal: true

# This module implements methods expected for Newsies::List (often without clear interface specification)
module User::NewsiesAdapter
  include Notifications::SubscribableList

  # SubscribableThread#subscribable_to_author? assumes this exists.
  def owner
    self
  end

  def async_owner
    Promise.resolve(owner)
  end

  # Required by SubscribableThread#subscribable_to_list? to check whether a given user
  # can subscribe to a list.
  #
  def public?
    true
  end

  # GitHub::Goomba::MentionFilter#public? assumes this exists
  def private?
    !public?
  end

  # Newsies::Emails::Message#list_id assumes that a notification list defines `name_with_owner`
  def name_with_owner
    login
  end

  # Newsies::Emails::Message#list_id assumes that a notification list defines `name_with_display_owner`
  def name_with_display_owner
    display_login
  end
end
