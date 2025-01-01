# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class RepositoryPushHandlerTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user, from_example: :post_receive_job_test)
    end

    setup do
      @ref_updates = [
        Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/master",
          before_oid: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
        )]
    end

    context "on_repository_push" do
      test "instruments SecretScanningConfigChange when config file is updated" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

        # create and push the config to the default branch
        default_branch = @repo.heads["master"]
        commit = default_branch.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
          files.add ".github/secret_scanning.yml", "some content"
        end

        ref_updates = [Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/master",
          before_oid: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after_oid: @repo.heads["master"].target_oid,
        )]

        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, ref_updates, @user)
        assert_hydro_messages(count: 1, schema: "github.v1.SecretScanConfigChange")
        default_branch.revert_commit(@user, commit.oid) # reset
      end

      test "does not instrument SecretScanningConfigChange if config file updated on non-default branch" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

        # create and push the config to another branch
        other_branch = @repo.heads["topic"]
        commit = other_branch.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
          files.add ".github/secret_scanning.yml", "some content"
        end
        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, @ref_updates, @user)

        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

        other_branch.revert_commit(@user, commit.oid) # reset
      end

      test "does not instrument SecretScanningConfigChange if config file was not updated" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, @ref_updates, @user)

        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")
      end

      test "message includes SecretScanningConfigChange when appropriate for deleting the default branch" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

        # delete default branch without config
        updates = [Git::Ref::Update.new(repository: @repo, refname: "master", before_oid: @repo.heads["master"].target_oid, after_oid: GitHub::NULL_OID)]
        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, updates, @user)

        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")

        # create and push the config to the default branch
        default_branch = @repo.heads["master"]
        commit = default_branch.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
          files.add ".github/secret_scanning.yml", "some content"
        end

        ref_updates = [Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/master",
          before_oid: GitHub::NULL_OID,
          after_oid: @repo.heads["master"].target_oid,
        )]

        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, ref_updates, @user)
        assert_hydro_messages(count: 1, schema: "github.v1.SecretScanConfigChange")

        # delete default branch with config
        updates = [Git::Ref::Update.new(repository: @repo, refname: "master", before_oid: @repo.heads["master"].target_oid, after_oid: GitHub::NULL_OID)]
        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, updates, @user)
        assert_hydro_messages(count: 2, schema: "github.v1.SecretScanConfigChange")

        default_branch.revert_commit(@user, commit.oid) # reset
      end

      test "does not instrument SecretScanningConfigChange if secret scanning disabled" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)

        SecretScanning::Instrumentation::RepositoryPushHandler.on_repository_push(@repo, @ref_updates, @user)
        assert_hydro_messages(count: 0, schema: "github.v1.SecretScanConfigChange")
      end
    end
  end
end
