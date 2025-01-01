# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsCommitMentionsTest < GitHub::TestCase
  include Notifications::TestHelper

  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @reader = create :user, login: "mentionee" # matches commit message
    @author = create :user, login: "author", email: "technoweenie@gmail.com"
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo", from_example: :notification_mentions
    @team.add_repository(@list, :push)
    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create :user, login: "user" # matches commit message
  end

  # CommitMentions only deliver to mentioned users.  Normally we don't send
  # notifications for every commit.
  test "shared: list-subscribed user" do
    disable_user_settings @reader
    user_settings @owner, :subscribed
    user_settings @visitor, :subscribed
    subscribe_to_list @owner, @reader, @visitor
    assert_subscribed_to_list @owner, @reader, @visitor

    comment = trigger_notifications
    refute comment.new_record?

    assert_delivered_to @owner
    assert_subscribed_to comment, @owner => :mention, @reader => :mention
    assert_subscribed_to_list @owner, @reader
  end

  test "shared: spammy author" do
    return if GitHub.enterprise? # no spammers in enterprise!
    @author.mark_as_spammy
    assert @author.spammy?
    user_settings @owner, :subscribed
    user_settings @reader, :subscribed
    user_settings @visitor, :subscribed
    subscribe_to_list @owner, @reader, @visitor
    assert_subscribed_to_list @owner, @reader, @visitor

    comment = trigger_notifications
    refute comment.new_record?

    assert_none_delivered
    assert_none_subscribed_to comment
    assert_subscribed_to_list @owner, @reader
  end

  test "shared: author blocks subscriber" do
    # Prevent BackfillCommitContributionSummariesJob from performing now and causing
    # transaction issues.
    GitHub.flipper[:commit_contribution_summaries].disable
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable

    @author.block @reader
    user_settings @owner, :subscribed
    user_settings @reader, :subscribed
    user_settings @visitor, :subscribed
    subscribe_to_list @owner, @reader, @visitor
    assert_subscribed_to_list @owner, @reader, @visitor

    comment = trigger_notifications
    refute comment.new_record?

    assert_delivered_to @owner

    assert_subscribed_to comment, @owner => :mention
    assert_subscribed_to_list @owner, @reader
  end

  test "shared: subscriber blocks author" do
    # Prevent BackfillCommitContributionSummariesJob from performing now and causing
    # transaction issues.
    GitHub.flipper[:commit_contribution_summaries].disable
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable

    @reader.block @author
    user_settings @owner, :subscribed
    user_settings @reader, :subscribed
    user_settings @visitor, :subscribed
    subscribe_to_list @owner, @reader, @visitor
    assert_subscribed_to_list @owner, @reader, @visitor

    comment = trigger_notifications
    refute comment.new_record?

    assert_delivered_to @owner
    assert_subscribed_to comment, @owner => :mention
    assert_subscribed_to_list @owner, @reader
  end

  def trigger_notifications(options = {})
    CommitMention.create! options.reverse_merge(
      repository: @list,
      commit_id: "a62c6b20ff594b18f95e585a65b07698a36af76d")
  end

  def default_subscribed
    {}
  end
end
