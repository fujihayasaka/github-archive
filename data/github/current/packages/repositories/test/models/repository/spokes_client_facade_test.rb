# typed: strict
# frozen_string_literal: true

require "test_helper"

class RepositorySpokesClientFacadeTest < GitHub::TestCase
  context "purge_repository" do
    test "purging last repo in a network deletes disk and replicas" do
      repo = create :repository

      Repository.any_instance.expects(:remove_from_disk).at_least_once
      Repository.any_instance.expects(:remove_wiki_from_disk).at_least_once
      GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).at_least_once
      GitHub::DGit::Maintenance.expects(:delete_network_replicas).at_least_once

      repo.remove(repo.owner, synchronous: true)
      assert repo.spokes_api_facade.purge_repository
    end

    test "purging a repo with siblings in network keeps network replicas" do
      repo = create :repository
      forked = create(:fork_repository, forker: create(:user), fork_repo: repo)

      Repository.any_instance.expects(:remove_from_disk).at_least_once
      Repository.any_instance.expects(:remove_wiki_from_disk).at_least_once
      GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).at_least_once
      GitHub::DGit::Maintenance.expects(:delete_network_replicas).never

      repo.remove(repo.owner, synchronous: true)
      assert repo.spokes_api_facade.purge_repository
    end

    test "purging a repo without a network only removes from disk" do
      repo = create :repository
      repo.update(network_id: nil)

      Repository.any_instance.expects(:remove_from_disk).at_least_once
      Repository.any_instance.expects(:remove_wiki_from_disk).never
      GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).never
      GitHub::DGit::Maintenance.expects(:delete_network_replicas).never

      repo.remove(repo.owner, synchronous: true)
      assert repo.spokes_api_facade.purge_repository
    end

    test "does not remove replica data if removing from disk fails" do
      repo = create :repository

      Repository.any_instance.stubs(:remove_from_disk).raises(StandardError, "error")
      Repository.any_instance.expects(:remove_wiki_from_disk).never
      GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).never
      GitHub::DGit::Maintenance.expects(:delete_network_replicas).never

      repo.remove(repo.owner, synchronous: true)
      refute repo.spokes_api_facade.purge_repository
    end
  end

  context "create_repository" do
    test "creating a repository inits repo replicas and writes repo to disk" do
      repo = create :repository

      Repository.any_instance.expects(:initialize_replicas_from_network).once
      RepositoryNetwork.any_instance.expects(:initialize_placeholder_network_replicas).once
      Repository.any_instance.stubs(:exists_on_disk?).returns(false)
      Repository.any_instance.expects(:setup_new_git_repository).once

      assert repo.spokes_api_facade.create_repository
    end

    test "an error in creation is reported" do
      repo = create :repository

      Repository.any_instance.stubs(:initialize_replicas_from_network).raises(StandardError, "error")
      Repository.any_instance.stubs(:exists_on_disk?).returns(false)
      Repository.any_instance.expects(:setup_git_repository).never

      Failbot.expects(:report).once

      refute repo.spokes_api_facade.create_repository
    end
  end

  context "clone_repository" do
    test "cloning a repository inits repo replicas and writes repo to disk" do
      repo = create :repository
      source_repo = create :repository

      Repository.any_instance.expects(:initialize_replicas_from_network).once
      RepositoryNetwork.any_instance.expects(:initialize_placeholder_network_replicas).once
      Repository.any_instance.stubs(:exists_on_disk?).returns(false)

      assert_enqueued_with job: RepositoryCloneJob, args: [source_repo, repo] do
        assert repo.spokes_api_facade.clone_repository(source_repository: source_repo)
      end
    end

    test "an error in forking is reported" do
      repo = create :repository
      source_repo = create :repository

      Repository.any_instance.stubs(:initialize_replicas_from_network).raises(StandardError, "error")
      Repository.any_instance.stubs(:exists_on_disk?).returns(false)

      Failbot.expects(:report).once

      refute repo.spokes_api_facade.clone_repository(source_repository: source_repo)
    end
  end

  context "initialize_repository" do
    test "initializing a repository inits repo content on disk" do
      user = create(:user)
      repo = create(:repository, owner: user)

      assert repo.empty?

      repo.created_by_user_id = user.id
      repo.auto_init = true
      assert repo.spokes_api_facade.initialize_repository

      commit = repo.heads.find(repo.default_branch).target
      blob = repo.blob(commit.oid, "README.md")
      assert_equal "# #{repo.name}", blob.data
    end

    test "an error in initialization is reported" do
      user = create(:user)
      repo = create(:repository, owner: user)

      Repository.any_instance.stubs(:initialize_git_repository_templates).raises(StandardError, "error")

      Failbot.expects(:report).once

      repo.created_by_user_id = user.id
      repo.auto_init = true
      refute repo.spokes_api_facade.initialize_repository
      assert repo.empty?
    end
  end
end
