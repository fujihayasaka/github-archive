# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Files::CopilotDiffChat
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

        @expected_payload = [{ "reference" => {
          "type" => "file-diff",
            "id" => "diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5",
            "url" => "#{repo.owner.display_login}/#{repo.name}/raw/537c5fa04ce1ee1f265e325bbb49b281ddc431a3/README.md",
            "baseFile" => {
              "type" => "file",
              "url" => "#{repo.owner.display_login}/#{repo.name}/raw/537c5fa04ce1ee1f265e325bbb49b281ddc431a3/README.md",
              "path" => "README.md",
              "repoID" => repo.id,
              "repoOwner" => repo.owner.display_login,
              "repoName" => repo.name,
              "ref" => "537c5fa04ce1ee1f265e325bbb49b281ddc431a3",
              "commitOID" => "537c5fa04ce1ee1f265e325bbb49b281ddc431a3"
            },
            "headFile" => {
              "type" => "file",
              "url" => "#{repo.owner.display_login}/#{repo.name}/raw/c78be2730338ba61f8bc0f9a3b8dae0fdfd239cd/README.md",
              "path" => "README.md",
              "repoID" => repo.id,
              "repoOwner" => repo.owner.display_login,
              "repoName" => repo.name,
              "ref" => "c78be2730338ba61f8bc0f9a3b8dae0fdfd239cd",
              "commitOID" => "c78be2730338ba61f8bc0f9a3b8dae0fdfd239cd"
            }
          },
          "path" => "README.md"
        }]
      end

      test "serializes the copilot diff data with Ruby conventions using to_hash" do
        data = PullRequests::PageData::CopilotDiffChat::Loader.load(
          base_oid: @pull.historical_comparison.async_base_oid.sync,
          head_oid: @pull.historical_comparison.async_head_oid.sync,
          pull_request: @pull,
        )

        assert_no_queries do
          actual_payload = PullRequests::PageData::CopilotDiffChat::Payload.call(data)
          assert_equal @expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
