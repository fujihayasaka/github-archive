# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryRestoreTest < GitHub::TestCase
  include HydroTestHelpers
  fixtures do
    @user   = create(:user, plan: "micro")
    @forker = create(:user)
    @deep_forker = create(:user)
    @org = create(:organization, admin: @user)

    @no_fork_repo = create :repository, owner: @user
    @repo = create :repository, owner: @user
    @org_repo = create :repository, owner: @org
    @private_repo = create :private_repository, owner: @user
    @fork = create :repository, owner: @forker, parent: @repo
    @deep_fork = create :repository, owner: @deep_forker, parent: @fork

    @issue = create :issue, repository: @repo, user: @user
    @org_issue = create :issue, repository: @org_repo, user: @user

    @gist = create(:gist, owner: @user)

    # ensure that @repo gets a wiki
    @repo.initialize_wiki(@user)
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    reset_repo_root
    example_repo :simple, @no_fork_repo
    example_repo :simple, @repo, @private_repo, @fork, @deep_fork
    example_repo :wiki, @repo.unsullied_wiki

    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")
    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:wiki_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/wiki.git")

    # We don't actually have the repo in backup, so we copy it from the sample
    # repository. We take over the client-side because it's harder to figure out
    # which path is the current one if we take over the client-side.
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
  end

  test "restores repositories record with same id" do
    @repo.remove(@user)
    restored_record = nil

    restored_record = Repository.restore(@repo.id)
    assert restored_record
    assert restored_record.active?
    assert_equal @repo.id, restored_record.id
  end

  test "restores associated records and creates git repository" do
    @repo.remove(@user)
    assert @repo.deleted?
    restored_record = Repository.restore(@repo.id)
    assert restored_record
    assert restored_record.active?
    assert Issue.exists?(@issue.id)
    assert restored_record.exists_on_disk?
  end

  test "restores repository with synchronized filesystem/database visibility" do
    assert @repo.public?
    @repo.remove(@user)

    restored_record = Repository.restore(@repo.id)
    assert restored_record
    assert restored_record.public?
  end

  test "reindexes all search indexes for restored repository" do
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    # Other stuff gets indexed, especially in the Rails 4 tests, so set up a
    # blank assertion since we don't care if other stuff gets indexed
    Search.expects(:add_to_search_index).at_least_once
    Search.expects(:add_to_search_index).with("repository", @repo.id)
    Search.expects(:add_to_search_index).with("commit", @repo.id, "purge" => true)

    if GitHub.use_elastomer_code_search?
      Search.expects(:add_to_search_index).with("code", @repo.id, "purge" => true)
    end

    # FIXME: It'd be great to assert that the below indexes also get re-built, but
    # the above `at_least_once` assertion above fails if all of these expectations
    # are checked and `add_to_search_index` is not called at least one additional
    # time. Because Repository, Code, and Commit search indexes are the most
    # important ones, we're just asserting those three for now.
    #
    # Search.expects(:add_to_search_index).with("bulk_issues", @repo.id, "purge" => true)
    # Search.expects(:add_to_search_index).with("bulk_projects", @repo.id, "purge" => true)
    # Search.expects(:add_to_search_index).with("bulk_pull_requests", @repo.id, "purge" => true)

    Repository.restore(@repo.id)
  end

  unless GitHub.use_elastomer_code_search?
    test "does not enqueue legacy code index outside of GHES" do
      @repo.remove(@user)
      assert_nil Repositories::Public.find_active(@repo.id)

      Search.stubs(:add_to_search_index)
      Search.expects(:add_to_search_index).with do |type, repo_id, _options|
        refute type == "code" && repo_id == @repo.id
      end

      Repository.restore(@repo.id)
    end
  end

  test "restores private repository with synchronized filesystem/database visibility" do
    @private_repo.remove(@user)

    restored_record = Repository.restore(@private_repo.id)
    assert restored_record
    assert restored_record.private?
  end

  test "ensures repository sequence is archived and restored" do
    3.times { create :issue, repository: @repo }
    issue = create :issue, repository: @repo

    refute_nil @repo.reload.repository_sequence
    assert Sequence.exists?(@repo), "sequence expected"

    @repo.remove(@user)

    restored_repo = Repository.restore(@repo.id)
    assert_equal @repo.id, restored_repo.id
    assert Repositories::Public.find_active(restored_repo.id)

    refute_nil restored_repo.repository_sequence
    assert_equal issue.number, restored_repo.repository_sequence.number
    assert Sequence.exists?(restored_repo), "sequence expected"
    assert_equal issue.number, Sequence.get(restored_repo)
  end

  test "restore re-establishes network on restored record" do
    old_network = RepositoryNetwork.find(@repo.network_id)
    @repo.remove(@user)
    assert @repo.deleted?

    Repository.restore(@repo.id)
    @repo = Repositories::Public.find_active(@repo.id)

    assert @repo.reload.network
    assert_equal old_network, @repo.network
  end

  test "uses existing parent if it exists" do
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @fork.remove(@forker)
    end
    assert @fork.deleted?

    restored_record = Repository.restore(@fork.id)
    assert restored_record.active?

    assert_equal @fork.id, restored_record.id
    assert_equal @repo.id, restored_record.parent_id

    @deep_fork.reload
    assert_equal @repo.id, @deep_fork.parent_id
  end

  test "adjusts parent to new root if old parent doesn't exist" do
    @deep_fork.remove(@deep_forker)
    assert @deep_fork.deleted?

    @fork.remove(@forker)
    assert @fork.deleted?

    restored_record = Repository.restore(@deep_fork.id)
    assert Repositories::Public.find_active(@deep_fork.id)

    assert_equal @deep_fork.id, restored_record.id
    assert_equal @repo.id, restored_record.parent_id
  end

  test "makes repo root if network no longer exists" do
    @deep_fork.remove(@deep_forker)
    assert Repositories::Public.is_deleted?(@deep_fork.id)

    @fork.remove(@forker)
    assert Repositories::Public.is_deleted?(@fork.id)

    @repo.remove(@user)
    assert Repositories::Public.is_deleted?(@repo.id)

    restored_record = Repository.restore(@fork.id)
    assert Repositories::Public.is_active?(@fork.id)

    assert_equal @fork.id, restored_record.id
    assert_nil restored_record.parent_id
  end

  test "recreates network with original network_id" do
    network_id = @repo.network_id

    @deep_fork.remove(@deep_forker)
    @fork.remove(@forker)
    @repo.remove(@user)

    restored = Repository.restore(@repo.id)
    assert Repositories::Public.is_active?(@repo.id)

    assert_equal network_id, restored.network_id
    assert_equal network_id, restored.network.id
  end

  test "leaves unnetworked repositories in place on disk during archive/restore" do
    shard_path = @no_fork_repo.shard_path

    assert !@no_fork_repo.refs.empty?
    assert File.exist?(shard_path)
    @no_fork_repo.remove(@user)
    assert_nil Repositories::Public.find_active(@no_fork_repo.id)
    assert File.exist?(shard_path)

    restored_record = Repository.restore(@no_fork_repo.id)
    assert_equal @no_fork_repo.id, restored_record.id

    assert Repositories::Public.is_active?(@no_fork_repo.id)
    assert File.exist?(shard_path)

    assert !restored_record.refs.empty?
  end

  test "leaves networked repositories in place on disk during archive/restore" do
    shard_path = @repo.shard_path
    wiki_shard_path = @repo.unsullied_wiki.shard_path
    @repo.unsullied_wiki.rpc.init

    assert !@repo.refs.empty?
    assert File.exist?(shard_path)
    assert File.exist?(wiki_shard_path)
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)
    assert File.exist?(shard_path)
    assert File.exist?(wiki_shard_path)

    restored_record = Repository.restore(@repo.id)
    assert_equal @repo.id, restored_record.id

    assert Repositories::Public.is_active?(@repo.id)
    assert File.exist?(shard_path)
    assert File.exist?(wiki_shard_path)

    assert !restored_record.refs.empty?
  end

  test "enqueues a hydro message without actor on restore", skip_enterprise: true do
    name = @repo.name
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    Timecop.freeze do
      repo = Repository.restore(@repo.id)
      assert_hydro_published({
        restored_repository: Hydro::EntitySerializer.repository(repo),
        }, schema: "github.v1.RepositoryRestored")
      assert_hydro_messages(count: 1, schema: "github.v1.RepositoryRestored")
    end
  end

  test "enqueues a hydro message with actor on restore", skip_enterprise: true do
    name = @repo.name
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    Timecop.freeze do
      repo = Repository.restore(@repo.id, actor: @user)
      assert_hydro_published({
        restored_repository: Hydro::EntitySerializer.repository(repo),
        actor: Hydro::EntitySerializer.user(@user),
        }, schema: "github.v1.RepositoryRestored")
      assert_hydro_messages(count: 1, schema: "github.v1.RepositoryRestored")
    end
  end

  test "instruments user repository restore" do
    GitHub.context.push(from: "stafftools/purgatory#restore")
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    events = subscribe "staff.repo_restore"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @user.login,
        user_id: @user.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
      }
    else
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @user.login,
        user_id: @user.id,
      }
    end

    restored_record = Repository.restore(@repo.id)
    assert restored_record
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments org repository restore" do
    GitHub.context.push(from: "stafftools/purgatory#restore")
    # Required on GHE to fulfill Repository.restore below.
    if GitHub.enterprise?
      example_repo :simple, @org_repo
    end

    @org_repo.remove(@user)
    assert_nil Repositories::Public.find_active(@org_repo.id)

    events = subscribe "staff.repo_restore"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        repo: @org_repo.name_with_owner,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
      }
    else
      expected_payload = {
        repo: @org_repo.name_with_owner,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
      }
    end

    restored_record = Repository.restore(@org_repo.id)
    assert restored_record
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments restores without actor" do
    GitHub.context.push(from: "stafftools/purgatory#restore")
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    events = subscribe "staff.repo_restore"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @user.login,
        user_id: @user.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
      }
    else
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @user.login,
        user_id: @user.id,
      }
    end

    restored_record = Repository.restore(@repo.id)
    assert restored_record
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end


  test "instruments restores when an actor is provided" do
    GitHub.context.push(from: "stafftools/purgatory#restore")
    @repo.remove(@user)
    assert_nil Repositories::Public.find_active(@repo.id)

    events = subscribe "staff.repo_restore"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
        staff_actor: @user.login,
        staff_actor_id: @user.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
      }
    else
      expected_payload = {
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @repo.owner.login,
        user_id: @repo.owner_id,
        actor: @user.login,
        actor_id: @user.id,
      }
    end

    restored_record = Repository.restore(@repo.id, actor: @user)
    assert restored_record
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "restores admin permissions when restored into an org" do
    owner = create(:user)
    org = create :organization, admin: owner
    repo = create(:repository, owner: org, from_example: :simple)
    assert repo.adminable_by?(owner)

    repo.remove(@user)
    Repository.restore(repo.id)
    repo = Repositories::Public.find_active(repo.id)

    assert repo.adminable_by?(owner), "repo should still be adminable by owner"
  end

  test "successfully restores a fork when the parent and organization are gone" do
    owner = create(:user)
    collab = create(:user)
    org = create :organization, admin: owner, plan: "silver"
    org.allow_private_repository_forking(actor: owner)
    GitHub.context.push(actor_id: owner.id)
    repo = create(:private_repository, owner: org, from_example: :simple)

    team = create(:team, organization: org)
    team.add_member collab
    team.add_repository repo, :pull
    forked = create(:fork_repository, forker: collab, fork_repo: repo, from_example: :simple)

    assert forked.in_organization?

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      repo.remove(@user)
    end

    assert_nil Repositories::Public.find_active(forked.id)

    org.destroy

    restored = Repository.restore(forked.id)
    assert Repositories::Public.find_active(forked.id)
    assert_equal restored.owner, restored.plan_owner
    assert_nil restored.organization_id
  end

  test "repository_spec is correct" do
    assert_equal "#{@repo.network_id}/#{@repo.id}", @repo.repository_spec
    assert_equal "#{@repo.network_id}/#{@repo.id}.wiki", @repo.unsullied_wiki.repository_spec
    assert_equal "gist/#{@gist.repo_name}", @gist.repository_spec
  end

  test "if restore fails, it can be retried successfully" do
    Repository.any_instance.stubs(:organization_collaborator_cache_write?).returns(false)

    # First, archive the project
    @repo.remove(@user)

    # Take some method call that happens at the end of the restore process - and make it fail once, then succeed
    Repository.any_instance.stubs(:in_organization?).raises(StandardError.new).then.returns(false)

    assert_raises StandardError do
      Repository.restore(@repo.id)
    end

    # Archived repo should still exist
    # and partially restored repos should be hidden
    assert Repositories::Public.is_deleted?(@repo.id)

    restored_repo = Repository.restore(@repo.id)

    assert Repositories::Public.find_active(@repo.id)
    refute restored_repo.deleted?
  end
end
