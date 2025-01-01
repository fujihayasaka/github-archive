# typed: true
# frozen_string_literal: true

# A database table to track users and their interactions with .com. Primary
# use case is tracking and querying basic engagement metrics. Will most likely
# be usurped by more sophisticated analytics in the future.
#
# Some metrics have been tracked for different time periods:
#
# 2013-05-31 active sessions
# 2013-05-31 web edits
# 2013-05-31 pull requests
# 2013-05-31 issues
# 2013-05-31 comments
# 2013-05-31 pushes
# 2013-06-03 wiki edits
# 2013-07-03 releases
#
class Interaction < ApplicationRecord::Domain::Users
  def self.enabled?
    GitHub.enterprise?
  end

  belongs_to :user

  before_save :ensure_interaction_tracking_enabled

  # An active session is a day that the person has visited the site while
  # logged in. Excludes people who have visited the same day they signed up.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_active_session(user)
    interaction = for_user(user)
    return if interaction.last_active_session_at && interaction.last_active_session_at > 1.day.ago
    return if user.created_at > 1.day.ago

    now = Time.now
    interaction.last_active_session_at = now
    interaction.active_sessions += 1
    store_interaction(interaction, now)
  end

  # A web edit is using the web UI to create a branch, tag, or do a file
  # create, edit, delete operation.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_web_edit(user)
    interaction = for_user(user)

    now = Time.now
    interaction.web_edits += 1
    interaction.last_web_edit_at = now
    store_interaction(interaction, now)
  end

  # Submitting a new pull request.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_pull_request(user)
    interaction = for_user(user)

    now = Time.now
    interaction.pull_requests += 1
    interaction.last_pull_request_at = now
    store_interaction(interaction, now)
  end

  # Submitting a new issue.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_issue(user)
    interaction = for_user(user)

    now = Time.now
    interaction.issues += 1
    interaction.last_issue_at = now
    store_interaction(interaction, now)
  end

  # Commenting on an a Commit, an Issue, a Pull Request, and Pull Request
  # Review Comments.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_comment(user)
    interaction = for_user(user)

    now = Time.now
    interaction.comments += 1
    interaction.last_comment_at = now
    store_interaction(interaction, now)
  end

  # Creating, editing, and deleting a wiki page.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_wiki_edit(user)
    interaction = for_user(user)

    now = Time.now
    interaction.wiki_edits += 1
    interaction.last_wiki_edit_at = now
    store_interaction(interaction, now)
  end

  # Git Pushes.
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_push(user)
    interaction = for_user(user)

    now = Time.now
    interaction.pushes += 1
    interaction.last_pushed_at = now
    store_interaction(interaction, now)
  end

  # Creating a new Release
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_release(user)
    now = Time.now
    interaction = for_user(user)
    interaction.releases += 1
    interaction.last_released_at = now
    store_interaction(interaction, now)
  end

  # Using the Mac app
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_mac(user)
    interaction = for_user(user)
    return if interaction.last_mac_active_session && interaction.last_mac_active_session > 1.day.ago

    now = Time.now
    interaction.mac_active_sessions += 1
    interaction.last_mac_active_session = now
    store_interaction(interaction, now)
  end

  # Using the Windows app
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_windows(user)
    interaction = for_user(user)
    return if interaction.last_windows_active_session && interaction.last_windows_active_session > 1.day.ago

    now = Time.now
    interaction.windows_active_sessions += 1
    interaction.last_windows_active_session = now
    store_interaction(interaction, now)
  end

  # Using the Desktop app on Mac
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_desktop_mac(user)
    interaction = for_user(user)
    return if interaction.last_mac_desktop_active_session_at && interaction.last_mac_desktop_active_session_at > 1.day.ago

    interaction.mac_desktop_active_sessions ||= 0
    interaction.mac_desktop_active_sessions += 1

    now = Time.now
    interaction.last_mac_desktop_active_session_at = now
    store_interaction(interaction, now)
  end

  # Using the Desktop app on Windows
  #
  # user - The User to record this activity on.
  #
  # Returns true for success.
  def self.track_desktop_windows(user)
    interaction = for_user(user)
    return if interaction.last_windows_desktop_active_session_at && interaction.last_windows_desktop_active_session_at > 1.day.ago

    interaction.windows_desktop_active_sessions ||= 0
    interaction.windows_desktop_active_sessions += 1

    now = Time.now
    interaction.last_windows_desktop_active_session_at = now
    store_interaction(interaction, now)
  end

  # Find or create an Interaction record for a given user.
  #
  # user - The User you'd like the interaction for.
  #
  # Returns the associated Interaction.
  def self.for_user(user)
    return Interaction.new unless user

    # Fake it out to stop queries if interaction tracking is disabled.
    return Interaction.new unless enabled?

    return user.interaction if user.interaction.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      user.interaction = Interaction.create(user: user)
    end
  end

  # Ensures the last_active timestamp is updated.
  def tap_last_active(activity_timestamp = Time.now)
    self.last_active_at = activity_timestamp
  end

  def been_with_any_content?
    content_areas = [web_edits, pull_requests, issues, comments, pushes, wiki_edits, releases, mac_active_sessions, windows_active_sessions, mac_desktop_active_sessions, windows_desktop_active_sessions]
    content_areas.any? { |count| count && count > 0 }
  end

  private

  def ensure_interaction_tracking_enabled
    self.class.enabled?
  end

  def self.store_interaction(interaction, activity_timestamp = Time.now)
    return unless enabled?
    interaction.tap_last_active(activity_timestamp)
    ActiveRecord::Base.connected_to(role: :writing) { interaction.save }
  end
  private_class_method :store_interaction
end
