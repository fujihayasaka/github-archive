# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::ViewedFilesCount
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
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

        UserReviewedFile.create(
          filepath: "bar.txt",
          user: @user,
          pull_request: @pull,
          head_sha: @pull.head_sha,
        )
      end

      test "returns expected payload for logged in user" do
        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @pull.head_sha,
          pull: @pull,
          start_commit_oid: @pull.merge_base,
          viewer: @user,
        )

        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          comparison: pull_comparison,
          current_user: @user,
          pull_request: @pull
        ), 1
      end

      test "returns expected payload for logged out user" do
        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @pull.head_sha,
          pull: @pull,
          start_commit_oid: @pull.merge_base,
          viewer: @user,
        )

        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          comparison: pull_comparison,
          current_user: nil,
          pull_request: @pull
        ), 0
      end

      test "has database error fallback" do
        PullRequest.any_instance.stubs(:name).raises(ActiveRecord::ActiveRecordError.new)

        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @pull.head_sha,
          pull: @pull,
          start_commit_oid: @pull.merge_base,
          viewer: @user,
        )

        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          comparison: pull_comparison,
          current_user: nil,
          pull_request: @pull
        ), 0
      end
    end
  end
end
