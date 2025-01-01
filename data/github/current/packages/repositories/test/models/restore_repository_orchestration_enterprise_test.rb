# typed: false
# frozen_string_literal: true

require "test_helper"

class RestoreRepositoryOrchestrationEnterpriseTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @actor = create(:user)
  end

  setup do
    repo = create :repository, owner: @user
    repo.initialize_wiki(repo.owner)
    example_repo :wiki, repo.unsullied_wiki
    issue = create :issue, repository: repo, user: @user

    repo.remove(@user)
    @archived = Repositories::Public.find_deleted(repo.id)
    @job_args = [@archived.id, @actor.id]
    @job_status = Restoration::RepositoryRestoreStatus.for(repository_id: @archived.id)
  end

  if GitHub.enterprise?
    test "verify restore creates network replicas from fork" do
      Packages::SyncPackagePermsOnRepoChangeJob.any_instance.stubs(:perform).returns(true)
      repo = create(:private_repository, from_example: :simple)
      org = create(:organization)
      org.add_member(repo.owner)

      org_repo = create(:fork_repository, forker: repo.owner, fork_repo: repo, organization: org)

      org_repo.remove(repo.owner)
      assert_nil Repositories::Public.find_active(org_repo.id)

      Repository.restore(org_repo.id, actor: @user)
      org_repo = Repositories::Public.find_active(org_repo.id)

      hosts = GitHub::DGit::Routing.hosts_for_repo(org_repo.id)
      assert_equal GitHub.dgit_default_copies, hosts.length
      assert_same_elements hosts, GitHub::DGit::Routing.hosts_for_network(org_repo.network.id)
      nrs = GitHub::DGit::Routing.all_network_replicas(org_repo.network.id)
      rrs = GitHub::DGit::Routing.all_repo_replicas(org_repo.id)
      assert_equal nrs.size, rrs.size
    end

    test "verify restore creates network replicas" do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@archived.id, actor: @actor, synchronous: false)
      end

      repo = Repositories::Public.find_active!(@archived.id)
      hosts = GitHub::DGit::Routing.hosts_for_repo(repo.id)
      assert_equal GitHub.dgit_default_copies, hosts.length
      assert_same_elements hosts, GitHub::DGit::Routing.hosts_for_network(repo.network.id)

      nrs = GitHub::DGit::Routing.all_network_replicas(repo.network.id)
      rrs = GitHub::DGit::Routing.all_repo_replicas(repo.id)
      assert_equal nrs.size, rrs.size

      nrs.each do |nr|
        matching_rr = rrs.find { |rr| nr.db_network_replica_id == rr.db_network_replica_id }
        refute_nil matching_rr, "No matching repository replica found for network replica"
        # We currently join on host, so make sure that this is the match we'd make
        assert_equal nr.host, matching_rr.host
      end
    end

    test "verify restore creates replicas for repository wiki" do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@archived.id, actor: @actor, synchronous: false)
      end

      repo = Repositories::Public.find_active!(@archived.id)
      assert repo.unsullied_wiki.exist?, "Wiki should exist after being restored"
      hosts = GitHub::DGit::Routing.hosts_for_repo(repo.id, true)
      assert_equal GitHub.dgit_default_copies, hosts.length
    end
  end
end
