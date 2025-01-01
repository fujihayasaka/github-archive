# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentNotificationsTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @repo_owner = create(:verified_user)
    @repo = create(:repository, owner: @repo_owner, has_discussions: true)

    @org = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @org, has_discussions: true)
    @org_private_repo = create(:private_repository, owner: @org, has_discussions: true)

    @repo_triager = create(:verified_user)
    @org_repo.add_member(@repo_triager, action: :triage)

    @repo_maintainer = create(:verified_user)
    @org_repo.add_member(@repo_maintainer, action: :maintain)

    @repo_writer = create(:verified_user)
    @org_repo.add_member(@repo_writer, action: :write)

    @repo_admin = create(:verified_user)
    @org_repo.add_member(@repo_admin, action: :admin)

    @unanswered_discussion = create(:discussion, repository: @repo)
    @comment = create(:discussion_comment, repository: @repo, discussion: @unanswered_discussion)

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_comment = create(:discussion_comment, repository: @org_repo,
      discussion: @org_discussion)

    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_private_comment = create(:discussion_comment, repository: @org_private_repo,
      discussion: @org_private_discussion)
  end

  context "#unsubscribable_users" do
    test "returns users who can be unsubscribed because they have not commented in the thread" do
      rando = create(:verified_user)
      users = [@comment.user, @unanswered_discussion.user, rando]

      result = @comment.unsubscribable_users(users)

      assert_equal [rando], result
    end
  end

  test "subscribes the correct users to the parent discussion" do
    user = create(:verified_user)
    rando = create(:verified_user)
    discussion = T.let(nil, T.nilable(Discussion))

    assert_performed_with(job: SubscribeAndNotifyJob) do
      discussion = create(:discussion, repository: @repo)

      assert discussion.subscribed?(discussion.user),
        "discussion creator should be subscribed to the post in Newsies."
      assert_equal "author", discussion.subscription_status(discussion.user).reason
    end

    rando.watch_repo(@repo)

    assert_performed_with(job: SubscribeAndNotifyJob) do
      create(:discussion_comment, user: user, discussion: discussion)

      discussion = T.must(discussion)
      assert discussion.subscribed?(user),
        "the posting user should be subscribed to post in Newsies."
      assert_equal "comment", discussion.subscription_status(user).reason

      refute discussion.subscribed?(rando),
        "rando should not be subscribed to the post in Newsies."
    end
  end

  test "correct users receive a web notification when the comment is created" do
    rando = create(:verified_user)
    discussion_author = create(:verified_user)
    comment_author = create(:verified_user)

    enable_notifications_for_user(@repo_owner)
    enable_notifications_for_user(rando)
    enable_notifications_for_user(discussion_author)

    @repo_owner.watch_repo(@repo)
    rando.watch_repo(@repo)

    only = [SubscribeAndNotifyJob]
    discussion = perform_enqueued_jobs(only: only) do
      create(:discussion, repository: @repo, user: discussion_author)
    end
    Newsies::NotificationEntry.destroy_all
    ActionMailer::Base.deliveries.clear

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    comment = perform_enqueued_jobs(only: only) do
      create(:discussion_comment, user: comment_author, discussion: discussion)
    end

    assert_delivered_web_notification(@repo_owner, comment, "list")
    assert_delivered_email_notification(@repo_owner, comment, "list")

    assert_delivered_web_notification(discussion_author, comment, "author")
    assert_delivered_email_notification(discussion_author, comment, "author")

    assert_delivered_web_notification(rando, comment, "list")
    assert_delivered_email_notification(rando, comment, "list")

    refute_delivered_any_notifications(comment_author)
  end

  test "spammer creating a discussion comment does not generate notifications" do
    rando = create(:verified_user)
    discussion_author = create(:verified_user)
    spammy_author = create(:spammy_user, :verified)

    enable_notifications_for_user(@repo_owner)
    enable_notifications_for_user(rando)
    enable_notifications_for_user(discussion_author)

    @repo_owner.watch_repo(@repo)
    rando.watch_repo(@repo)

    only = [AddToSearchIndexJob, Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob, SubscribeAndNotifyJob]
    discussion = perform_enqueued_jobs(only: only) do
      create(:discussion, repository: @repo, user: discussion_author)
    end
    Newsies::NotificationEntry.destroy_all
    ActionMailer::Base.deliveries.clear

    only = [AddToSearchIndexJob, Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob, SubscribeAndNotifyJob]
    comment = perform_enqueued_jobs(only: only) do
      create(:discussion_comment, user: spammy_author, discussion: discussion)
    end

    refute_delivered_any_notifications(@repo_owner)
    refute_delivered_any_notifications(discussion_author)
    refute_delivered_any_notifications(rando)
    refute_delivered_any_notifications(spammy_author)
  end if GitHub.spamminess_check_enabled?

  context "#permalink" do
    test "returns URL to comment" do
      assert_equal "https://github.com/#{@repo.name_with_display_owner}/discussions/" \
        "#{@unanswered_discussion.number}#discussioncomment-#{@comment.id}", @comment.permalink
    end

    test "returns URL to comment for org discussion" do
      create(:organization_discussion_config, organization: @org, repository: @org_repo)
      assert_equal "https://github.com/orgs/#{@org}/discussions/" \
        "#{@org_discussion.number}#discussioncomment-#{@org_comment.id}", @org_comment.permalink
    end
  end

  context "#deliver_notifications?" do
    test "false when the discussion's repository has been disabled for discussion notifications" do
      enable_feature_flag(:disable_discussions_notifications, @comment.repository)

      refute_predicate @comment, :deliver_notifications?
    end

    test "true when the feature is globally enabled but not specifically for this repository" do
      enable_feature_flag(:disable_discussions_notifications)

      assert_predicate @comment, :deliver_notifications?
    end

    test "true if discussion does not have a converted_at timestamp" do
      @comment.discussion.update!(converted_at: nil)

      assert_predicate @comment, :deliver_notifications?
    end

    test "false if the discussion is actively being converted from an issue" do
      @comment.discussion.update!(issue: create(:issue), state: :converting)

      refute_predicate @comment, :deliver_notifications?
    end

    test "false if comment was updated before discussion was converted" do
      @comment.discussion.update!(converted_at: @comment.updated_at + 1.minute)

      refute_predicate @comment, :deliver_notifications?
    end

    test "true if comment was updated after discussion was converted" do
      @comment.discussion.update!(converted_at: @comment.updated_at - 1.minute)

      assert_predicate @comment, :deliver_notifications?
    end

    test "false if comment was updated before discussion was converted from team discussion" do
      @comment.discussion.update!(team_post_id: create(:discussion_post).id,
        converted_at: @comment.updated_at + 1.minute)

      refute_predicate @comment, :deliver_notifications?
    end

    test "true if comment was updated after discussion was converted from team discussion" do
      @comment.discussion.update!(team_post_id: create(:discussion_post).id,
        converted_at: @comment.updated_at - 1.minute)

      assert_predicate @comment, :deliver_notifications?
    end


    test "delivers notifications for closed discussion" do
      @comment.discussion.close(actor: @repo_owner)
      assert_predicate @comment.discussion, :deliver_notifications?
    end

    test "false when discussion is converted from a team discussion" do
      @comment.discussion.update!(team_post_id: create(:discussion_post).id, state: :converting)

      refute_predicate @comment, :deliver_notifications?
    end
  end

  context "#async_viewer_can_delete?" do
    test "true for author of comment" do
      assert @comment.async_viewer_can_delete?(@comment.user).sync
    end

    test "true for repo owner" do
      assert @comment.async_viewer_can_delete?(@comment.repository.owner).sync
    end

    test "true for repo admin" do
      assert @org_comment.async_viewer_can_delete?(@repo_admin).sync
    end

    test "true for repo triager" do
      assert @org_comment.async_viewer_can_delete?(@repo_triager).sync
    end

    test "true for repo maintainer" do
      assert @org_comment.async_viewer_can_delete?(@repo_maintainer).sync
    end

    test "true for user with repo write access" do
      assert @org_comment.async_viewer_can_delete?(@repo_writer).sync
    end

    test "false for user with only read access to the comment" do
      rando = create(:verified_user)

      refute @comment.async_viewer_can_delete?(rando).sync
    end
  end
end
