# typed: false
# frozen_string_literal: true

# Records @mentions happening in commit messages. This is used to notify
# mentionees by email and Message notifications.
class CommitMention < ApplicationRecord::Domain::IssuesPullRequests
  include NotificationsContent::WithCallbacks
  include GitHub::Relay::GlobalIdentification

  belongs_to :repository
  destroy_in_background_with :repository
  alias_method :entity, :repository
  alias_method :async_entity, :async_repository

  validates_length_of :mentioned_users, maximum: 10
  validates_uniqueness_of :commit_id, case_sensitive: false

  after_commit :subscribe_and_notify,            on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_subscriptions_and_notify, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # The mentioning commit on the repository.
  #
  # Returns a Commit.
  def commit
    @commit ||= repository.commits.find(commit_id)
  end

  # The user sending the @mention.
  #
  # Returns a User.
  def user
    @user ||= commit.author
  end

  def user_id
    user ? user.id : nil
  end

  # Public: Processes the mentions for a commit.  Don't bother if the commit
  # has already been processed.  Also triggers notifications.
  #
  # repo   - A Repository.
  # commit - A Commit.
  #
  # Returns nothing.
  def self.process(repo, commit)
    return if commit.author.nil?
    return if commit.mentioned_users.empty?
    create(repository: repo, commit_id: commit.oid)
  end

  # Public: Determine whether the given Commit has been processed. Useful
  # to avoid storing the same commit twice for different repos or branch. Also
  # enforced at the MySQL level with an unique index:
  #
  #   add_index "commit_mentions", ["commit_id", "repository_id"],
  #     :unique => true
  #
  # Returns a Boolean.
  def self.processed?(commit)
    !find_by_commit_id(commit.oid).nil?
  end

  # Users mentioned in this @mention.
  #
  # Returns an Array of @mentioned Users.
  def mentioned_users
    commit.mentioned_users
  end

  # Returns an Array of @mentioned teams.
  def mentioned_teams
    commit.mentioned_teams
  end

  # Internal: Override Mentionable#subscribe_mentioned so that we subscribe
  # the author of the commit mention with the correct reason, in addition to
  # the list of mentioned users.
  #
  # mentions - Array of users that were mentioned. This defaults to users
  #            mentioned in the commit body.
  # author   - Author of the commit mention.  Defaults to #user.
  #
  # Returns nothing.
  def subscribe_mentioned(mentions = mentioned_users, author = user)
    subscribable_user_mentions(mentions, author) do |mentionee, author|
      if mentionee == author
        subscribe(mentionee, :author)
      else
        subscribe(mentionee, :mention)
      end
    end
  end

  # Used by the email reply system. See EmailReplyJob.
  def email_reply_creation_method
    :reply_to_commit_mention
  end

  def repo_id
    repository.id
  end

  def repo_name
    repository.name
  end

  def short_id
    commit.abbreviated_oid
  end

  def short_message
    commit.short_message
  end

  # Checks if the CommitMention is available.  CommitMentions need a valid
  # Repository and Commit.
  #
  # Returns true if it is, or false.
  def available?
    !!(repository && commit)
  end

  # Returns an Array of Users that are not part of users mentioned
  def unsubscribable_users(users)
    users.reject { |user| mentioned_users.include?(user.id) }
  end

  # Overrides Summarizable#deliver_notifications because by default that method
  # does not distinguish between authors mentioned users.
  #
  # This implementation does not handle delivery of notifications to mentioned
  # teams.
  def deliver_notifications
    direct_mention_user_ids ||= mentioned_users.map(&:id)
    direct_mention_user_ids.delete(user_id) # this commit's author

    GitHub.newsies.trigger(
      self,
      recipient_ids: direct_mention_user_ids,
      event_time: created_at,
    )
  end

  # Public: Gets the NotificationSummary for this Mention's thread.
  # See Summarizable.
  #
  # Returns a Newsies::Response instance .
  def get_notification_summary
    list = Newsies::List.new("Repository", repository_id)
    thread = Newsies::Thread.new("Grit::Commit", commit_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end

  def notifications_author
    user
  end

  def async_notifications_list
    async_repository
  end

  def notifications_thread
    commit
  end
end
