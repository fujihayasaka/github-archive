# typed: true
# frozen_string_literal: true

# This module implements methods expected (often without clear interface specification) by Newsies.
module Team::NewsiesAdapter
  extend T::Helpers
  requires_ancestor { Team }
  # A temporary measure to prevent `@epicgames/developers` from being notified
  # See https://github.com/github/platform-health-incidents/issues/486
  EPICGAMES_DEVELOPER_TEAM_ID = 699229

  # Newsies::Service#deliver_from_author? assumes this exists.
  def owner
    organization
  end

  # Required by Goomba's async mention filter due to some strange interaction between emails and
  # mentions.
  def private?
    true
  end

  # For consistency with URLs (see #permalink), this uses a team's slug rather than its actual name.
  def name_with_owner
    combined_slug
  end

  # For consistency with URLs (see #permalink), this uses a team's slug rather than its actual name.
  def name_with_display_owner
    combined_slug
  end

  # Required by Platform::Interfaces::Subscribable to resolve viewerSubscription
  # and viewerCanUnsubscribe fields on the Team GraphQL type.
  def subscription_status(user)
    async_subscription_status(user).sync
  end

  def async_subscription_status(user)
    Promise.resolve(Notifications::Subscriptions.list_subscription_status(user, self))
  end

  def async_notifications_list
    Promise.resolve(self)
  end
end
