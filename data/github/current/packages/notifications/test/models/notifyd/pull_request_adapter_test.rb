# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydPullRequestAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @repo = create(:repository)
      @user = create(:user)
      @mentioned_user = create(:user)
      @repo.add_member(@user)
      @repo.add_member(@mentioned_user)
    end

    setup do
      example_repo(:simple, @repo)
      @pr = PullRequest.create_for!(@repo,
        user: @user,
        base: "master",
        head: "cr-line-endings",
        title: "A title",
        body: "Hi @#{@mentioned_user}"
      )
    end

    test "matches for pull requests" do
      assert adapter(@pr).matches?
    end

    test "does not match if repository is missing" do
      @pr.repository.destroy
      @pr.reload

      refute adapter(@pr).matches?
    end

    test "does not match if repository owner is missing" do
      @pr.repository.owner.delete
      @pr.reload

      refute adapter(@pr).matches?
    end

    test "does return notification_id for pull_requests" do
      assert_equal adapter(@pr).notification_id,
        "/#{@pr.repository.name_with_owner}/pull/#{@pr.number}"
    end

    test "repository_id" do
      assert_equal adapter(@pr).repository_id, @pr.repository_id
    end

    test "owner_id" do
      refute_nil adapter(@pr).owner_id
      assert_equal adapter(@pr).owner_id, @pr.repository.owner.id
    end

    test "owner_id is nil when owner is missing" do
      @pr.repository.owner.delete
      @pr.reload

      assert_nil adapter(@pr).owner_id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        org.add_member(@user, action: :admin)
        repo = create(:repository, owner: org, from_example: :simple)
        pr = PullRequest.create_for!(repo,
          user: @user,
          base: "master",
          head: "cr-line-endings",
          title: "A title",
          body: "Hi @#{@mentioned_user}"
        )

        assert_equal adapter(pr).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@pr).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@pr).authzd_attributes, @pr.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@pr).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        org.add_member(@user, action: :admin)
        repo = create(:repository, owner: org, from_example: :simple)
        pr = PullRequest.create_for!(repo,
          user: @user,
          base: "master",
          head: "cr-line-endings",
          title: "A title",
          body: "Hi @#{@mentioned_user}"
        )
        assert_equal adapter(pr).saml_enforcement, { organization_id: org.id }
      end
    end

    context "mobile_layout" do
      test "without an actor" do
        assert_nil adapter(
          @pr,
          actor_login: "test_login",
          actor_id: 0,
          operation: Operations::PullRequestOperation::Update.serialize
        ).mobile_layout
      end

      test "with an actor" do
        refute_nil adapter(@pr, { actor_id: @user.id }).mobile_layout
      end
    end


    test "email_layout" do
      assert_nil adapter(@pr, { actor_id: @user.id }).email_layout
    end

    test "actor" do
      user = create(:user)
      %w(create update assigned review_requested).each do |operation|
        actor = adapter(@pr, { actor_id: user.id, operation: operation }).actor

        assert_equal user, actor
      end
    end

    test "related topics" do
      %w(create update assigned review_requested).each do |operation|
        expected_related_topics = [
          { type: "repository", value: @pr.repository.id.to_s },
          { type: "pull_request", value: @pr.id.to_s },
          { type: "issue", value: @pr.issue.id.to_s },
        ]
        assert_equal adapter(@pr, { operation: operation }).related_topics, expected_related_topics
      end
    end

    test "attributes" do
      %w(create update assigned review_requested).each do |operation|
        expected_attributes = [
          { name: "thread_participant_activity", value: "true" },
          { name: "thread_type", value: "pull_request" },
          { name: "watch_activity", value: "true" },
        ]
        assert_equal adapter(@pr, { operation: operation }).attributes, expected_attributes
      end
    end

    context "explicit_recipients" do
      test "for create action" do
        assert_equal adapter(@pr, { current_body: @pr.issue.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user] }]
      end

      test "for create action and multiple recipients" do
        another_user = create(:user)
        @pr.issue.body = "@#{@mentioned_user.login} yeah? and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@pr, { current_body: @pr.issue.body, operation: "create" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned_user, another_user] }]
      end

      test "for update action with no previous body" do
        @pr.issue.body = ""
        assert_same_explicit_recipients adapter(@pr, { current_body: @pr.issue.body, operation: "update" }).explicit_recipients, []
      end

      test "for update action" do
        another_user = create(:user)
        previous_body = @pr.body
        @pr.issue.body += " and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@pr, { previous_body: previous_body, current_body: @pr.issue.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [another_user] }]
      end

      test "for update action for new recipients" do
        user = create(:user)
        another_user = create(:user)
        previous_body = @pr.body
        @pr.issue.body = "now @#{user.login} and @#{another_user.login}"

        assert_same_explicit_recipients adapter(@pr, { previous_body: previous_body, current_body: @pr.issue.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [user, another_user] }]
      end

      test "for update and no user mention" do
        previous_body = @pr.body
        @pr.issue.body = "no user mention"

        assert_same_explicit_recipients adapter(@pr, { previous_body: previous_body, current_body: @pr.issue.body, operation: "update" }).explicit_recipients, []
      end

      test "for unknown action" do
        assert_same_explicit_recipients adapter(@issue, { operation: "unknown" }).explicit_recipients, []
      end
    end

    test "feature switches" do
      %w(create update assigned review_requested).each do |operation|
        assert_equal adapter(@pr, { operation: operation }).feature_switches, { notify_subscribers: false }
      end
    end

    private

    def adapter(pr, context = {})
      Notifyd::PullRequestAdapter.new(pr, context)
    end
  end
end
