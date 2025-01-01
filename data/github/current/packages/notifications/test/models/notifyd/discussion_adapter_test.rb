# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class DiscussionAdapterTest < GitHub::TestCase
    fixtures do
      @mentioned_user = create(:user)
      @discussion = create(:discussion, body: "@#{@mentioned_user} yeah?")
    end

    test "matches for discussions" do
      assert adapter(@discussion).matches?
    end

    test "does not match if repository is missing" do
      @discussion.repository.destroy
      @discussion.reload
      refute adapter(@discussion).matches?
    end

    test "does return notification_id for discussions" do
      assert_equal adapter(@discussion).notification_id,
        "/#{@discussion.repository.name_with_owner}/discussions/#{@discussion.number}"
    end

    test "repository_id" do
      assert_equal adapter(@discussion).repository_id, @discussion.repository_id
    end

    test "returns related_topics" do
      label_one = create(:label, repository: @discussion.repository)
      label_two = create(:label, repository: @discussion.repository)
      @discussion.add_labels([label_one, label_two])

      expected_topics = [
        { type: "repository", value: @discussion.repository.id.to_s },
        { type: "discussion", value: @discussion.id.to_s },
      ]
      assert_equal adapter(@discussion).related_topics, expected_topics
    end

    test "owner_id" do
      refute_nil adapter(@discussion).owner_id
      assert_equal adapter(@discussion).owner_id, @discussion.repository.owner.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        category = create(:discussion_category, repository: repo)
        discussion = create(:discussion, category: category, repository: repo)
        assert_equal adapter(discussion).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@discussion).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@discussion).authzd_attributes, @discussion.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@discussion).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        category = create(:discussion_category, repository: repo)
        discussion = create(:discussion, category: category, repository: repo)
        assert_equal adapter(discussion).saml_enforcement, { organization_id: org.id }
      end
    end

    test "mobile_layout" do
      refute_nil adapter(@discussion, { actor_id: @discussion.user.id }).mobile_layout
    end

    test "email_layout" do
      assert_nil adapter(@discussion, { actor_login: "test_login" }).email_layout
    end

    test "trigger" do
      assert_equal adapter(@discussion, { operation: "create" }).trigger, "create"
    end

    context "explicit_recipients" do
      test "for create action" do
        assert_equal adapter(@discussion, { current_body: @discussion.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }]
      end

      test "for create action and multiple recipients" do
        another_user = create(:user)
        @discussion.body = "@#{@mentioned_user.login} yeah? and @#{another_user.login}"

        assert_equal adapter(@discussion, { current_body: @discussion.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @discussion.body
        @discussion.body += " and @#{another_user.login}"

        assert_equal adapter(@discussion, { previous_body: previous_body, current_body: @discussion.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [another_user] }]
      end

      test "for update action for new recipients" do
        user = create(:user)
        another_user = create(:user)
        previous_body = @discussion.body
        @discussion.body = "now @#{user.login} and @#{another_user.login}"

        assert_equal adapter(@discussion, { previous_body: previous_body, current_body: @discussion.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update and no user mention" do
        previous_body = @discussion.body
        @discussion.body = "no user mention"

        assert_equal adapter(@discussion, { previous_body: previous_body, current_body: @discussion.body, operation: "update" }).explicit_recipients, []
      end

      test "for unknown action" do
        assert_equal adapter(@discussion, { operation: "unknown" }).explicit_recipients, []
      end
    end

    private

    def adapter(discussion, context = {})
      DiscussionAdapter.new(discussion, context)
    end
  end
end
