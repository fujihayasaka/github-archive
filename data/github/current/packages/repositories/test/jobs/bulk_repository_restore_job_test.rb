# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkRepositoryRestoreJobTest < GitHub::TestCase
  include HydroTestHelpers
  fixtures do
    @user = create(:user)
    @staff = create :staff_admin_user
  end

  setup do
    repo = create :repository, owner: @user
    repo2 = create :repository, owner: @user

    repo.remove(@user)
    repo2.remove(@user)
    @archived = Repositories::Public.find_deleted(repo.id)
    @archived2 = Repositories::Public.find_deleted(repo2.id)

    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")

    # We don't actually have the repo in backup, so we copy it from the sample
    # repository. We take over the client-side because it's harder to figure out
    # which path is the current one if we take over the client-side.
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
  end

  test "restores multiple repositories" do
    GitHub.context.push(from: "stafftools/purgatory#restore_bulk")
    events = subscribe "staff.repo_restore"
    Repositories::JobStatus.create(id: BulkRepositoryRestoreJob.job_id([@archived.id, @archived2.id]))
    perform_enqueued_jobs(only: [BulkRepositoryRestoreJob, RepositoryOrchestrationJob]) do
      BulkRepositoryRestoreJob.perform_later([@archived.id, @archived2.id], @staff.id)
    end

    assert Repositories::Public.find_active!(@archived.id)
    assert Repositories::Public.find_active!(@archived2.id)
    assert Repositories::JobStatus.find(BulkRepositoryRestoreJob.job_id([@archived.id]))
    assert Repositories::JobStatus.find(BulkRepositoryRestoreJob.job_id([@archived2.id]))
    assert_equal events.length, 2
    assert_equal @archived2.id, events.pop.payload[:repo_id]
    assert_equal @archived.id, events.pop.payload[:repo_id]
  end

  test "enqueues a hydro message for each restore", skip_enterprise: true do
    Repositories::JobStatus.create(id: BulkRepositoryRestoreJob.job_id([@archived.id, @archived2.id]))
    perform_enqueued_jobs(only: [BulkRepositoryRestoreJob, RepositoryOrchestrationJob]) do
      BulkRepositoryRestoreJob.perform_later([@archived.id, @archived2.id], @staff.id)
    end

    repo = Repository.where(name: @archived.name).first
    repo2 = Repository.where(name: @archived2.name).first
    assert_hydro_messages(count: 2, schema: "github.v1.RepositoryRestored")
  end
end
