# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::TabCounts
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )
        check_suite = create(:check_suite, repository: @repository, head_sha: @pull.head_sha)
        create(:check_run, :success, check_suite:, display_name: "required-run")

        create(:issue_comment, issue: @pull.issue)
        create(:issue_comment, issue: @pull.issue)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "returns expected payload" do
        expected_payload = {
          "check_suites_count" => 1,
          "conversation_count" => 2,
          "files_changed_count" => 1,
        }

        actual_payload = PullRequests::PageData::TabCounts::Loader.load(pull_request: @pull)

        assert_equal expected_payload, actual_payload.serialize
      end

      test "uses fallback value when changed files count GitRPC request fails" do
        GitHub::Diff.any_instance.stubs(:changed_files).raises(GitRPC::Error.new)
        payload = PullRequests::PageData::TabCounts::Loader.load(pull_request: @pull)
        assert_equal PullRequests::PageData::TabCounts::Loader::CHANGED_FILES_COUNT_FALLBACK, payload.files_changed_count
      end

      test "uses fallback value when check runs count query fails" do
        PullRequest.any_instance.stubs(:latest_check_runs_count).raises(ActiveRecord::ActiveRecordError.new)
        payload = PullRequests::PageData::TabCounts::Loader.load(pull_request: @pull)
        assert_equal PullRequests::PageData::TabCounts::Loader::CHECKS_COUNT_FALLBACK, payload.check_suites_count
      end
    end
  end
end
