# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class RecipientsHelperTest < GitHub::TestCase
    include GitHub::LoggerHelper

    fixtures do
      @mentioned_user = create(:user)
      @user = create(:user)
      @gist = create(:gist, user: @user)
      @comment_author = create(:user)
      @gist_comment = create(:gist_comment, body: "Hi!", gist: @gist, user: @mentioned_user)
      @gist_comment = create(:gist_comment, body: "@#{@mentioned_user.login} yeah?", gist: @gist, user: @comment_author)

      @owner = create(:verified_user)
      @org = create(:organization, admin: @owner)
      @team = create(:public_team, organization: @org)
      @member = create(:verified_user)
      @org.add_member(@member)
      @team.add_member(@owner)
      @repo = create(:repository, owner: @org)
      @issue = create(:issue, repository: @repo, user: @owner)
    end

    test "explicit recipients for create" do
      helper = RecipientsHelper.new(@gist_comment, "create", nil, @gist_comment.body)
      recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

      assert recipients.length == 3
      assert_equal recipients[0], { reason: "author", users: [User.new(id: @user.id)] }
      assert_equal recipients[1], { reason: "comment", users: [User.new(id: @comment_author.id)] }
      assert_equal recipients[2], { reason: "mention", users: [User.new(id: @mentioned_user.id)] }
    end

    test "explicit recipients for update" do
      helper = RecipientsHelper.new(@gist_comment, "update", "test", @gist_comment.body)
      recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

      assert recipients.length == 1
      assert_equal recipients[0], { reason: "mention", users: [User.new(id: @mentioned_user.id)] }
    end

    context "team mentions" do
      test "includes user from mentioned team when an issue is created" do
        @issue.body = "Hi @#{@team.combined_slug}"
        helper = RecipientsHelper.new(@issue, "create", nil, @issue.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        assert_equal 2, recipients.length
        assert_equal recipients[0], { reason: "author", users: [User.new(id: @owner.id)] }
        assert_equal recipients[1], { reason: "team_mention", users: [User.new(id: @owner.id)] }
      end

      test "includes user from mentioned team when an issue is updated" do
        @issue.body = "Hi @#{@team.combined_slug}"
        helper = RecipientsHelper.new(@issue, "update", "", @issue.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        assert_equal 1, recipients.length
        assert_equal recipients[0], { reason: "team_mention", users: [User.new(id: @owner.id)] }
      end

      test "includes user from mentioned team when an issue comment is created" do
        issue_comment = create(:issue_comment, repository: @repo, user: @owner, issue: @issue, body: "Hi @#{@team.combined_slug}")
        helper = RecipientsHelper.new(issue_comment, "create", nil, issue_comment.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        assert_equal 3, recipients.length
        assert_equal recipients[0], { reason: "author", users: [User.new(id: @owner.id)] }
        assert_equal recipients[1], { reason: "comment", users: [User.new(id: @owner.id)] }
        assert_equal recipients[2], { reason: "team_mention", users: [User.new(id: @owner.id)] }
      end

      test "includes user from mentioned team when an issue comment is updated" do
        issue_comment = create(:issue_comment, repository: @repo, user: @owner, issue: @issue, body: "Hi @#{@team.combined_slug}")
        helper = RecipientsHelper.new(issue_comment, "update", "", issue_comment.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        assert_equal 1, recipients.length
        assert_equal recipients[0], { reason: "team_mention", users: [User.new(id: @owner.id)] }
      end

      test "does include user of team with notifications enabled" do
        team = create(:public_team, organization: @org, notification_setting: Team::NOTIFICATIONS_ENABLED)
        team.add_member(@owner)
        @issue.body = "Hi @#{team.combined_slug}"

        assert_logged(
        "Body": "RecipientsHelper: this team is notified because it has notifications enabled",
        "code.function": "remove_mentioned_teams_with_disabled_notifications",
        "gh.organization": team.organization.display_login,
        "gh.team.name": team.name,
        "gh.team.notification_setting": team.notification_setting) do
          helper = RecipientsHelper.new(@issue, "create", nil, @issue.body)
          recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }
          assert_equal 2, recipients.length
          assert_equal recipients[0], { reason: "author", users: [User.new(id: @owner.id)] }
          assert_equal recipients[1], { reason: "team_mention", users: [User.new(id: @owner.id)] }
        end
      end

      test "does not include user of team with notifications disabled" do
        team = create(:public_team, organization: @org, notification_setting: Team::NOTIFICATIONS_DISABLED)
        team.add_member(@owner)
        @issue.body = "Hi @#{team.combined_slug}"
        helper = RecipientsHelper.new(@issue, "create", nil, @issue.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        refute_logged(
        "Body": "RecipientsHelper: this team is notified because it has notifications enabled",
        "code.function": "remove_mentioned_teams_with_disabled_notifications",
        "gh.organization": team.organization.display_login,
        "gh.team.name": team.name,
        "gh.team.notification_setting": team.notification_setting) do
          helper = RecipientsHelper.new(@issue, "create", nil, @issue.body)
          recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }
          assert_equal 1, recipients.length
          assert_equal recipients[0], { reason: "author", users: [User.new(id: @owner.id)] }
        end
      end

      test "both mention and team mention reasons are included when applicable" do
        @issue.body = "Hi @#{@owner.login} from @#{@team.combined_slug}"
        helper = RecipientsHelper.new(@issue, "create", nil, @issue.body)
        recipients = helper.explicit_recipients.sort_by { |recipient| recipient[:reason] }

        assert_equal 3, recipients.length
        assert_equal recipients[0], { reason: "author", users: [User.new(id: @owner.id)] }
        assert_equal recipients[1], { reason: "mention", users: [User.new(id: @owner.id)] }
        assert_equal recipients[2], { reason: "team_mention", users: [User.new(id: @owner.id)] }
      end
    end

    context "memex_project_statuses" do
      test "returns MemexProject owner as author" do
        memex_project = create(:memex_project, owner: @org, creator: @owner)
        memex_project_status = create(:memex_project_status, creator: @member, memex_project: memex_project)
        helper = RecipientsHelper.new(memex_project_status, "create", nil, memex_project_status.body)
        expected_explicit_recipients = [
          {
            reason: "author",
            users: [@owner],
          },
          {
            reason: "state_change",
            users: [@member],
          }
        ]

        assert_equal expected_explicit_recipients, helper.explicit_recipients
      end

      test "returns status update authors as state_change subscribable reason for thread" do
        other_member = create(:verified_user)
        @org.add_member(other_member)
        memex_project = create(:memex_project, owner: @org, creator: @owner)
        memex_project_status = create(:memex_project_status, creator: @member, memex_project: memex_project)
        other_memex_project_status = create(:memex_project_status, creator: other_member, memex_project: memex_project)
        helper = RecipientsHelper.new(memex_project_status, "create", nil, memex_project_status.body)
        expected_explicit_recipients = [
          {
            reason: "author",
            users: [@owner],
          },
          {
            reason: "state_change",
            users: [@member, other_member],
          }
        ]

        assert_equal expected_explicit_recipients, helper.explicit_recipients
      end
    end
  end
end
