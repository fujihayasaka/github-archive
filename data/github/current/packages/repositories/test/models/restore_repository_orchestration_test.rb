# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RestoreRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @actor = create(:user)

    repo = create :repository, owner: @user
    repo.initialize_wiki(repo.owner)
    example_repo :wiki, repo.unsullied_wiki
    issue = create :issue, repository: repo, user: @user

    repo.remove(@user, synchronous: true)
    @deleted = repo

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")
    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:wiki_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/wiki.git")

    # We don't actually have the repo in backup, so we copy it from the sample
    # repository. We take over the client-side because it's harder to figure out
    # which path is the current one if we take over the client-side.
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end

    RepositoryAuthVersion.delete_all
  end

  def restore(repo, actor)
    orchestration = RepositoryOrchestration.restore(repo, actor: actor)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, RepositoryUpdateLanguageStatsJob]) do
      orchestration.execute(synchronous: false) # don't wait for the job to finish
    end
    orchestration
  end

  def get_restore_status(repo)
    Restoration::RepositoryRestoreStatus.for(repository_id: repo.id)
  end

  test "returns nil if a key value has been set for this job" do
    RestoreRepositoryOrchestration.create(repository_id: @deleted.id, state: :running)

    o = restore(@deleted, @actor)

    assert_includes o.errors.first.message, "orchestration in progress"
  end

  test "restores repository" do
    Repository.any_instance.stubs(:language_size_analysis).returns({ "Java" => 1000 })
    Repository.any_instance.stubs(:default_oid).returns("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    job_status = get_restore_status(@deleted)
    refute job_status.message

    assert restore(@deleted, @actor), job_status.message

    assert_equal "Done!", job_status.message

    repo = Repositories::Public.find_active!(@deleted.id)
    assert repo
    assert_equal "Done!", job_status.message
    assert_equal "Java", repo.primary_language.name
  end

  test "cannot restore repository that exists" do
    repo = create :repository, owner: @user

    o = restore(repo, @actor)

    assert_equal "Repository already restored.", o.errors.first.message
  end

  test "cannot restore repository with the same name as an existing repository" do
    repo = create :repository, owner: @user, name: @deleted.name

    o = restore(@deleted, @actor)

    assert_equal "Repository already exists on this account.", o.errors.first.message
  end

  test "cannot restore repository where conflicting fork exists" do
    parent = create(:repository, from_example: :simple)

    forked, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { parent.fork forker: @user }
    forked.remove(@user, synchronous: true)

    refute get_restore_status(forked).message

    repo, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { parent.fork forker: @user }
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.rename "my-new-fork", actor: @user }

    o = restore(forked, @actor)

    assert_equal "This account has an existing fork in the deleted repository's network.",
      o.errors.first.message
  end

  test "can restore intra-org repository where existing fork exists" do
    org_admin = create(:user, login: "org-admin")
    org = create(:organization, admin: org_admin, plan: "bronze", business: GitHub.global_business)
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create :repository, owner: org
    fork1, result = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { repo.fork(forker: org_admin, org: org) }
    assert_equal :created, result
    fork1.remove(@org_admin, synchronous: true)

    restore(fork1, org_admin)

    assert_equal "Done!", get_restore_status(fork1).message
  end

  test "cannot restore repository without archive" do
    refute get_restore_status(@deleted).message
    @deleted.destroy

    o = restore(@deleted, @actor)

    assert_equal "Repository does not exist", o.errors.first.message
  end

  test "does not reset message if not finished" do
    restore(@deleted, @actor)

    job_status = get_restore_status(@deleted)
    job_status.message = "booya...?"

    refute job_status.reset_message_if_finished
    assert_equal "booya...?", job_status.message
  end

  test "resets message and returns default when finished" do
    restore(@deleted, @actor)
    job_status = get_restore_status(@deleted)
    job_status.message = "booya!"

    assert job_status.reset_message_if_finished
    assert job_status.message.nil?
  end

  test "uses write db to reset message" do
    restore(@deleted, @actor)
    job_status = get_restore_status(@deleted)
    job_status.message = "booya!"

    ActiveRecord::Base.expects(:connected_to).with(role: :writing).once.returns({})

    assert job_status.reset_message_if_finished
  end

  test "status when unlocked" do
    assert_equal :ok, get_restore_status(@deleted).status
  end

  test "status when locked" do
    RestoreRepositoryOrchestration.any_instance.stubs(:succeeded?).returns(false)

    restore(@deleted, @actor)

    assert_equal :accepted, get_restore_status(@deleted).status
  end

  test "status after performing the job" do
    restore(@deleted, @actor)

    assert_equal :ok, get_restore_status(@deleted).status
  end

  test "message after performing the job" do
    restore(@deleted, @actor)

    assert_equal Restoration::RepositoryRestoreStatus::COMPLETED_MESSAGE, get_restore_status(@deleted).message
  end

  context "default message" do
    test "without Repository" do
      job_status = get_restore_status(Repository.new(id: 9999999))
      assert_equal Restoration::RepositoryRestoreStatus::MISSING_REPOSITORY_MESSAGE, job_status.default_message
    end

    test "with repository" do
      repo = create :repository, owner: @user
      repo.remove(@user, synchronous: true)

      restore(repo, @user)

      assert_equal Restoration::RepositoryRestoreStatus::COMPLETED_MESSAGE, get_restore_status(repo).default_message
    end
  end

  context "status messages" do
    test "started" do
      GitHub.context.push(from: "repos/restore#restore")

      orchestration = RepositoryOrchestration.restore(@deleted, actor: @actor)
      orchestration.execute(synchronous: false) # don't wait for the job to finish

      assert_equal "Queued...", get_restore_status(@deleted).message
    end

    test "repo already restored" do
      GitHub.context.push(from: "repos/restore#restore")
      repo = create :repository, owner: @user

      o = restore(repo, @actor)

      assert_equal "Repository already restored.",  o.errors.first.message
    end

    test "repo already exists" do
      GitHub.context.push(from: "repos/restore#restore")
      repo = create :repository, owner: @user, name: @deleted.name

      o = restore(@deleted, @actor)

      assert_equal "Repository already exists on this account.", o.errors.first.message
    end

    test "existing fork" do
      GitHub.context.push(from: "repos/restore#restore")

      parent = create :repository, owner: @actor
      fork1  = create :repository, owner: @user, parent: parent, name: "fork1"
      fork1.remove(@user, synchronous: true)
      fork2 = create :repository, owner: @user, parent: parent, name: "fork2"

      o = restore(fork1, @user)

      assert_equal "This account has an existing fork in the deleted repository's network.", o.errors.first.message
    end

    test "unhandled exception failure" do
      GitHub.context.push(from: "repos/restore#restore")

      Repository.any_instance.stubs(:unhide).raises(StandardError)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob, RepositoryUpdateLanguageStatsJob]) do
        assert_raises(StandardError) do
          Repository.restore(@deleted.id, actor: @actor, synchronous: false)
        end
      end

      assert_equal Restoration::RepositoryRestoreStatus::FAILED_MESSAGE, get_restore_status(@deleted).message
    end

    test "exhausted retries failure" do
      GitHub.context.push(from: "repos/restore#restore")

      Repository.any_instance.stubs(:unhide).raises(ActiveRecord::RecordNotFound)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob, RepositoryUpdateLanguageStatsJob]) do
        Repository.restore(@deleted.id, actor: @actor, synchronous: false)
      end

      assert_equal Restoration::RepositoryRestoreStatus::FAILED_MESSAGE, get_restore_status(@deleted).message
    end
  end

  context "validation" do
    test "fails if the repository is not restorable" do
      repo = create(:repository, owner: @user)
      repo.restorable = false
      repo.save!

      repo.remove(@user, synchronous: true)
      o = restore(repo, @user)

      assert_includes o.errors.first.message, "not restorable"
    end

    test "succeeds if the repository is not restorable but override is submitted" do
      repo = create(:repository, owner: @user)
      repo.restorable = false
      repo.save!

      repo.remove(@user, synchronous: true)

      orchestration = RepositoryOrchestration.restore(repo, actor: @user, override_restorable: true)
      # If this doesn't throw, our override worked!
      orchestration.execute(synchronous: true)
    end
  end

  test "publishes Restored event" do
    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      message = {
        repository_id: @deleted.id,
        request_id: nil,
        actor_id: @actor.id,
        deleted_at: @deleted.deleted_at
      }

      restore(@deleted, @actor)

      assert_hydro_published(message, schema: "github.repositories.v2.Restored")
      assert_hydro_messages(count: 1, schema: "github.repositories.v2.Restored")
    end
  end

  test "does not enqueue search indexing job" do
    assert_enqueued_jobs 0, only: RemoveFromSearchIndexJob do
      orchestration = RepositoryOrchestration.restore(@deleted, actor: @actor)
      orchestration.execute(synchronous: true)
    end
  end

  # Prevent the user from renaming while restoration is in progress
  # https://github.com/github/search-and-flywheel/issues/233
  test "acquires lock for retired namespace" do
    Repositories::RepositoryOwnerLock.expects(:acquire_rename_lock).with(owner_id: @deleted.owner_id).once.returns(true)
    Repositories::RepositoryOwnerLock.expects(:release_rename_lock).with(owner_id: @deleted.owner_id).once

    orchestration = RepositoryOrchestration.restore(@deleted, actor: @actor)
    orchestration.execute(synchronous: true)
    refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @deleted.owner_id)
  end

  # Tests rollback for the outer transaction in the RestoreRepositoryOrchestration :unhide_repo step
  test "failed restore rolls back changes" do
    example_repo :simple, @deleted
    @deleted.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    @deleted.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    refute_predicate @deleted, :active?

    o = RepositoryOrchestration.restore(@deleted, actor: @actor)
    assert_raises StandardError do
      o.execute(synchronous: true)
    end

    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "unhide_repo", o.step_name

    @deleted.reload
    refute_predicate @deleted, :active?
    assert_equal 42, @deleted.auth_version
  end

  # Tests rollback for the inner transaction in Repository::RestoreDependency#unhide
  test "failed unhide rolls back changes" do
    example_repo :simple, @deleted
    @deleted.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Mock a failure during Repository#unhide after the hidden status is updated in the DB
    @deleted.stubs(:save!).raises(StandardError.new("boom"))

    refute_predicate @deleted, :active?

    o = RepositoryOrchestration.restore(@deleted, actor: @actor)
    assert_raises StandardError do
      o.execute(synchronous: true)
    end

    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "unhide_repo", o.step_name

    @deleted.reload
    refute_predicate @deleted, :active?
    assert_equal 42, @deleted.auth_version
  end

  test "increments the repository_auth_version", skip_enterprise: true do
    example_repo :simple, @deleted
    @deleted.create_repository_auth_version(version: 42)

    GitHub.flipper[:geyser_denylist].disable

    # Freeze time so the hydro event timestamps match
    Timecop.freeze do
      RepositoryOrchestration.restore(@deleted, actor: @actor).execute(synchronous: true)
      @deleted.reload

      assert_equal 43, @deleted.auth_version

      assert_hydro_published({
        change: :RESTORED,
        repository: Hydro::EntitySerializer.repository(@deleted),
        auth_version: 43,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end
  end
end
