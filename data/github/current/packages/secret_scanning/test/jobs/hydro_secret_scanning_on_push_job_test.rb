# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user, from_example: :post_receive_job_test)

    @ref = "refs/heads/master"
    @before = "c1800491d95c42b4e96fb83f31fe8d9230c62907"
    @after = "63611721afd41f58f801d66e543d8288b4c5eb44"
  end

  setup do
    @message = {
      ref_updates: [{ ref: @ref, before: @before, after: @after }],
      repository_id: @repository.id,
      pusher: @user.login,
      pushed_at: Time.now,
    }
  end

  test "notifies security center of updates" do
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_secret_scanning_on_push") do
      SecretScanning::Instrumentation::RepositoryPushHandler.expects(:on_repository_push).once
    end
  end

  test "instruments SecretScanningConfigChange when config file is updated" do
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

    assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

    # create and push the config to the default branch
    default_branch = @repository.heads["master"]
    commit = default_branch.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
      files.add ".github/secret_scanning.yml", "some content"
    end
    @message[:ref_updates] = [{ ref: "refs/heads/master", before: @after, after: @repository.heads["master"].target_oid }]

    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_secret_scanning_on_push")

    assert_hydro_messages(count: 1, schema: "github.v1.SecretScanConfigChange")

    default_branch.revert_commit(@user, commit.oid) # reset
  end

  test "message includes SecretScanningConfigChange when appropriate for deleting the default branch" do
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

    assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

    # delete default branch without config
    @message[:ref_updates] = [{ ref: "refs/heads/master", before: @repository.heads["master"].target_oid, after: GitHub::NULL_OID }]
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_secret_scanning_on_push")

    assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

    # create and push the config to the default branch
    default_branch = @repository.heads["master"]
    commit = default_branch.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
      files.add ".github/secret_scanning.yml", "some content"
    end
    @message[:ref_updates] = [{ ref: "refs/heads/master", before: GitHub::NULL_OID, after: @repository.heads["master"].target_oid }]
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_secret_scanning_on_push")
    assert_hydro_messages(count: 1, schema: "github.v1.SecretScanConfigChange")

    # delete default branch with config
    @message[:ref_updates] = [{ ref: "refs/heads/master", before: @repository.heads["master"].target_oid, after: GitHub::NULL_OID }]
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_secret_scanning_on_push")

    assert_hydro_messages(count: 2, schema: "github.v1.SecretScanConfigChange")

    default_branch.revert_commit(@user, commit.oid) # reset
  end
end
