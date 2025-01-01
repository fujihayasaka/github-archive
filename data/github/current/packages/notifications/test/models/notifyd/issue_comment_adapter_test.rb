# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class IssueCommentAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @mentioned_user = create(:user)
      @issue_comment = create(:issue_comment, body: "@#{@mentioned_user} yeah?")
      @pull_request = create(:pull_request, :disable_disk_access)
      @pull_request_comment = create(:issue_comment, issue: @pull_request.issue)
    end

    context "issue comments" do
      test "matches" do
        assert adapter(@issue_comment).matches?
      end

      test "does return notification_id for issue comments" do
        repository_name = @issue_comment.repository.name_with_owner

        assert_equal adapter(@issue_comment).notification_id,
          "/#{repository_name}/issues/#{@issue_comment.issue.number}#issuecomment-#{@issue_comment.id}"
      end

      test "related_topics" do
        label_one = create(:label, repository: @issue_comment.repository)
        label_two = create(:label, repository: @issue_comment.repository)
        @issue_comment.issue.add_labels([label_one, label_two])

        related_topics = adapter(@issue_comment).related_topics

        assert_equal related_topics.size, 4
        assert_equal related_topics.first, { type: "repository", value: @issue_comment.repository.id.to_s }
        assert_equal related_topics.second, { type: "issue", value: @issue_comment.issue.id.to_s }
        assert_equal related_topics.third, { type: "label", value: label_one.id.to_s }
        assert_equal related_topics.last, { type: "label", value: label_two.id.to_s }
      end

      test "attributes" do
        label_one = create(:label, repository: @issue_comment.repository)
        label_two = create(:label, repository: @issue_comment.repository)
        @issue_comment.issue.add_labels([label_one, label_two])

        attributes = adapter(@issue_comment).attributes

        assert_equal attributes.size, 5
        assert_equal attributes[0], { name: "thread_participant_activity", value: "true" }
        assert_equal attributes[1], { name: "watch_activity", value: "true" }
        assert_equal attributes[2], { name: "thread_type", value: "issue" }
        assert_equal attributes[3], { name: "has_label", value: label_one.id.to_s }
        assert_equal attributes[4], { name: "has_label", value: label_two.id.to_s }
      end

      test "mobile_layout" do
        refute_nil adapter(@issue_comment, { actor_id: @issue_comment.user.id }).mobile_layout
      end

      test "email_layout" do
        refute_nil adapter(@issue_comment, { actor_id: @issue_comment.user.id }).email_layout
      end
    end

    context "pull request comments" do
      test "matches" do
        assert adapter(@pull_request_comment).matches?
      end

      test "does return notification_id" do
        repository_name = @pull_request_comment.repository.name_with_owner

        assert_equal adapter(@pull_request_comment).notification_id,
          "/#{repository_name}/pull/#{@pull_request_comment.issue.pull_request.number}#issuecomment-#{@pull_request_comment.id}"
      end

      test "related_topics" do
        label_one = create(:label, repository: @pull_request_comment.repository)
        label_two = create(:label, repository: @pull_request_comment.repository)
        @pull_request_comment.issue.add_labels([label_one, label_two])

        related_topics = adapter(@pull_request_comment).related_topics

        assert_equal related_topics.size, 5
        assert_equal related_topics[0], { type: "repository", value: @pull_request_comment.repository.id.to_s }
        assert_equal related_topics[1], { type: "issue", value: @pull_request_comment.issue.id.to_s }
        assert_equal related_topics[2], { type: "pull_request", value: @pull_request_comment.issue.pull_request.id.to_s }
        assert_equal related_topics[3], { type: "label", value: label_one.id.to_s }
        assert_equal related_topics[4], { type: "label", value: label_two.id.to_s }
      end

      test "attributes" do
        label_one = create(:label, repository: @pull_request_comment.repository)
        label_two = create(:label, repository: @pull_request_comment.repository)
        @pull_request_comment.issue.add_labels([label_one, label_two])

        attributes = adapter(@pull_request_comment).attributes

        assert_equal attributes.size, 5
        assert_equal attributes[0], { name: "thread_participant_activity", value: "true" }
        assert_equal attributes[1], { name: "watch_activity", value: "true" }
        assert_equal attributes[2], { name: "thread_type", value: "pull_request" }
        assert_equal attributes[3], { name: "has_label", value: label_one.id.to_s }
        assert_equal attributes[4], { name: "has_label", value: label_two.id.to_s }
      end

      test "mobile_layout" do
        refute_nil adapter(@pull_request_comment, { actor_id: @pull_request_comment.user.id }).mobile_layout
      end

      test "email_layout" do
        assert_nil adapter(@pull_request_comment, { actor_id: @pull_request_comment.user.id }).email_layout
      end
    end

    test "does not match if the issue is missing" do
      @issue_comment.issue.delete
      @issue_comment.reload

      refute adapter(@issue_comment).matches?
    end

    test "does not match if repository is missing" do
      @issue_comment.issue.repository.delete
      @issue_comment.reload
      refute adapter(@issue_comment).matches?
    end

    test "does return notify feature flag value" do
      assert_equal GitHub.flipper[:notifyd_issue_comment_notify], adapter(@issue_comment).notify_feature_flag
    end

    test "repository_id" do
      assert_equal adapter(@issue_comment).repository_id, @issue_comment.repository_id
    end

    test "owner_id" do
      refute_nil adapter(@issue_comment).owner_id
      assert_equal adapter(@issue_comment).owner_id, @issue_comment.repository.owner.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        issue_comment = create(:issue_comment, repository: repo)
        assert_equal adapter(issue_comment).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@issue_comment).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@issue_comment).authzd_attributes, @issue_comment.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@issue_comment).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        issue_comment = create(:issue_comment, repository: repo)
        assert_equal adapter(issue_comment).saml_enforcement, { organization_id: org.id }
      end
    end

    context "explicit_recipients" do
      test "for create action" do
        assert_same_explicit_recipients adapter(@issue_comment, { current_body: @issue_comment.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }]
      end

      test "for create action and multiple recipients" do
        another_user = create(:user)
        @issue_comment.body = "@#{@mentioned_user.login} yeah? and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue_comment, { current_body: @issue_comment.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @issue_comment.body
        @issue_comment.body += " and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue_comment, { previous_body: previous_body, current_body: @issue_comment.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [another_user] }]
      end

      test "for update action for new recipients" do
        user = create(:user)
        another_user = create(:user)
        previous_body = @issue_comment.body
        @issue_comment.body = "now @#{user.login} and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@issue_comment, { previous_body: previous_body, current_body: @issue_comment.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update and no user mention" do
        previous_body = @issue_comment.body
        @issue_comment.body = "no user mention"

        assert_same_explicit_recipients adapter(@issue_comment, { previous_body: previous_body, current_body: @issue_comment.body, operation: "update" }).explicit_recipients, []
      end

      test "for unknown action" do
        assert_same_explicit_recipients adapter(@issue_comment, { operation: "unknown" }).explicit_recipients, []
      end
    end

    context "feature switches" do
      test "disable subscribers for update opeations" do
        assert_equal adapter(@issue_comment, { current_body: @issue_comment.body, operation: "update" }).feature_switches, {
          notify_subscribers: false
        }
      end

      test "return default otherwise" do
        assert_equal adapter(@issue_comment, { current_body: @issue_comment.body, operation: "create" }).feature_switches, {}
      end
    end

    private

    def adapter(issue_comment, context = {})
      Notifyd::IssueCommentAdapter.new(issue_comment, context)
    end
  end
end
