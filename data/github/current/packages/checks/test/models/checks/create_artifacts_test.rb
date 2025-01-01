# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::CreateArtifactsTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  fixtures do
    @user = create(:user, plan:  "pro")
    @repository = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repository.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    make_trusted_oauth_apps_owner

    @check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, head_branch: nil)
  end

  context "call" do
    test "creates check suite artifacts" do
      created_at = DateTime.current
      expires_at = DateTime.current + 1.day

      artifacts_data = [
        {
          name: "Artifact 1",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
          size: 102400,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
        },
        {
          name: "Artifact 2",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_2.zip",
          size: 204800,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
        },
      ]

      Checks::CreateArtifacts.call(
        check_suite: @check_suite,
        artifacts: artifacts_data,
      )

      @check_suite.reload

      artifacts = @check_suite.artifacts
      artifact_1 = artifacts.find_by(name: "Artifact 1")
      artifact_2 = artifacts.find_by(name: "Artifact 2")

      assert_equal 2, artifacts.count
      assert_equal "https://dev.azure.com/Account/project/_build/artifacts_1.zip", artifact_1.source_url
      assert_equal 102400, artifact_1.size
      assert_equal created_at.to_i, artifact_1.created_at.to_i
      assert_equal expires_at.to_i, artifact_1.expires_at.to_i
      assert_equal @check_suite.repository_id, artifact_1.repository_id
      assert_equal "https://dev.azure.com/Account/project/_build/artifacts_2.zip", artifact_2.source_url
      assert_equal 204800, artifact_2.size
      assert_equal created_at.to_i, artifact_2.created_at.to_i
      assert_equal expires_at.to_i, artifact_2.expires_at.to_i
      assert_equal @check_suite.repository_id, artifact_2.repository_id
    end

    test "subsequent update check suite does not dupe artifacts" do
      created_at = DateTime.current
      expires_at = DateTime.current + 1.day

      artifacts_data = [
        {
          name: "Artifact 1",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
          size: 102400,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
      },
        {
          name: "Artifact 2",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_2.zip",
          size: 204800,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
        },
      ]

      Checks::CreateArtifacts.call(
        check_suite: @check_suite,
        artifacts: artifacts_data,
      )

      @check_suite.reload
      assert_equal 2, @check_suite.artifacts.count

      Checks::CreateArtifacts.call(
        check_suite: @check_suite,
        artifacts: artifacts_data,
      )

      @check_suite.reload
      assert_equal 2, @check_suite.artifacts.count
    end

    test "adds additional artifacts to existing artifacts" do
      created_at = DateTime.current
      expires_at = DateTime.current + 1.day

      artifacts_data = [
        {
          name: "Artifact 2",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_2.zip",
          size: 204800,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
        },
        {
          name: "Artifact 3",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_3.zip",
          size: 100,
          created_at: created_at,
          expires_at: expires_at,
          repository_id: @repository.id,
        },
      ]

      @check_suite.artifacts.create!(
        name: "Artifact 1",
        source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
        size: 102400,
        repository: @check_suite.repository
      )

      Checks::CreateArtifacts.call(
        check_suite: @check_suite,
        artifacts: artifacts_data,
      )

      @check_suite.reload

      artifacts = @check_suite.artifacts
      artifact_1 = artifacts.find_by(name: "Artifact 1")
      artifact_2 = artifacts.find_by(name: "Artifact 2")
      artifact_3 = artifacts.find_by(name: "Artifact 3")

      assert_equal 3, artifacts.count
      assert_equal "https://dev.azure.com/Account/project/_build/artifacts_1.zip", artifact_1.source_url
      assert_equal 102400, artifact_1.size
      assert_equal "https://dev.azure.com/Account/project/_build/artifacts_2.zip", artifact_2.source_url
      assert_equal 204800, artifact_2.size
      assert_equal created_at.to_i, artifact_2.created_at.to_i
      assert_equal "https://dev.azure.com/Account/project/_build/artifacts_3.zip", artifact_3.source_url
      assert_equal 100, artifact_3.size
      assert_equal created_at.to_i, artifact_3.created_at.to_i
    end
  end
end
