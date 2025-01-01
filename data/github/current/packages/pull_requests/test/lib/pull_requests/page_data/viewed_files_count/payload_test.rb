# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::ViewedFilesCount
    class PayloadTest < GitHub::TestCase
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

      test "serializes the code button with Ruby conventions using to_hash" do
        data = PullRequests::PageData::ViewedFilesCount::Loader.load(
          current_user: @user,
          pull_request: @pull,
        )
        expected_payload = { "viewedFilesCount" => 1 }

        assert_no_queries do
          actual_payload = PullRequests::PageData::ViewedFilesCount::Payload.call(data)
          assert_equal expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
