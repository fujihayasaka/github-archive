# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::TabCounts
    class PayloadTest < GitHub::TestCase

      fixtures do
        @user = create(:user)
        repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)

        @pull = create(:pull_request,
          base_ref: repo.default_branch,
          base_repository: repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: repo,
          head_user: @user,
          repository: repo,
          user: @user,
        )

        check_suite = create(:check_suite, repository: repo, head_sha: @pull.head_sha)
        create(:check_run, :success, check_suite:, display_name: "required-run")

        create(:issue_comment, issue: @pull.issue)

        @expected_payload = {
          "checksCount" => 1,
          "conversationCount" => 1,
          "filesChangedCount" => 1,
        }
      end

      test "serializes the tab counts with Ruby conventions using to_hash" do
        data = PullRequests::PageData::TabCounts::Loader.load(pull_request: @pull)

        assert_no_queries do
          actual_payload = PullRequests::PageData::TabCounts::Payload.call(data)
          assert_equal @expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
