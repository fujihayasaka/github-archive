# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionNotificationsTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @public_discussion = create(:discussion, repository: @public_repo)

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

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)
  end

  context "#unsubscribable_users" do
    test "returns users who can be unsubscribed because they have not commented in the thread" do
      comment = create(:discussion_comment, discussion: @public_discussion)
      rando = create(:verified_user)
      users = [comment.user, @public_discussion.user, rando]

      result = @public_discussion.unsubscribable_users(users)

      assert_equal [rando], result
    end
  end

  test "subscribes the correct users to a public discussion" do
    rando = create(:verified_user)
    author = create(:verified_user)

    rando.watch_repo(@public_repo)
    @repo_owner.watch_repo(@public_repo)

    assert_performed_with(job: SubscribeAndNotifyJob) do
      discussion = create(:discussion, repository: @public_repo, user: author)

      assert discussion.subscribed?(author),
        "author should be subscribed to post in Newsies after posting."
      assert_equal "author", discussion.subscription_status(author).reason

      refute discussion.subscribed?(@repo_owner),
        "repo admin should not be subscribed to post in Newsies after posting."

      refute discussion.subscribed?(rando),
        "rando should not be subscribed to post in Newsies after posting."
    end
  end

  test "spammer creating a discussion does not generate notifications" do
    rando = create(:verified_user)
    spammy_author = create(:spammy_user, :verified)

    enable_notifications_for_user(@repo_owner)
    enable_notifications_for_user(rando)
    enable_notifications_for_user(spammy_author)

    @repo_owner.watch_repo(@public_repo)
    rando.watch_repo(@public_repo)

    only = [AddToSearchIndexJob, Newsies::DeliverNotificationsJob, Newsies::UpdateNotificationsSpamStatusJob, NotifySubscriptionStatusChangeJob, SubscribeAndNotifyJob]
    discussion = perform_enqueued_jobs(only: only) do
      create(:discussion, repository: @public_repo, user: spammy_author)
    end

    refute_delivered_any_notifications(@repo_owner)
    refute_delivered_any_notifications(spammy_author)
    refute_delivered_any_notifications(rando)
  end if GitHub.spamminess_check_enabled?

  test "correct users receive a web notification when a public discussion is created" do
    rando = create(:verified_user)
    author = create(:verified_user)

    enable_notifications_for_user(@repo_owner)
    enable_notifications_for_user(rando)
    enable_notifications_for_user(author)

    @repo_owner.watch_repo(@public_repo)
    rando.watch_repo(@public_repo)

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    discussion = perform_enqueued_jobs(only: only) do
      create(:discussion, repository: @public_repo, user: author)
    end

    assert_delivered_web_notification(@repo_owner, discussion, "list")
    assert_delivered_email_notification(@repo_owner, discussion, "list")

    refute_delivered_any_notifications(author)

    assert_delivered_web_notification(rando, discussion, "list")
    assert_delivered_email_notification(rando, discussion, "list")
  end

  context "#async_viewer_can_delete?" do
    test "false for non-admin author of discussion" do
      refute @public_discussion.async_viewer_can_delete?(@public_discussion.user).sync
    end

    test "true for repo owner" do
      assert @public_discussion.async_viewer_can_delete?(@repo_owner).sync
    end

    test "true for repo admin" do
      assert @org_discussion.async_viewer_can_delete?(@repo_admin).sync
    end

    test "true for repo triager" do
      assert @org_discussion.async_viewer_can_delete?(@repo_triager).sync
    end

    test "true for repo maintainer" do
      assert @org_discussion.async_viewer_can_delete?(@repo_maintainer).sync
    end

    test "true for user with repo write access" do
      assert @org_discussion.async_viewer_can_delete?(@repo_writer).sync
    end

    test "false for user who can only read discussion" do
      rando = create(:verified_user)
      refute @public_discussion.async_viewer_can_delete?(rando).sync
    end
  end

  context "#async_path_uri" do
    test "returns relative URL path to discussion" do
      uri = @public_discussion.async_path_uri.sync
      assert_equal "/#{@public_repo.name_with_display_owner}/discussions/#{@public_discussion.number}", uri.to_s
    end

    test "returns relative URL to path discussion for org discussion" do
      create(:organization_discussion_config, organization: @org, repository: @org_repo)
      uri = @org_discussion.async_path_uri.sync
      assert_equal "/orgs/#{@org}/discussions/#{@org_discussion.number}", uri.to_s
    end

    test "does not use org discussion link if repo is not org level discussions repo" do
      create(:organization_discussion_config, organization: @org, repository: @org_repo)
      other_org_repo = create(:repository, organization: @org, has_discussions: true)
      other_org_discussion = create(:discussion, repository: other_org_repo)
      expected_url = "/#{other_org_repo.name_with_display_owner}/discussions/#{other_org_discussion.number}"
      assert_equal expected_url, other_org_discussion.async_path_uri.sync.to_s
    end
  end

  context "#permalink" do
    test "returns URL to discussion" do
      expected_url = "https://github.com/#{@public_repo.name_with_display_owner}/discussions/#{@public_discussion.number}"
      assert_equal expected_url, @public_discussion.permalink
    end

    test "returns URL to path discussion for org discussion" do
      create(:organization_discussion_config, organization: @org, repository: @org_repo)
      expected_url = "https://github.com/orgs/#{@org}/discussions/#{@org_discussion.number}"
      assert_equal expected_url, @org_discussion.permalink
    end

    test "returns URL to path discussion for org private discussion" do
      create(:organization_discussion_config, organization: @org, repository: @org_private_repo)
      expected_url = "https://github.com/orgs/#{@org}/discussions/#{@org_private_discussion.number}"
      assert_equal expected_url, @org_private_discussion.permalink
    end

    test "does not use org discussion link if repo is not org level discussions repo" do
      create(:organization_discussion_config, organization: @org, repository: @org_repo)
      other_org_repo = create(:repository, organization: @org, has_discussions: true)
      other_org_discussion = create(:discussion, repository: other_org_repo)
      expected_url = "https://github.com/#{other_org_repo.name_with_display_owner}/discussions/#{other_org_discussion.number}"
      assert_equal expected_url, other_org_discussion.permalink
    end
  end

  context "#deliver_notifications?" do
    test "false when the discussion's repository has been disabled for discussion notifications" do
      enable_feature_flag(:disable_discussions_notifications, @public_discussion.repository)

      refute_predicate @public_discussion, :deliver_notifications?
    end

    test "true when the feature is globally enabled but not specifically for this repository" do
      enable_feature_flag(:disable_discussions_notifications)

      assert_predicate @public_discussion, :deliver_notifications?
    end

    test "false when discussion is being converted from an issue" do
      discussion = create(:discussion, state: :converting, issue: create(:issue))
      refute_predicate discussion, :deliver_notifications?
    end

    test "false when discussion is in an error state" do
      discussion = create(:discussion, state: :error, error_reason: :close_failure)
      refute_predicate discussion, :deliver_notifications?
    end

    test "can deliver notifications" do
      assert_predicate @public_discussion, :deliver_notifications?
    end

    test "delivers notifications for closed discussion" do
      @public_discussion.close(actor: @repo_owner)
      assert_predicate @public_discussion, :deliver_notifications?
    end

    test "false when discussion is converted from a team discussion" do
      discussion = create(:discussion, state: :converting, team_post_id: create(:discussion_post).id)
      refute_predicate discussion, :deliver_notifications?
    end
  end
end
