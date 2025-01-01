# typed: true
# frozen_string_literal: true

require "test_helper"

# This test case is for the in app (not background job) portion of the remove
# process. The repositories records are marked deleted = 1 and all remaining
# child forks reparented to maintain network consistency.
#
# See the separate archive and purge test case below for archiving
# and git repository on disk tests.
class RepositoryRemoveHideStageTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @priv_user = create :user, plan: "medium"
    @pub_user = create :user, plan: "medium"
    @user = create(:user)

    @private = create(:private_repository, owner: @priv_user, from_example: :simple)
    @private.add_member @pub_user
    @private.add_member @user
    @priv_fork = create(:fork_repository, forker: @pub_user,  fork_repo: @private)

    @public = create(:repository, owner: @pub_user, from_example: :simple)
    @pub_fork = create(:fork_repository, forker: @priv_user, fork_repo: @public)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "unsets active flag" do
    @public.remove(@pub_user)

    refute @public.active?
  end

  test "allows same-name repo to be created" do
    @public.remove(@pub_user)

    repo = create(:repository, name: @public.name, owner: @public.owner)
    assert repo.valid?
  end

  test "sets deleted_by_user_id and deleted_at attributes" do
    @public.remove(@pub_user)
    assert_equal @pub_user.id, @public.deleted_by_user_id
    assert @public.deleted_at.is_a?(Time)

    record = Repository.find(@public.id)
    assert_equal @pub_user.id, record.deleted_by_user_id
    assert_equal @pub_user, record.deleted_by
    assert record.deleted_at.is_a?(Time)
  end

  test "elects new root when existing root removed" do
    @public.remove(@pub_user, synchronous: true)
    @pub_fork.reload
    assert @pub_fork.active?,        "bad cascading delete"
    assert @pub_fork.parent_id.nil?, "expected to be reparented to root"
  end

  if !GitHub.enterprise?
    test "emits a repository deleted event upon public repo removal for search indexing" do
      repo = create :repository, owner: @pub_user
      assert repo.active?
      repo.remove(@pub_user, synchronous: true)

      refute repo.active?
      assert_equal @pub_user.id, repo.deleted_by_user_id

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(repo),
        ref: "refs/heads/#{repo.default_branch}",
        owner_name: repo.owner.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end

    test "emits a repository deleted event upon private repo removal for search indexing" do
      assert @private.active?

      # @private is the network root, so deleting it will also delete the child fork @priv_fork
      # that happens on a background job so make sure it runs
      @private.remove(@priv_user, synchronous: true)

      refute @private.active?
      assert_equal @priv_user.id, @private.deleted_by_user_id

      assert_hydro_messages(count: 2, schema: "github.search.v0.RepositoryChanged")

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(@private),
        ref: "refs/heads/#{@private.default_branch}",
        owner_name: @private.owner.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      @priv_fork.reload

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(@priv_fork),
        ref: "refs/heads/#{@priv_fork.default_branch}",
        owner_name: @priv_fork.owner.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)
    end
  end

  test "reparents remaining forks under remaining parent" do
    user2 = create(:user)
    fork2 = create(:fork_repository, forker: user2, fork_repo: @pub_fork)

    user3 = create(:user)
    fork3 = create(:fork_repository, forker: user3, fork_repo: @public)

    @pub_fork.remove(user3, synchronous: true)
    fork2.reload
    fork3.reload
    assert_equal @public, fork2.parent
    assert_equal @public, fork3.parent
  end

  test "updates organization on reparented forks" do

    parent_org = create(:organization)
    parent_org.allow_private_repository_forking(actor: parent_org.admins.first)
    parent_team = create :team, organization: parent_org
    root_repo = create(:private_repository, owner: parent_org)
    assert parent_team.add_repository(root_repo, :pull).success?
    assert parent_team.add_member(@user).success?

    middle_org = create(:organization)
    middle_org.allow_private_repository_forking(actor: middle_org.admins.first)
    middle_team = create(:team, organization: middle_org, permission: "admin")
    assert middle_team.add_member(@user).success?

    middle_fork, status = root_repo.fork(forker: @user, org: middle_org)
    assert_equal :created, status
    assert middle_team.add_repository(middle_fork, :admin).success?

    user_fork, status = middle_fork.fork(forker: @user)
    assert_equal :created, status

    # sanity check:
    assert_equal middle_org.id, user_fork.organization_id

    # now, delete the middle repo:
    middle_fork.remove(@user, synchronous: true)

    user_fork.reload
    assert_equal root_repo.id, user_fork.parent_id, "should be reparented"
    assert_equal parent_org.id, user_fork.organization_id
  end

  test "reparents remaining forks under newly elected root" do
    user2 = create(:user)
    fork2 = create(:fork_repository, forker: user2, fork_repo: @pub_fork)

    user3 = create(:user)
    fork3 = create(:fork_repository, forker: user3, fork_repo: @public)

    user4 = create(:user)
    fork4 = create(:fork_repository, forker: user4, fork_repo: fork2)

    @public.remove(@pub_user, synchronous: true)

    @pub_fork.reload
    assert_nil @pub_fork.parent

    [fork2, fork3, fork4].each(&:reload)
    assert_equal @pub_fork, fork3.parent
    assert_equal @pub_fork, fork2.parent
    assert_equal fork2, fork4.parent
  end

  test "cascades to all same plan private forks when plan owner repo removed" do
    user2 = create(:user, plan: "medium")
    @priv_fork.add_member user2
    other_fork = create(:fork_repository, forker: @user, fork_repo: @private)

    fork2 = create(:fork_repository, forker: user2, fork_repo: @priv_fork)

    user3 = create(:user, plan: "medium")
    fork2.add_member user3
    fork3 = create(:fork_repository, forker: user3, fork_repo: fork2)
    forks = [@private, @priv_fork, fork2, fork3, other_fork]

    @private.remove(@priv_user, synchronous: true)

    forks.each do |repo|
      repo.reload
      refute repo.active?, "private dependent #{repo} should be deleted"
    end
  end

  test "does not cascade to same plan private forks when fork is deleted" do
    user2 = create(:user, plan: "medium")
    @priv_fork.add_member user2
    fork2 = create(:fork_repository, forker: user2, fork_repo: @priv_fork)

    @priv_fork.remove(user2, synchronous: true)
    refute @priv_fork.active?

    @private.reload
    assert @private.active?
    assert_nil @private.parent_id

    fork2.reload
    assert fork2.active?
    assert_equal @private, fork2.parent
  end

  test "promotes fork to root but not change the network" do
    assert_equal @public.id, @pub_fork.parent_id
    assert_equal @public.network_id, @pub_fork.network_id

    @public.remove(@pub_user, synchronous: true)

    @pub_fork = Repository.find(@pub_fork.id)
    assert_nil                 @pub_fork.parent_id
    assert_equal @pub_fork,    @pub_fork.root, "root was #{@public.inspect}"
    assert_equal @public.network_id,   @pub_fork.network_id
    assert_equal @pub_fork,    @pub_fork.network.root
  end

  test "deleting private root with public forks reparents public forks" do
    @private.add_member(@user)
    repo = create(:fork_repository, forker: @user, fork_repo: @private)
    repo.toggle_visibility(actor: @user)
    assert repo.public?
    @private.remove(@priv_user, synchronous: true)

    repo.reload
    assert_equal 1, repo.network_repositories.count
    assert_nil repo.parent_id
  end

  test "unlocks private repos if there's room in the plan now" do
    (5 - @priv_user.owned_private_repositories.count).times do
      create(:private_repository, owner: @priv_user)
    end
    repo = @priv_user.repositories.last
    repo.lock_for_billing
    assert repo.locked_on_billing?

    @priv_user.update_attribute(:plan, "micro")
    @private.remove(@priv_user, synchronous: true)

    refute repo.reload.locked_on_billing?
  end
end

class RepositoryRemoveWithAnInstallationTest < GitHub::TestCase
  include RepositoriesTestHelper
  include HydroMessageJobTestHelpers

  fixtures do
    @user  = create :user, plan: "medium"
    @repo1 = create :repository, owner: @user
    @repo2 = create :repository, owner: @user
  end

  test "queues an IntegrationInstallationRepositoryRemovalJob" do
    installation = make_integration_installation(
      target: @user,
      repository: @repo1,
      permissions: { "metadata" => :read },
    )

    events = subscribe "integration_installation.repositories_removed"

    assert_enqueued_jobs(1, only: IntegrationInstallationRepositoryRemovalJob) do
      perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 27) do
        @repo1.remove(@user, synchronous: true)
      end
    end

    # Assert only one event was emitted.
    assert event = events.pop, "expected event to be present"
    assert_empty events
    assert_equal installation.id, event.payload[:installation_id]
    assert_equal [@repo1.id], event.payload[:repositories_removed]
    assert_equal [@repo1.full_name], event.payload[:repositories_removed_names]
    assert_equal @user.login, event.payload[:actor]
  end
end

# Test case for the background portion of the removal process. Checks that
# repository records are archived and removed entirely and that git data is
# cleaned up properly.
class RepositoryRemoveArchiveAndPurgeStageTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

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

    # all_repos = [@private, @public, @pub_fork, @priv_fork]
    # all_repos.push *all_repos.map(&:unsullied_wiki)
    example_repo(:simple, @public.unsullied_wiki)
    example_repo(:simple, @private.unsullied_wiki)
    example_repo(:simple, @pub_fork.unsullied_wiki)
    example_repo(:simple, @priv_fork.unsullied_wiki)

    example_repo_snapshot

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
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

  test "records deleted_by and deleted_at on archive record" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    @public.remove(@pub_user, synchronous: true)
    archived = Repositories::Public.find_deleted!(@public.id)
    assert_equal @pub_user.id, archived.deleted_by_user_id
    assert_equal @pub_user, archived.deleted_by
    assert archived.deleted_at.is_a?(Time)
  end

  test "does not remove individual repo from disk" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    paths = DGit.paths_for_repo(@public)
    @public.remove(@pub_user, synchronous: true)

    assert_nil  Repositories::Public.find_active(@public.id)
    paths.each do |shard_path|
      assert File.exist?(shard_path), "#{shard_path} should exist"
    end
  end

  test "destroys the network record when no repositories remain" do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    assert network = @public.network

    @public.remove(@pub_user, synchronous: true)
    assert RepositoryNetwork.exists?(network.id)

    @pub_fork = Repository.find(@pub_fork.id)
    @pub_fork.remove(@priv_user, synchronous: true)

    # the network of soft-deleted forks is not destroyed until all the repos in the network are purged
    assert RepositoryNetwork.exists?(network.id)
    @public.purge(synchronous: true)
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

    @private.remove(@priv_user, synchronous: true)

    assert_nil Repositories::Public.find_active(@private.id)
    assert_nil Repositories::Public.find_active(@priv_fork.id)
    assert_nil Repositories::Public.find_active(priv_fork2.id)
    assert_nil Repositories::Public.find_active(priv_fork3.id)
    assert_nil Repositories::Public.find_active(other_fork.id)

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

    fork_path   = fork.shard_path
    assert File.exist?(fork_path)

    fork_2, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      fork.fork(forker: other_user)
    end

    fork_2_path = fork_2.shard_path
    assert File.exist?(fork_2_path)

    fork.remove(@user, synchronous: true)

    assert File.exist?(fork_path)

    assert  Repositories::Public.find_active(@private.id)
    assert !Repositories::Public.find_active(fork.id)

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
    org.allow_private_repository_forking(actor: admin, policy: Configurable::AllowPrivateRepositoryForking::LEGACY_ENABLED)
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

    internal_repo.remove(admin, synchronous: true)

    refute Repositories::Public.find_active(fork.id)
    refute Repositories::Public.find_active(fork_of_fork.id)
  end

  test "deletes commit contributions when destroyed" do
    repo = create(:deleted_repository)
    committers = Array.new(3) { create(:user) }
    3.times do |i|
      committers.each do |user|
        create :commit_contribution,
          repository: repo,
          user: user,
          committed_date: i.days.ago.to_date
      end
    end

    assert_difference("CommitContribution.count", -9) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  context "delete statuses" do
    test "when destroyed" do
      repo = create(:deleted_repository)
      reset_repo_root
      example_repo :mojombo_grit, repo

      3.times { create :status, repository: repo }
      assert_difference("Status.where(repository_id: #{repo.id}).count", -3) do
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          repo.purge(synchronous: true)
        end
      end
    end

    test "in the background" do
      repo = create(:deleted_repository)
      reset_repo_root
      example_repo :mojombo_grit, repo

      status = create :status, repository: repo

      args = ["Repository", repo.id, :statuses, { sharding_key: :repository_id, sharding_value: repo.id, inverse_relationship: false }]
      assert_enqueued_with job: DeleteDependentRecordsJob, args: args do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes milestones when destroyed" do
    repo = create(:repository, owner: @user)
    milestone = create(
      :milestone,
      repository: repo,
      created_by: repo.owner,
      due_on: Time.now + 1.month,
      title: "The Milestone"
    )

    repo.remove(repo.owner, synchronous: true)

    assert_difference("Milestone.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes pull requests when destroyed" do
    make_pull_request

    @repo.remove(@repo.owner, synchronous: true)

    assert_difference("PullRequest.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes commit comments when destroyed" do
    repo = create(:deleted_repository)
    example_repo :simple, repo

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
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes commit mentions when destroyed" do
    repo = create(:deleted_repository)
    example_repo :pull_request_source, repo

    sha = repo.heads.find("master").target_oid
    create :commit_mention, repository: repo, commit_id: sha

    assert_difference("CommitMention.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys releases in the background when destroyed" do
    repo = create(:deleted_repository)
    example_repo :repository_test_simple, repo
    create :release, repository: repo, tag_name: "v1",
      author: repo.owner, state: :published, created_at: 1.month.ago,
      body: "*version 1*"

    assert_difference("Release.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
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
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.purge(synchronous: true) }
    end
  end

  test "destroys check suites in the background when soft-deleted" do
    repo = create(:repository)
    create(:check_suite, repository: repo)

    assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.remove(repo.owner, synchronous: true)
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys environments in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:environment, repository: repo)

    assert_difference("Environment.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys projects in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:project, owner: repo)

    assert_difference("Project.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys public keys in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:public_key, repository: repo, verifier: repo.owner)

    assert_difference("PublicKey.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository vulnerability alerts in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:repository_vulnerability_alert, repository: repo)

    assert_difference "RepositoryVulnerabilityAlert.count", -1 do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys repository rulesets in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:repository_ruleset, :targets_all_branches, source: repo)

    assert_difference("RepositoryRuleset.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys tabs in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:tab, anchor: "Removed", repository: repo)

    assert_difference("Tab.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "destroys workflows in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:workflow, repository: repo, name: "CI", path: ".github/workflows/ci.yml")

    assert_difference("Actions::Workflow.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes labels in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:label, repository: repo, name: "foobar")

    assert_difference("Label.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes repository redirects in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:repository_redirect, repository: repo, repository_name: "org/repo")

    assert_difference("RepositoryRedirect.count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
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
        repo.purge(synchronous: true)
      end
    end
  end

  test "deletes key links in the background when destroyed" do
    repo = create(:deleted_repository)
    create(:key_link, owner: repo, key_prefix: "foo")

    assert_difference("KeyLink.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  # NOTE: If you're here because this test failed and you've added a destroy_dependents_in_background to Repository,
  # don't do that! Use `destroy_in_background_with` instead.
  test "expected destroy/delete job counts" do
    repo = create(:deleted_repository)

    assert_enqueued_jobs 8, only: DeleteDependentRecordsJob do
      assert_enqueued_jobs 27, only: DestroyDependentRecordsJob do
        repo.purge(synchronous: true)
      end
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

    perform_enqueued_hydro_jobs(only: [HydroDeletePullRequestRepositoryDeletedJob],
      allowed_primary_query_count: 33) do
      fork.remove(fork.owner, synchronous: true)
    end

    assert source.rpc.object_exists?(cross_repo_pull.head_sha, "commit")
  end

  test "archive is idempotent" do
    5.times { @public.remove(@public.owner, synchronous: true) }
  end

  test "archive works after a quorum of replicas have been removed" do
    # Delete all but one replica from disk.
    _, *routes_to_delete = @public.dgit_all_routes
    routes = routes_to_delete.map(&:path)
    assert routes.size == 2, "expected 2 routes"
    system "rm", "-rf", routes.first, routes.second

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
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
      @public.remove(@public.owner, synchronous: true)
    end
  end

  test "archive works after a quorum of wiki replicas have been removed" do
    # Delete all but one replica from disk.
    _, *routes_to_delete = @public.dgit_wiki_write_routes
    routes = routes_to_delete.map(&:path)
    assert routes.size == 2, "expected 2 routes"
    system "rm", "-rf", routes.first, routes.second or fail

    assert_no_enqueued_jobs queue: "dgit_repairs" do
      # also, this shouldn't raise an error
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
      @public.remove(@public.owner, synchronous: true)
    end
  end
end
