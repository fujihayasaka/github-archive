# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydIssueAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @user = create(:user)
      @mentioned_user = create(:user)
      @issue = create(:issue, user: @user, body: "@#{@mentioned_user} yeah?")
    end

    test "matches for issues" do
      assert adapter(@issue).matches?
    end

    test "does not match if repository is missing" do
      issue = create(:issue)
      issue.repository.destroy
      issue.reload

      refute adapter(issue).matches?
    end

    test "does not match if repository owner is missing" do
      issue = create(:issue)
      issue.repository.owner.delete
      issue.reload

      refute adapter(issue).matches?
    end

    test "does return notify feature flag value" do
      assert_equal GitHub.flipper[:notifyd_issue_notify], adapter(@issue).notify_feature_flag
    end

    test "does return notification_id for issues" do
      assert_equal adapter(@issue).notification_id,
        "/#{@issue.repository.name_with_owner}/issues/#{@issue.number}"
    end

    test "repository_id" do
      assert_equal adapter(@issue).repository_id, @issue.repository_id
    end

    test "owner_id" do
      refute_nil adapter(@issue).owner_id
      assert_equal adapter(@issue).owner_id, @issue.repository.owner.id
    end

    test "owner_id is nil when owner is missing" do
      issue = create(:issue)
      issue.repository.owner.delete
      issue.reload

      assert_nil adapter(issue).owner_id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        issue = create(:issue, repository: repo)
        assert_equal adapter(issue).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@issue).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@issue).authzd_attributes, @issue.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@issue).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        issue = create(:issue, repository: repo)
        assert_equal adapter(issue).saml_enforcement, { organization_id: org.id }
      end
    end

    context "mobile_layout" do
      test "without an actor" do
        assert_nil adapter(
          @issue,
          actor_login: "test_login",
          actor_id: 0,
          operation: Operations::IssueOperation::Update.serialize
        ).mobile_layout
      end

      test "with an actor" do
        refute_nil adapter(@issue, { actor_login: "test_login" }).mobile_layout
      end
    end

    test "email_layout" do
      refute_nil adapter(@issue, { actor_login: "test_login" }).email_layout
    end

    context "actor" do
      test "when the operation is create" do
        user = create(:user)
        actor = adapter(@issue, { actor_id: user.id, operation: "create" }).actor

        assert_equal @issue.user, actor
      end

      test "when the operation is update" do
        user = create(:user)
        actor = adapter(@issue, { actor_id: user.id, operation: "update" }).actor
        assert_equal user, actor
      end
    end

    context "related_topics" do
      test "returns related_topics for create operations when" do
        label_one = create(:label, repository: @issue.repository)
        label_two = create(:label, repository: @issue.repository)
        @issue.add_labels([label_one, label_two])
        expected_related_topics = [
          { type: "repository", value: @issue.repository.id.to_s },
          { type: "issue", value: @issue.id.to_s },
          { type: "label", value: label_one.id.to_s },
          { type: "label", value: label_two.id.to_s },
        ]
        assert_equal adapter(@issue, { operation: "create" }).related_topics, expected_related_topics
      end

      test "returns related_topics for update operations" do
        label_one = create(:label, repository: @issue.repository)
        label_two = create(:label, repository: @issue.repository)
        @issue.add_labels([label_one, label_two])
        expected_related_topics = [
          { type: "repository", value: @issue.repository.id.to_s },
          { type: "issue", value: @issue.id.to_s },
          { type: "label", value: label_one.id.to_s },
          { type: "label", value: label_two.id.to_s },
        ]
        assert_equal adapter(@issue, { operation: "update" }).related_topics, expected_related_topics
      end
    end

    context "attributes" do
      test "returns attributes for create operations when" do
        label_one = create(:label, repository: @issue.repository)
        label_two = create(:label, repository: @issue.repository)
        @issue.add_labels([label_one, label_two])
        expected_attributes = [
          { name: "thread_participant_activity", value: "true" },
          { name: "thread_type", value: "issue" },
          { name: "has_label", value: label_one.id.to_s },
          { name: "has_label", value: label_two.id.to_s },
          { name: "watch_activity", value: "true" },
        ]
        assert_equal adapter(@issue, { operation: "create" }).attributes, expected_attributes
      end
    end

    context "explicit_recipients" do
      test "for create action" do
        assert_same_explicit_recipients adapter(@issue, { current_body: @issue.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }, { reason: "author", users: [@user] }]
      end

      test "for create action and multiple recipients" do
        another_user = create(:user)
        @issue.body = "@#{@mentioned_user.login} yeah? and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue, { current_body: @issue.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user, another_user] }, { reason: "author", users: [@user] }]
      end

      test "for create action with assignees" do
        repo = create(:repository)
        owner = repo.owner
        assignee1 = create(:user)
        assignee2 = create(:user)
        repo.add_member(assignee1)
        repo.add_member(assignee2)
        issue_with_assignees = create(:issue, user: owner, repository: repo, assignees: [assignee1, assignee2])

        assert_same_explicit_recipients adapter(issue_with_assignees, { current_body: issue_with_assignees.body, operation: "create" }).explicit_recipients,
          [{ reason: "author", users: [owner] }, { reason: "assign", users: [assignee1, assignee2] }]
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @issue.body
        @issue.body += " and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue, { previous_body: previous_body, current_body: @issue.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [another_user] }]
      end

      test "for update action for new recipients" do
        user = create(:user)
        another_user = create(:user)
        previous_body = @issue.body
        @issue.body = "now @#{user.login} and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue, { previous_body: previous_body, current_body: @issue.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [user, another_user] }]
      end

      test "for update and no user mention" do
        previous_body = @issue.body
        @issue.body = "no user mention"

        assert_same_explicit_recipients adapter(@issue, { previous_body: previous_body, current_body: @issue.body, operation: "update" }).explicit_recipients, []
      end

      test "for unknown action" do
        assert_same_explicit_recipients adapter(@issue, { operation: "unknown" }).explicit_recipients, []
      end
    end

    context "feature switches" do
      test "disable subscribers for update operations" do
        assert_equal adapter(@issue, { operation: "update" }).feature_switches, {
          notify_subscribers: false
        }
      end

      test "return default otherwise" do
        assert_equal adapter(@issue, { operation: "create" }).feature_switches, {}
      end
    end

    private

    def adapter(issue, context = {})
      Notifyd::IssueAdapter.new(issue, context)
    end
  end
end
