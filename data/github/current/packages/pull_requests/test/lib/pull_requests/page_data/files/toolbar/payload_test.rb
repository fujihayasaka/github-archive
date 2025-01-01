# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files::Toolbar
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @user_session = create(:authentication_record, user: @user).user_session
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

        @expected_payload = {
          "annotations" => [],
          "hostUrl" => "https://github.com",
          "pullRequest" => {
            "id" => @pull.id,
            "pathName" => @pull.permalink(include_host: false),
          },
          "repositoryId" => @pull.repository.id,
          "threadPreviews" => [],
          "totalFilesCount" => 1,
          "viewedFilesCount" => 0,
          "viewSettings" => {
            "hideWhitespace" => false,
            "lineSpacing" => "relaxed",
            "splitPreference" => "unified",
          },
        }
      end

      test "serializes the code button with Ruby conventions using to_hash" do
        data = PullRequests::PageData::Files::Toolbar::Loader.load(
          cap_filter: nil,
          current_user: @user,
          end_commit_oid: @pull.head_sha,
          pull_request: @pull,
          user_session: @user_session,
        )

        assert_no_queries do
          actual_payload = PullRequests::PageData::Files::Toolbar::Payload.call(data)
          assert_equal @expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
