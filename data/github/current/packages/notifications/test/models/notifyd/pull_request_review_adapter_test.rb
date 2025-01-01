# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class PullRequestReviewAdapterTest < GitHub::TestCase
    setup do
      @owner = create(:user, login: "owner")
      @author = create(:user, login: "author")
      @reviewer = create(:user, login: "reviewer")
      @mentioned = create(:user)
      @repo = create(:repository, owner: @owner, name: "repo")
      @pull_request = create(:pull_request, :disable_disk_access, user: @author, repository: @repo)
      @review = create(:pull_request_review, pull_request: @pull_request, user: @reviewer)
    end

    test "matches if the review state is approved" do
      @review.approve!
      assert adapter(@review).matches?
    end

    test "matches if the review state is commented" do
      @review.comment!
      assert adapter(@review).matches?
    end

    test "matches if the review state is changes requested" do
      @review.request_changes!
      assert adapter(@review).matches?
    end

    test "does not match if the review state is pending" do
      refute adapter(@review).matches?
    end

    test "does not match if the review state is dismissed" do
      @review.approve!
      @review.dismiss!(@reviewer, message: "No longer relevant")
      refute adapter(@review).matches?
    end

    test "does not match if repository is missing" do
      @review.repository.delete
      @review.reload
      refute adapter(@review).matches?
    end

    test "does not match if pull request is missing" do
      @review.pull_request.delete
      @review.reload
      refute adapter(@review).matches?
    end

    test "does not match if pull request user is missing" do
      @review.pull_request.user.delete
      @review.reload
      refute adapter(@review).matches?
    end

    test "does not match if reviewer is missing" do
      @review.user.delete
      @review.reload
      refute adapter(@review).matches?
    end

    test "does return notify feature flag value" do
      assert_equal GitHub.flipper[:notifyd_pull_request_review_notify], adapter(@review).notify_feature_flag
    end

    test "does return notification_id for reviews" do
      assert_equal adapter(@review).notification_id,
        "/#{@review.repository.name_with_owner}/pull/#{@pull_request.number}#pullrequestreview-#{@review.id}"
    end

    test "repository_id" do
      assert_equal adapter(@review).repository_id, @review.repository_id
    end

    test "owner_id" do
      refute_nil adapter(@review).owner_id
      assert_equal adapter(@review).owner_id, @review.repository.owner.id
    end

    context "owner type" do
      test "for an organization is :organization" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        author = create(:user)
        reviewer = create(:user)
        pull_request = create(:pull_request, :disable_disk_access, user: author, repository: repo)
        review = create(:pull_request_review, pull_request: pull_request, user: reviewer)
        assert_equal adapter(review).owner_type, :organization
      end

      test "for a user is :user" do
        assert_equal adapter(@review).owner_type, :user
      end
    end

    test "authzd_attributes" do
      assert_equal adapter(@review).authzd_attributes, @pull_request.permissions_wrapper.serialized_subject_attributes
    end

    context "saml_enforcement" do
      test "for user without org" do
        assert_equal adapter(@review).saml_enforcement, { skip_enforcement: true }
      end

      test "for user with org" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        author = create(:user)
        reviewer = create(:user)
        pull_request = create(:pull_request, :disable_disk_access, user: author, repository: repo)
        review = create(:pull_request_review, pull_request: pull_request, user: reviewer)
        assert_equal adapter(review).saml_enforcement, { organization_id: org.id }
      end
    end

    context "mobile_layout" do
      test "approve" do
        @review.approve!
        assert adapter(@review, { operation: "create" }).mobile_layout.title.include?("approved")
      end

      test "comment" do
        @review.comment!
        assert adapter(@review, { operation: "create" }).mobile_layout.title.include?("review comment")
      end

      test "request changes" do
        @review.request_changes!
        assert adapter(@review, { operation: "create" }).mobile_layout.title.include?("requested changes")
      end

      test "update" do
        assert adapter(@review, { operation: "update" }).mobile_layout.title.include?("mentioned")
      end
    end

    test "email_layout" do
      assert_nil adapter(@review, { actor_login: "test_login" }).email_layout
    end

    context "trigger" do
      test "create" do
        assert_equal adapter(@review.pull_request, { operation: "create" }).trigger, "pull_request_reviewed"
      end

      test "update" do
        assert_equal adapter(@review.pull_request, { operation: "update" }).trigger, "update"
      end
    end

    test "returns related_topics" do
      @review.pull_request.labels << create(:label, repository: @review.pull_request.repository)
      @review.pull_request.labels << create(:label, repository: @review.pull_request.repository)

      expected_topics = [
        { type: "repository", value: @review.repository.id.to_s },
        { type: "pull_request_review", value: @review.id.to_s },
        { type: "pull_request", value: @review.pull_request.id.to_s },
        { type: "issue", value: @review.pull_request.issue.id.to_s },
      ]
      assert_equal adapter(@review).related_topics, expected_topics
    end

    context "explicit_recipients" do
      test "create" do
        assert_equal adapter(@review, { current_body: @review.body, operation: "create" }).explicit_recipients,
          [{ reason: "pull_request_reviewed", users: [@pull_request.user] }]
      end

      test "update" do
        @review.body = "Hi @#{@mentioned}"
        assert_equal adapter(@review, { current_body: @review.body, operation: "update" }).explicit_recipients,
          [{ reason: "mention", users: [@mentioned] }]
      end
    end

    private

    def adapter(pull_request_review, context = {})
      Notifyd::PullRequestReviewAdapter.new(pull_request_review, context)
    end
  end
end
