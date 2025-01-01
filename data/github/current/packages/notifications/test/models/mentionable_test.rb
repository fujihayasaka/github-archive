# typed: true
# frozen_string_literal: true

require "test_helper"

class MentionableTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, from_example: :commit_user_mentions)
    @owner = @repo.owner
    @author = create(:user)
    @user = create :user, login: "defunkt"


    @issue = create :issue, repository: @repo, user: @author

    @org_repo = create(:repository, owner: @org, from_example: :simple)
    parent_team = create(:team, organization: @org, privacy: :closed)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
    @member = create(:user)
    @org.add_member(@member)
    @child_team_member = create(:user)
    @org.add_member(@child_team_member)
    @child_team.add_member(@child_team_member)
    @message_body = "hello world /cc @#{@org}/#{parent_team.slug}"

    @org_issue = create :issue, repository: @org_repo, user: @org.admins.first

  end

  setup do
    @mention = CommitMention.new(repository: @repo, commit_id: "1be5f4658c7c8cf0edada58fff0625a7bd242da1")
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
  end

  context "commit mentions" do
    test "subscribe mentioned users" do
      assert_performed_with job: SubscribeAndNotifyJob do
        only = [SubscribeAndNotifyJob]
        perform_enqueued_jobs(only: only) do
          @mention.save
        end
      end

      @mention.mentioned_users.each do |user|
        assert @mention.subscription_status(user).value.subscribed?
      end
    end
  end

  context "Issue" do
    test "#subscribe_mentioned" do
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert @issue.subscription_status(@user).value.subscribed?
    end

    test "#subscribe_mentioned when author is spammy", spammy_only: true do
      @author.mark_as_spammy
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).value.subscribed?
    end

    test "#subscribe_mentioned when owner is spammy", spammy_only: true do
      @owner.mark_as_spammy
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).value.subscribed?
    end

    test "#subscribe_mentioned when user blocks author" do
      @user.block @author
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned when user blocks owner" do
      @user.block @owner
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned when author blocks user" do
      @author.block @user
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).valid?
    end

    test "#subscribe_mentioned when owner blocks user" do
      @owner.block @user
      assert !@issue.subscription_status(@user).valid?

      @issue.subscribe_mentioned [@user]

      assert !@issue.subscription_status(@user).valid?
    end

    test "#update_subscribed_mentions delivers to new mentionees" do
      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create :issue_comment, issue: @issue, body: "new comment", user: @author

        GitHub.newsies.expects(:trigger)

        comment.body = "@defunkt"
        comment.save!
      end
    end

    test "#update_subscribed_mentions delivers to newly mentioned teams" do
      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create(:issue_comment, issue: @org_issue, body: "new comment", user: @member)

        updated_at = 3.minutes.from_now.change(usec: 0).utc

        GitHub.newsies.expects(:trigger).with(
          comment,
          recipient_ids: [@child_team_member.id],
          reason: "team-mentioned",
          event_time: updated_at,
          is_update: true,
        )

        comment.body = "@#{@org}/#{@child_team.slug}"
        Timecop.freeze(updated_at) { comment.save! }
      end
    end

    test "#update_subscribed_mentions does not deliver to new mentioned author" do
      assert_performed_with job: SubscribeAndNotifyJob do
        comment = create :issue_comment, issue: @issue, body: "new comment", user: @author

        GitHub.newsies.expects(:trigger).never

        comment.body = "@#{@author.login}"
        comment.save!
      end
    end

    test "#update_subscribed_mentions does not deliver to author if mentioned via a team" do
      assert_performed_with job: SubscribeAndNotifyJob do
        team = create(:team, organization: @org, privacy: :closed)
        team.add_member(@member)
        comment = create(:issue_comment, issue: @org_issue, body: "new comment", user: @member)

        GitHub.newsies.expects(:trigger).never

        comment.body = "@#{@org}/#{team.slug}"
        comment.save!
      end
    end
  end

  context "descendant team mentions" do
    test "issue mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create :issue, repository: @org_repo, user: @member, body: @message_body
        assert issue.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "issue comment mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create :issue, repository: @org_repo, user: @member
        create :issue_comment, issue: issue, user: @member, body: @message_body

        assert issue.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "Pull Request mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create :issue, repository: @org_repo, user: @member, body: @message_body
        create :pull_request, repository: @org_repo, head_ref: "cr-line-endings", user: @member, issue: issue

        assert issue.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "Pull request review mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create :issue, repository: @org_repo, user: @member
        pr = create :pull_request, repository: @org_repo, head_ref: "cr-line-endings", user: @member, issue: issue
        prv = create :pull_request_review, user: @member, pull_request: pr, repository: @org_repo, body: @message_body
        prv.comment!

        assert issue.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "Pull request review comment mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = create :issue, repository: @org_repo, user: @member
        pr = create :pull_request, repository: @org_repo, head_ref: "cr-line-endings", user: @member, issue: issue
        review = create(:pull_request_review, pull_request: pr, user: @member)
        create :pull_request_review_comment, user: @member, pull_request: pr, pull_request_review: review, repository: @org_repo, body: @message_body
        assert review.comment!

        assert issue.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "Commit comment mentions includes descendant team members when nested teams is enabled" do
      assert_performed_with job: SubscribeAndNotifyJob do
        commit_comment = create :commit_comment, user: @member, repository: @org_repo, position: 0, body: @message_body, commit_id: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
        assert commit_comment.subscribed?(@child_team_member), "expected mention to include descendant team members"
      end
    end

    test "#update_subscribed_mentions delivers to descendant team members when parent team is newly mentioned" do
      assert_performed_with job: SubscribeAndNotifyJob do
        org_issue = create :issue, repository: @org_repo, user: @member
        comment = create(:issue_comment, issue: org_issue, body: "new comment", user: @member)

        updated_at = 3.minutes.from_now.change(usec: 0).utc

        GitHub.newsies.expects(:trigger).with(
          comment,
          recipient_ids: [@child_team_member.id],
          reason: "team-mentioned",
          event_time: updated_at,
          is_update: true,
        )

        comment.body = @message_body
        Timecop.freeze(updated_at) { comment.save! }
      end
    end
  end
end
