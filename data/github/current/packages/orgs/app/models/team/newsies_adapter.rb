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
  # mentions and the fact that DiscussionPostReply#entity returns a Team.
  def private?
    true
  end

  # Required by SubscribableThread#subscribable_to_list? to check whether a given user
  # can subscribe to a list.
  #
  def public?
    !private?
  end

  # Newsies::Emails::Message assumes that a notification_list implements this method.
  #
  # For consistency with URLs (see #permalink), this uses a team's slug rather than its actual name.
  def name_with_owner
    combined_slug
  end

  # Newsies::Emails::Message assumes that a notification_list implements this method.
  #
  # For consistency with URLs (see #permalink), this uses a team's slug rather than its actual name.
  def name_with_display_owner
    combined_slug
  end

  # Newsies::Emails::Message assumes that a comment implements this method, so we define this in
  # order to allow a DiscussionPost (the 'comment' in the Newsies world) to use this to build its
  # own permalink.
  def permalink(include_host: true)
    "#{include_host ? GitHub.url : ""}/orgs/#{organization&.login}/teams/#{slug}"
  end
end
