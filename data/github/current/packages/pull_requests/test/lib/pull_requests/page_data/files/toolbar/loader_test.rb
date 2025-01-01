# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Files::Toolbar
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user.split_diff_preferred = "split"
        @user_session = create(:authentication_record, user: @user).user_session


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

        UserReviewedFile.create(
          filepath: "bar.txt",
          user: @user,
          pull_request: @pull,
          head_sha: @pull.head_sha,
        )

        example_repo_snapshot
      end

      test "returns expected payload for logged in user" do
        # Codespace access differs depending on test mode (dotcom vs MT vs EMU), so rather than jump through
        # hoops to set up the user, repo, org, etc. data correctly for each mode, we're stubbing it out.

        expected_payload = {
          "annotations" => [],
          "host_url" => "https://github.com",
          "pull_request" => {
            "id" => @pull.id,
            "path_name" => @pull.permalink(include_host: false)
          },
          "repository_id" => @repository.id,
          "thread_previews" => [],
          "total_files_count" => 1,
          "viewed_files_count" => 1,
          "view_settings" => {
            "hide_whitespace" => false,
            "line_spacing" => "relaxed",
            "split_preference" => "split",
          },
        }

        actual_payload = PullRequests::PageData::Files::Toolbar::Loader.load(
          cap_filter: nil,
          current_user: @user,
          end_commit_oid: @pull.head_sha,
          pull_request: @pull,
          user_session: @user_session
        )
        assert_equal expected_payload, actual_payload.serialize
      end

      test "returns expected payload for logged out user" do
        expected_payload = {
          "annotations" => [],
          "host_url" => "https://github.com",
          "pull_request" => {
            "id" => @pull.id,
            "path_name" => @pull.permalink(include_host: false)
          },
          "repository_id" => @repository.id,
          "thread_previews" => [],
          "total_files_count" => 1,
          "viewed_files_count" => 0,
          "view_settings" => {
            "hide_whitespace" => false,
            "line_spacing" => "relaxed",
            "split_preference" => "unified",
          },
        }
        actual_payload = PullRequests::PageData::Files::Toolbar::Loader.load(
          cap_filter: nil,
          current_user: nil,
          end_commit_oid: @pull.head_sha,
          pull_request: @pull,
          user_session: @user_session
        )
        assert_equal expected_payload, actual_payload.serialize
      end
    end
  end
end
