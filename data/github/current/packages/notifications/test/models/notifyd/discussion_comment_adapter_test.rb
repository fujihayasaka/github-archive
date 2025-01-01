# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class DiscussionCommentAdapterTest < GitHub::TestCase
    fixtures do
      @mentioned_user = create(:user)
      @discussion_comment = create(:discussion_comment, body: "@#{@mentioned_user} yeah?")
    end

    test "matches for discussion comments" do
      assert adapter(@discussion_comment).matches?
    end

    test "does not match if discussion is missing" do
      @discussion_comment.discussion.delete
      @discussion_comment.reload

      refute adapter(@discussion_comment).matches?
    end

    test "does not match if repository is missing" do
      @discussion_comment.discussion.repository.destroy
      @discussion_comment.reload
      refute adapter(@discussion_comment).matches?
    end

    test "does return always enabled feature flag value" do
      assert_equal Notifyd::SubjectAdapter::FeatureEnabled.new, adapter(@discussion_comment).notify_feature_flag
    end

    test "does return notification_id for discussion comments" do
      repository_name = @discussion_comment.repository.name_with_owner

      assert_equal adapter(@discussion_comment).notification_id,
        "/#{repository_name}/discussions/#{@discussion_comment.number}#discussioncomment-#{@discussion_comment.id}"
    end

    test "repository_id" do
      assert_equal adapter(@discussion_comment).repository_id, @discussion_comment.repository_id
    end

    test "owner_id" do
      refute_nil adapter(@discussion_comment).owner_id
      assert_equal adapter(@discussion_comment).owner_id, @discussion_comment.repository.owner.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        category = create(:discussion_category, repository: repo)
        discussion = create(:discussion, category: category, repository: repo)
        discussion_comment = create(:discussion_comment, discussion: discussion)
        assert_equal adapter(discussion_comment).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@discussion_comment).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@discussion_comment).authzd_attributes,
        @discussion_comment.discussion.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@discussion_comment).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        category = create(:discussion_category, repository: repo)
        discussion = create(:discussion, category: category, repository: repo)
        discussion_comment = create(:discussion_comment, discussion: discussion)

        assert_equal adapter(discussion_comment).saml_enforcement, { organization_id: org.id }
      end
    end

    test "mobile_layout" do
      refute_nil adapter(@discussion_comment, { actor_id: @discussion_comment.user.id }).mobile_layout
    end

    test "email_layout" do
      assert_nil adapter(@discussion_comment, { actor_login: "test_login" }).email_layout
    end

    test "trigger" do
      assert_equal adapter(@discussion_comment, { operation: "create" }).trigger, "create"
    end

    test "returns related_topics" do
      label_one = create(:label, repository: @discussion_comment.repository)
      label_two = create(:label, repository: @discussion_comment.repository)
      @discussion_comment.discussion.add_labels([label_one, label_two])

      expected_topics = [
        { type: "repository", value: @discussion_comment.repository.id.to_s },
        { type: "discussion_comment", value: @discussion_comment.id.to_s },
      ]
      assert_equal adapter(@discussion_comment).related_topics, expected_topics
    end

    context "explicit_recipients" do
      test "for create action" do
        context = { current_body: @discussion_comment.body, operation: "create" }
        assert_equal adapter(@discussion_comment, context).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }]
      end

      test "for create action and multiple recipients" do
        another_user = create(:user)
        @discussion_comment.body = "@#{@mentioned_user.login} yeah? and @#{another_user.login}"

        context = { current_body: @discussion_comment.body, operation: "create" }
        assert_equal adapter(@discussion_comment, context).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @discussion_comment.body
        @discussion_comment.body += " and @#{another_user.login}"

        context = {
          previous_body: previous_body,
          current_body: @discussion_comment.body,
          operation: "update",
        }
        assert_equal adapter(@discussion_comment, context).explicit_recipients,
          [{ reason: "mention", users: [another_user] }]
      end

      test "for update action for new recipients" do
        user = create(:user)
        another_user = create(:user)
        previous_body = @discussion_comment.body
        @discussion_comment.body = "now @#{user.login} and @#{another_user.login}"

        context = {
          previous_body: previous_body,
          current_body: @discussion_comment.body,
          operation: "update",
        }
        assert_equal adapter(@discussion_comment, context).explicit_recipients,
          [{ reason: "mention", users: [user] }, { reason: "mention", users: [another_user] }]
      end

      test "for update and no user mention" do
        previous_body = @discussion_comment.body
        @discussion_comment.body = "no user mention"

        context = {
          previous_body: previous_body,
          current_body: @discussion_comment.body,
          operation: "update",
        }
        assert_equal adapter(@discussion_comment, context).explicit_recipients, []
      end

      test "for unknown action" do
        assert_equal adapter(@discussion_comment, { operation: "unknown" }).explicit_recipients, []
      end
    end

    private

    def adapter(discussion_comment, context = {})
      Notifyd::DiscussionCommentAdapter.new(discussion_comment, context)
    end
  end
end
