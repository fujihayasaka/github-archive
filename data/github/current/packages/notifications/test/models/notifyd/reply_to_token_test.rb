# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class ReplyToTokenTest < GitHub::TestCase

    context "generate" do
      test "generate a valid token when target and user exist" do
        Timecop.freeze do
          issue = create(:issue)
          user = issue.user
          notification_id = Notifyd::IssueAdapter.new(issue).notification_id
          actual_token = ReplyToToken.new(user, notification_id).generate
          assert actual_token
          expected_token = GitHub::Email::Token.target_token(issue, user)
          assert_equal actual_token, expected_token
        end
      end

      test "returns nothing when target does not exist" do
        issue = create(:issue)
        user = issue.user
        notification_id = Notifyd::IssueAdapter.new(issue).notification_id
        issue.destroy
        refute ReplyToToken.new(user, notification_id).generate
      end

      test "returns nothing when user id is nil" do
        issue = create(:issue)
        notification_id = Notifyd::IssueAdapter.new(issue).notification_id
        refute ReplyToToken.new(nil, notification_id).generate
      end

      test "returns nothing when notification_id is nil" do
        issue = create(:issue)
        user = issue.user
        refute ReplyToToken.new(user, nil).generate
      end
    end

    context "ReplyToToken::Target" do
      test "fetches Issue target from notification_id" do
        original_target = create(:issue)
        target = ReplyToToken::Target.new(Notifyd::IssueAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "Issue"
        assert_equal target.id, original_target.id
      end

      test "fetches IssueComment target from notification_id" do
        original_target = create(:issue_comment)
        target = ReplyToToken::Target.new(Notifyd::IssueCommentAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "IssueComment"
        assert_equal target.id, original_target.id
      end

      test "fetches Discussion target from notification_id" do
        original_target = create(:discussion)
        target = ReplyToToken::Target.new(Notifyd::DiscussionAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "Discussion"
        assert_equal target.id, original_target.id
      end

      test "fetches DiscussionComment target from notification_id" do
        original_target = create(:discussion_comment)
        target = ReplyToToken::Target.new(Notifyd::DiscussionCommentAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "DiscussionComment"
        assert_equal target.id, original_target.id
      end

      test "fetches PullRequestReview target from notification_id" do
        original_target = create(:pull_request_review, pull_request: create(:pull_request, :disable_disk_access))
        target = ReplyToToken::Target.new(Notifyd::PullRequestReviewAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "PullRequestReview"
        assert_equal target.id, original_target.id
      end

      test "does not fetch CheckSuite target from notification_id" do
        adapter = Notifyd::CheckSuiteAdapter.new(create(:check_suite, :with_name, :failure, :with_push, pusher: create(:user)))
        refute ReplyToToken::Target.new(adapter.notification_id).get
      end

      test "does not fetch GateRequest target from notification_id", skip_enterprise: true  do
        make_trusted_oauth_apps_owner
        repository = create(:repository)
        env = create(:environment, repository: repository)
        check_suite = create(:check_suite_for_actions_app, repository: repository)
        check_run = create(:check_run, :success, check_suite: check_suite)
        gate = create(:gate, type: :manual_approval, environment: env)
        gate_request = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil)
        adapter = Notifyd::GateRequestAdapter.new(gate_request)
        refute ReplyToToken::Target.new(adapter.notification_id).get
      end

      test "fetches GistComment target from notification_id" do
        original_target = create(:gist_comment)
        target = ReplyToToken::Target.new(Notifyd::GistCommentAdapter.new(original_target).notification_id).get
        assert_equal target.class.name, "GistComment"
        assert_equal target.id, original_target.id
      end

      test "returns nil for unknown subject notification_ids" do
        refute ReplyToToken::Target.new("").get
        refute ReplyToToken::Target.new(nil).get
        refute ReplyToToken::Target.new("/").get
        refute ReplyToToken::Target.new("/#3-2").get
        refute ReplyToToken::Target.new("/#discussioncomment-243523").get
      end
    end
  end
end
