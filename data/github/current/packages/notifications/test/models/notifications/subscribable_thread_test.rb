# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscribableThreadTest < GitHub::TestCase
  include GitHub::LoggerHelper

  PackagesMock = Struct.new(:packages)
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, from_example: :commit_user_mentions)
    @owner = @repo.owner
    @user = create :user, login: "defunkt"
    @committer = create :user, email: "simon@rozet.name"
    @visitor = create :user, login: "visitor"

    @team = create :team, organization: @org, privacy: :closed
    @team.add_member(@user)
    @child_team = create :team, organization: @org, privacy: :closed, parent_team_id: @team.id
    @child_team.add_member(@committer)
    @child_team.add_member(@visitor)


    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    @issue = build :issue, repository: @repo, user: @user
    @i_comment = build :issue_comment, repository: @repo, user: @user, issue: @issue, body: "@#{@org}/#{@team.slug}"

    @commit  = @repo.commits.find("1be5f4658c7c8cf0edada58fff0625a7bd242da1")

    @c_comment = build :commit_comment, user: @user, repository: @repo,
      position: 0, path: "empty_file", commit_id: @commit.to_s

    @pull = PullRequest.new repository: @repo, issue: @issue,
      head_sha: "1be5f4658c7c8cf0edada58fff0625a7bd242da1",
      base_sha: "b11d4cb9f1c0a389b15880f0661ffce7a22f4517"
    @p_thread = build :pull_request_review_thread, pull_request: @pull
    @p_comment = build :pull_request_review_comment, user: @user,
      pull_request: @pull, repository: @repo, pull_request_review_thread: @p_thread

    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    @mention = CommitMention.new(repository: @repo, commit_id: @commit.oid)
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackagesMock.new(packages: []))
  end

  context "Issue" do
    test "#notifications_list" do
      assert_equal @repo, @issue.notifications_list
    end

    test "#notifications_author" do
      assert_equal @user, @issue.notifications_author
    end

    test "#notifications_thread" do
      assert_equal @issue, @issue.notifications_thread
    end

    test "#subscribable_to_author?" do
      assert @issue.subscribable_to_author?(@committer)
    end

    test "#subscribable_to_author? if user blocks author" do
      @committer.block @user
      refute @issue.subscribable_to_author?(@committer)
    end

    test "#subscribable_to_author? if user blocks repository owner" do
      @committer.block @owner
      refute @issue.subscribable_to_author?(@committer)
    end

    test "#subscribable_to_author? if author blocks user" do
      @user.block @committer
      refute @issue.subscribable_to_author?(@committer)
    end

    test "#subscribable_to_author? if repository owner blocks user" do
      @owner.block @committer
      refute @issue.subscribable_to_author?(@committer)
    end

    test "#subscribable_by?" do
      assert @issue.subscribable_by?(@visitor)
    end
  end

  context "IssueComment" do
    test "#notifications_list" do
      assert_equal @repo, @i_comment.notifications_list
    end

    test "#notifications_author" do
      assert_equal @user, @i_comment.notifications_author
    end

    test "#notifications_thread" do
      assert_equal @issue, @i_comment.notifications_thread
    end

    test "#subscribable_by?" do
      assert @i_comment.subscribable_by?(@visitor)
    end
  end

  context "PullRequestReviewComment" do
    test "#notifications_list" do
      assert_equal @repo, @p_comment.notifications_list
    end

    test "#notifications_author" do
      assert_equal @user, @p_comment.notifications_author
    end

    test "#notifications_thread" do
      assert_equal @issue, @p_comment.notifications_thread
    end
  end

  context "CommitComment" do
    test "#notifications_list" do
      assert_equal @repo, @c_comment.notifications_list
    end

    test "#notifications_author" do
      assert_equal @user, @c_comment.notifications_author
    end

    test "#notifications_thread" do
      assert_equal @commit.to_s, @c_comment.notifications_thread.to_s
    end
  end

  context "CommitMention" do
    test "#notifications_list" do
      assert_equal @repo, @mention.notifications_list
    end

    test "#notifications_author" do
      assert_equal @committer, @mention.notifications_author
    end

    test "#notifications_thread" do
      assert_equal @commit.to_s, @mention.notifications_thread.to_s
    end

    test "#subscribe_mentioned" do
      @mention.save!
      assert @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if author is spammy", spammy_only: true do
      @committer.mark_as_spammy
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if author is nil" do
      @committer.destroy
      perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
        @mention.save!
      end
      assert @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if author is nil and user blocks owner" do
      @committer.destroy
      @user.block @owner
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if user blocks author" do
      @user.block @committer
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if user blocks repository owner" do
      @user.block @owner
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if author blocks user" do
      @committer.block @user
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned if repository owner blocks user" do
      @owner.block @user
      @mention.save!
      refute @mention.subscription_status(@user).valid?
    end

    test "#subscribable_to_author?" do
      assert @mention.subscribable_to_author?(@user)
    end

    test "#subscribable_to_author? if user blocks author" do
      @user.block @committer
      refute @mention.subscribable_to_author?(@user)
    end

    test "#subscribable_to_author? if user blocks repository owner" do
      @user.block @owner
      refute @mention.subscribable_to_author?(@user)
    end

    test "#subscribable_to_author? if author blocks user" do
      @committer.block @user
      refute @mention.subscribable_to_author?(@user)
    end

    test "#subscribable_to_author? if repository owner blocks user" do
      @owner.block @user
      refute @mention.subscribable_to_author?(@user)
    end

    test "#subscribable_to_author? logs are emitted when is false" do
      @owner.block @user
      other_users = [@mention.notifications_author, @mention.notifications_list.owner]

      expected_log = {
        "Body" => "user cannot subscribe to this author's threads",
        "code.namespace" => "Subscribable",
        "code.function" => "subscribable_to_author",
        "gh.user.id" => @user.id,
        "gh.user.login" => @user.login,
        "gh.notifications.avoided_users_ids" => other_users.map(&:id),
        "gh.notifications.avoided_users_logins" => other_users.map(&:login),
      }
      assert_logged(**expected_log) do
        @mention.subscribable_to_author?(@user)
      end
    end
  end

  context "#subscribe", skip_if_feature_enabled: :notifyd_issue_watch_activity_notify  do
    test "uses the thread to check if a user can be subscribed" do
      issue = create(:issue, repository: @repo, user: @user)
      comment = create(:issue_comment, repository: @repo, user: @user, issue: issue)
      issue.stubs(:subscribable_by?).returns(false)
      comment.stubs(:subscribable_by?).returns(true)

      comment.subscribe(@owner, :manual)

      refute issue.subscribed?(@owner)

      issue.stubs(:subscribable_by?).returns(true)
      comment.stubs(:subscribable_by?).returns(false)

      comment.subscribe(@owner, :manual)

      assert issue.subscribed?(@owner)
    end

    test "subscribes to issue with custom events", skip_if_feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      issue = create(:issue, repository: @repo, user: @owner)
      issue.stubs(:subscribable_by?).returns(true)

      issue.subscribe(@owner, :manual, %w[closed reopened])

      assert issue.subscribed?(@owner)
      assert_equal GitHub.newsies.subscription_status(@owner, @repo, issue).events.sort, %w[closed reopened].sort
    end
  end

  context "#subscribe_all", skip_if_feature_enabled: :notifyd_issue_watch_activity_notify do
    test "uses the thread to check if a user can be subscribed" do
      issue = create(:issue, repository: @repo, user: @user)
      comment = create(:issue_comment, repository: @repo, user: @user, issue: issue)
      issue.stubs(:subscribable_by?).returns(false)
      comment.stubs(:subscribable_by?).returns(true)

      comment.subscribe_all([@owner], :manual)

      refute issue.subscribed?(@owner)

      issue.stubs(:subscribable_by?).returns(true)
      comment.stubs(:subscribable_by?).returns(false)

      comment.subscribe_all([@owner], :manual)

      assert issue.subscribed?(@owner)
    end
  end

  context "#subscribable_team_members(team)" do
    test "return all subscribable members excluding users ignoring team and has the flag enabled" do
      enable_feature_flag(:ignorable_team_notifications)

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@committer, @team)
      end

      assert_predicate @team.subscription_status(@committer).value!, :ignored?

      collection = @issue.subscribable_team_members(@team)
      expected_collection = [@user, @visitor]

      assert_same_elements expected_collection, collection
    end

    test "return all descendant or self members" do
      disable_feature_flag(:ignorable_team_notifications)

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@committer, @team)
      end

      assert_predicate @team.subscription_status(@committer).value!, :ignored?

      collection = @issue.subscribable_team_members(@team)
      expected_collection = @team.descendant_or_self_members

      assert_same_elements expected_collection, collection
    end
  end
end
