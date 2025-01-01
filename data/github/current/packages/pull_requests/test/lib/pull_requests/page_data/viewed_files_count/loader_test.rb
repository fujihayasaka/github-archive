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
        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          current_user: @user,
          pull_request: @pull
        ), 1
      end

      test "returns expected payload for logged out user" do
        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          current_user: nil,
          pull_request: @pull
        ), 0
      end

      test "has database error fallback" do
        PullRequest.any_instance.stubs(:name).raises(ActiveRecord::ActiveRecordError.new)

        assert_equal PullRequests::PageData::ViewedFilesCount::Loader.load(
          current_user: nil,
          pull_request: @pull
        ), 0
      end
    end
  end
end
