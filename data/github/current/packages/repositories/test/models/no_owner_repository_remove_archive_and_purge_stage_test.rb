# typed: false
# frozen_string_literal: true

require "test_helper"

# Test case for the background portion of the removal process. Checks that
# repository records are archived and removed entirely and that git data is
# cleaned up properly.
class NoOwnerRepositoryRemoveArchiveAndPurgeStageTest < GitHub::TestCase
  include RepositoriesTestHelper
  include HydroMessageJobTestHelpers
  include AuditLog::IntegrationTestHelpers

  PackageRepoMock = Struct.new(:packages)
  fixtures do
    @priv_user = create(:user, plan: "medium")
    @pub_user = create(:user, plan: "medium")
    @user = create(:user)

    @private = create(:private_repository, owner: @priv_user, from_example: :simple)
    @private.add_member(@pub_user)
    @private.add_member(@user)

    @priv_fork = create(:fork_repository, forker: @pub_user, fork_repo: @private)

    @public = create(:repository, owner: @pub_user, from_example: :simple)
    @pub_fork = create(:fork_repository, forker: @priv_user, fork_repo: @public)

    example_repo(:simple, @public.unsullied_wiki)
    example_repo(:simple, @private.unsullied_wiki)
    example_repo(:simple, @pub_fork.unsullied_wiki)
    example_repo(:simple, @priv_fork.unsullied_wiki)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackageRepoMock.new(packages: []))
    GitHub.flipper[:update_notification_summary_always_enqueue].enable
  end

  def make_pull_request
    @repo = create(:repository, from_example: :pull_request_source)

    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create("branch", base_ref.target, @repo.owner)
    head_ref.append_commit({ message: "an change",
                             committer: @repo.owner }, @repo.owner) do |files|
      files.add("change.txt", "foo")
    end

    @issue = create :issue, repository: @repo
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "branch",
      issue: @issue,
    )
  end

  test "archives records" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)
    assert Repositories::Public.is_deleted?(@public.id)
  end

  test "records deleted_by and deleted_at on archive record" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)
    archived = Repositories::Public.find_deleted(@public.id)
    assert_equal @pub_user.id, archived.deleted_by_user_id
    assert_equal @pub_user, archived.deleted_by
    assert archived.deleted_at.is_a?(Time)
  end

  test "does not remove individual repo from disk" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    paths = DGit.paths_for_repo(@public)
    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)

    assert_nil  Repositories::Public.find_active(@public.id)
    paths.each do |shard_path|
      assert File.exist?(shard_path), "#{shard_path} should exist"
    end
  end

  test "destroys the network record when no repositories remain" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    assert network = @public.network

    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)
    @public.purge(synchronous: true)
    assert RepositoryNetwork.exists?(network.id)

    @pub_fork = Repositories::Public.find_active!(@pub_fork.id)
    @pub_fork.remove(@priv_user, synchronous: true)
    @pub_fork.purge(synchronous: true)
    assert !RepositoryNetwork.exists?(network.id)
  end

  test "purges repo and dependent forks when private" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    user = create(:user, plan: "medium")
    @priv_fork.add_member user

    priv_fork2, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @priv_fork.fork(forker: user)
    end

    user2 = create(:user, plan: "medium")
    priv_fork2.add_member user2
    priv_fork3, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      priv_fork2.fork(forker: user2)
    end

    other_fork, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @private.fork(forker: @user)
    end

    private_path   = @private.shard_path
    wiki_path      = @private.unsullied_wiki.shard_path
    dependent_path = @priv_fork.shard_path
    other_path     = other_fork.shard_path

    assert File.exist?(private_path)
    assert File.exist?(wiki_path)
    assert File.exist?(dependent_path)
    assert File.exist?(other_path)

    assert_equal 5, @private.network.repositories.size

    non_existent_owner(@private)
    @private.remove(@priv_user, synchronous: true)

    assert Repositories::Public.is_deleted?(@private.id)
    assert Repositories::Public.is_deleted?(@priv_fork.id)
    assert Repositories::Public.is_deleted?(priv_fork2.id)
    assert Repositories::Public.is_deleted?(priv_fork3.id)
    assert Repositories::Public.is_deleted?(other_fork.id)

    assert File.exist?(private_path), "#{private_path} doesn't exist after remove"
    assert File.exist?(wiki_path)
    assert File.exist?(dependent_path)
    assert File.exist?(other_path)
  end

  test "archives private forks" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

    other_user = create :user, plan: "small"
    @private.add_member other_user
    fork, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @private.fork(forker: @user)
    end
    fork_path = fork.shard_path
    assert File.exist?(fork_path)
    fork_2, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      fork.fork(forker: other_user)
    end
    fork_2_path = fork_2.shard_path
    assert File.exist?(fork_2_path)

    non_existent_owner(@private)
    fork.remove(@user, synchronous: true)

    assert File.exist?(fork_path)

    assert Repositories::Public.is_active?(@private.id)
    assert Repositories::Public.is_deleted?(fork.id)

    assert File.exist?(fork_2_path)

    fork_2.reload
    fork_2.remove(other_user, synchronous: true)

    assert File.exist?(fork_2_path)
    assert !Repositories::Public.find_active(fork_2.id)
  end

  test "archives forks when internal repo is removed" do
    business = Business.first || create(:business)
    org = create(:organization)
    admin = org.admin
    business.add_organization(org)
    org.allow_private_repository_forking(actor: admin)
    org.reload

    other_admin = create(:user, plan: :pro)
    org.add_admin(other_admin)

    internal_repo = create(:internal_repository, owner: org)

    fork = create(:fork_repository, forker: admin, fork_repo: internal_repo)
    # Temporarily change the visibility on the root Repo to allow the now unsupported 2-level internal fork creation
    internal_repo.send(:set_permission, Repository::PRIVATE_VISIBILITY)
    fork_of_fork, status = fork.fork(forker: other_admin)
    assert_equal :created, status
    internal_repo.send(:set_permission, Repository::INTERNAL_VISIBILITY)
    assert_equal internal_repo.internal?, true

    assert Repositories::Public.find_active(fork.id)
    assert Repositories::Public.find_active(fork_of_fork.id)

    non_existent_owner(internal_repo)
    internal_repo.remove(admin, synchronous: true)

    refute Repositories::Public.find_active(fork.id)
    refute Repositories::Public.find_active(fork_of_fork.id)
  end

  test "deletes commit contributions when destroyed" do
    repo = create(:repository)
    committers = Array.new(3) { create(:user) }
    3.times do |i|
      committers.each do |user|
        create :commit_contribution,
          repository: repo,
          user: user,
          committed_date: i.days.ago.to_date
      end
    end

    repo.remove(repo.owner, synchronous: true)

    assert_difference("CommitContribution.count", -9) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes commit contributions in the background" do
    repo = create(:repository)
    create :commit_contribution,
      repository: repo,
      user: repo.owner,
      committed_date: 1.day.ago.to_date

    repo.remove(repo.owner, synchronous: true)

    args = ["CommitContribution", repo.id, :repository, { inverse_relationship: true }]
    assert_enqueued_with job: DeleteDependentRecordsJob, args: args do
      non_existent_owner(repo)
      repo.purge(synchronous: true)
    end
  end

  context "delete statuses" do
    test "when destroyed" do
      repo = create(:repository, from_example: :mojombo_grit)
      reset_repo_root
      example_repo :mojombo_grit, repo
      3.times { create :status, repository: repo }

      repo.remove(repo.owner, synchronous: true)

      assert_difference("Status.where(repository_id: #{repo.id}).count", -3) do
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          non_existent_owner(repo)
          repo.purge(synchronous: true)
        end
      end
    end

    test "in the background" do
      repo = create(:repository, from_example: :mojombo_grit)
      reset_repo_root
      example_repo :mojombo_grit, repo
      status = create :status, repository: repo

      repo.remove(repo.owner, synchronous: true)

      args = ["Repository", repo.id, :statuses, { sharding_key: :repository_id, sharding_value: repo.id }]
      assert_enqueued_with job: DeleteDependentRecordsJob, args: args do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes issues when destroyed" do
    issue = create(:issue)

    repo = issue.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("Issue.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes issue events when destroyed" do
    issue_event = create :issue_event, event: "closed"

    repo = issue_event.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("IssueEvent.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(issue_event.repository)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes issue comments when destroyed" do
    issue_comment = create(:issue_comment)

    repo = issue_comment.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("IssueComment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(issue_comment.repository)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes pull requests when destroyed" do
    make_pull_request

    @repo.remove(@repo.owner, synchronous: true)

    assert_difference("PullRequest.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(@repo)
        @repo.purge(synchronous: true)
      end
    end
  end

  test "deletes pull request review comments when destroyed" do
    make_pull_request

    create :pull_request_review_comment, pull_request: @pull

    @repo.remove(@repo.owner, synchronous: true)

    assert_difference("PullRequestReviewComment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(@repo)
        @repo.purge(synchronous: true)
      end
    end
  end

  test "destroys deployments when destroyed" do
    deployment = create :deployment

    repo = deployment.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("Deployment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys protected branches in the background when destroyed" do
    prot_branch = create :protected_branch, repository: @public

    repo = prot_branch.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("ProtectedBranch.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(prot_branch.repository)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes commit comments when destroyed" do
    repo = create(:repository, from_example: :simple)

    commit = repo.heads.find("master").target

    comment = create(:commit_comment,
      repository: repo,
      user: create(:user),
      body: "This is a comment",
      commit_id: commit.oid,
    )

    repo = comment.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("CommitComment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(comment.repository)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes commit mentions when destroyed" do
    repo = create(:repository, from_example: :pull_request_source)

    sha = repo.heads.find("master").target_oid
    create :commit_mention, repository: repo, commit_id: sha

    repo.remove(repo.owner, synchronous: true)

    assert_difference("CommitMention.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys releases in the background when destroyed" do
    repo = create(:repository, from_example: :repository_test_simple)
    create :release, repository: repo, tag_name: "v1",
      author: repo.owner, state: :published, created_at: 1.month.ago,
      body: "*version 1*"

    repo.remove(repo.owner, synchronous: true)

    assert_difference("Release.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys webhooks in the background when destroyed" do
    repo = create(:deleted_repository)
    email_hook = create(:hook, name: "email", active: true, events: ["push"], installation_target: repo, config: { address: "foo@example.com " })
    web_hook = create(:hook, name: "web",   active: true, events: ["push"], installation_target: repo)

    assert_difference("Hook.count", -2) do

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.purge(synchronous: true) }
    end
  end

  test "destroys branch renames in the background when destroyed" do
    repo = create(:repository, from_example: :simple)
    rename = create(:repository_branch_rename, repository: repo, old_name: "master", new_name: "cucumbers", old_sha: "cdbef")

    repo.remove(repo.owner, synchronous: true)

    assert_difference("RepositoryBranchRename.count", -1) do
      non_existent_owner(repo)
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.purge(synchronous: true) }
    end
  end

  test "destroys check suites in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:check_suite, repository: repo)

    assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys close issue references in the background when destroyed" do
    repo = create(:repository)
    issue = create(:issue, repository: repo)
    ref = create(:close_issue_reference, issue: issue)

    repo.remove(repo.owner, synchronous: true)

    assert_difference("CloseIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys duplicate issues in the background when destroyed" do
    repo = create(:deleted_repository)
    issue = create(:issue, repository: repo)
    create(:duplicate_issue, issue: issue)

    assert_difference("DuplicateIssue.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys environments in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:environment, repository: repo)

    assert_difference("Environment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys packages in the background when destroyed" do
    GitHub.flipper[:skip_package_destroy_in_repo_purge].disable

    repo = create(:deleted_repository)
    create(:registry_package, repository: repo)

    assert_difference("Registry::Package.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys projects in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:project, owner: repo)

    assert_difference("Project.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys public keys in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:public_key, repository: repo, verifier: repo.owner)

    assert_difference("PublicKey.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository invitations in the background when destroyed" do
    repo = create(:deleted_repository)
    user = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: repo, invitee: user)

    assert_difference("RepositoryInvitation.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository vulnerability alerts in the background when destroyed" do
    repo = create(:deleted_repository)
    alerts = create(:repository_vulnerability_alert, repository: repo)

    assert_difference "RepositoryVulnerabilityAlert.count", -1 do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository rulesets in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:repository_ruleset, :targets_all_branches, source: repo)

    assert_difference("RepositoryRuleset.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys tabs in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:tab, anchor: "Removed", repository: repo)

    assert_difference("Tab.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository transfers in the background when destroyed" do
    repo = create(:deleted_repository)
    org = create(:organization, admin: repo.owner)
    create(:repository_transfer, repository: repo, requester: repo.owner, target: org)

    assert_difference("RepositoryTransfer.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys workflows in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:workflow, repository: repo, name: "CI", path: ".github/workflows/ci.yml")

    assert_difference("Actions::Workflow.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes labels in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:label, repository: repo, name: "foobar")

    assert_difference("Label.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes repository redirects in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:repository_redirect, repository: repo, repository_name: "org/repo")

    assert_difference("RepositoryRedirect.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes repository clones in the background when destroyed" do
    template_repo = create(:repository, template: true, from_example: :simple)
    repo = create(:deleted_repository)
    create(:repository_clone, template_repository: template_repo, clone_repository: repo)

    assert_difference("RepositoryClone.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes key links in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:key_link, owner: repo, key_prefix: "foo")

    assert_difference("KeyLink.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        non_existent_owner(repo)
        repo.purge(synchronous: true)
      end
    end
  end

  test "purge handles no tenant context" do
    GitHub.flipper[:tenant_context_telemetry_query_scoping_logging].enable

    on_multi_tenant_enterprise do
      owner = create(:emu)
      business = owner.enterprise_managed_business
      GitHub::CurrentTenant.set(business)
      updater = create(:emu, business: business)
      repo = create(:repository, owner: owner)
      repo.disable_releases_sidebar_section(updater)

      repo.remove(owner, synchronous: true)
      repo = Repository.find(repo.id)
      non_existent_owner(repo)

      events = assert_performed_audit_entries(count: 1, only: ["config_entry.destroy"]) do
        GitHub::CurrentTenant.remove
        o = RepositoryOrchestration.purge(repo)
        o.execute!(synchronous: true)
      end

      expected_payload = {
        action: "config_entry.destroy",
        actor: nil,
      }
      assert_subset_hash expected_payload, events.first

      refute(Failbot.reports.detect { |report| report["rollup_significant_frame"].include?("event_payload") && report["rollup_significant_frame"].include?("configuration")  })
      refute(Failbot.reports.detect { |report| report["rollup_significant_frame"].include?("clear_contributions_cache") })
    end
  end

  test "syncs commits of any cross-repo pull requests to the base repo" do
    source = create(:repository, from_example: :simple)

    only = [RepositoryOrchestrationJob, UpdateNotificationSummaryJob]
    fork, _ = perform_enqueued_jobs(only: only) do
      source.fork(forker: create(:user))
    end

    fork.reload

    metadata = { message: "blah", committer: fork.owner }
    topic = fork.heads.create("topic", fork.heads.find("master").target_oid, fork.owner)
    topic.append_commit(metadata, fork.owner) {}

    cross_repo_pull = PullRequest.create_for!(source,
      title: "blah",
      body: "blah",
      base: "#{source.owner}:master",
      head: "#{fork.owner}:topic",
      user: fork.owner)

    refute source.rpc.object_exists?(cross_repo_pull.head_sha, "commit")

    non_existent_owner(source)
    perform_enqueued_hydro_jobs(only: [HydroDeletePullRequestRepositoryDeletedJob], allowed_primary_query_count: 32) do
      fork.remove(fork.owner, synchronous: true)
    end

    assert source.rpc.object_exists?(cross_repo_pull.head_sha, "commit")
  end

  test "archive is idempotent" do
    non_existent_owner(@public)
    5.times { @public.remove(@public.owner, synchronous: true) }
  end

  test "archive works after a quorum of replicas have been removed" do
    # Delete all but one replica from disk.
    _, *routes_to_delete = @public.dgit_all_routes
    system "rm", "-rf", *(routes_to_delete.map(&:path))

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
      non_existent_owner(@public)
      @public.remove(@public.owner, synchronous: true)
    end
  end

  test "archive works when a quorum of replicas are unhealthy" do
    # Delete all but one replica from disk.
    _, *routes_to_break = @public.dgit_all_routes
    routes_to_break.each do |route|
      ::DGit.set_repo_replica_checksum_for_host(@public.network_id, "creating", route.original_host, repo_id: @public.id, repo_type: GitHub::DGit::RepoType::REPO)
    end

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
      non_existent_owner(@public)
      @public.remove(@public.owner, synchronous: true)
    end
  end

  test "archive works after a quorum of wiki replicas have been removed" do
    # Delete all but one replica from disk.
    _, *routes_to_delete = @public.dgit_wiki_write_routes
    system "rm", "-rf", *(routes_to_delete.map(&:path)) or fail

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
      non_existent_owner(@public)
      @public.remove(@public.owner, synchronous: true)
    end
  end

  test "archive works when a quorum of wiki replicas are unhealthy" do
    # Delete all but one replica from disk.
    _, *routes_to_break = @public.dgit_wiki_write_routes
    routes_to_break.each do |route|
      ::DGit.set_repo_replica_checksum_for_host(@public.network_id, "creating", route.original_host, repo_id: @public.id, repo_type: GitHub::DGit::RepoType::WIKI)
    end

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
      non_existent_owner(@public)
      @public.remove(@public.owner, synchronous: true)
    end
  end
end
