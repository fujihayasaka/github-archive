# typed: true
# frozen_string_literal: true

# NOTE: This class and the MediaTransitionJobWithStorageClusterTest class
# should be kept in synchronization.  Any changes to this class should
# be mirrored in the MediaTransitionJobWithStorageClusterTest class as well.

require "test_helper"

class MediaTransitionJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  skip_with_all_emus

  fixtures do
    Media::Blob.network_copy_batch_size = 1
    Media::Blob.stub_copy!

    @owner = create :user, login: "owner", plan: "business_plus"
    @forker = create :user, login: "forker", plan: "large"
    @forker2 = create :user, login: "forker2", plan: "large"
    @subforker = create :user, login: "subforker", plan: "large"
    @org = create :organization, admin: @owner, plan: "business_plus"

    # - source
    #   - fork
    #     - subfork
    #   - fork2
    # - org_fork (forked, then extracted from source)

    @source = create(:repository, name: "source", owner: @owner, from_example: :simple)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source)
    @fork2 = create(:fork_repository, forker: @forker2, fork_repo: @source)
    @subfork = create(:fork_repository, forker: @subforker, fork_repo: @fork)
    @org_fork = create(:fork_repository, forker: @owner, organization: @org, fork_repo: @source)

    assert_equal @source.network, @org_fork.network
    @org_fork.extract!(synchronous: true)
    refute_equal @source.reload.network, @org_fork.reload.network

    # Creating Media::Blob objects with a "verified" state causes
    # Storage::Uploadable#storage_ensure_inner_asset() to run on validation,
    # which resets the blob size to the asset size, which is 1B by default,
    # so we create assets with our intended sizes and use those explicitly.
    file1 = create :asset, size: 5.gigabytes
    file2 = create :asset, size: 2.gigabytes
    file3 = create :asset, size: 700.megabytes

    @source_blob_1 = create :media_blob, repository_network: @source.network, state: :verified,
      asset: file1
    @source_blob_2 = create :media_blob, repository_network: @source.network, state: :verified,
      asset: file2
    @org_blob_1 = create :media_blob, repository_network: @org_fork.network, state: :verified,
      asset: file3
    @org_blob_2 = create :media_blob, repository_network: @org_fork.network, state: :verified,
      asset: file1

    @other_repository = create(:repository, owner: @owner, from_example: :simple)

    # joins Media::Blob row to Asset row
    Media::Blob.all.each do |blob|
      blob.asset.reference!(blob)
    end

    @org.build_asset_status!
    @org.asset_status.rebuild
    @owner.build_asset_status!
    @owner.asset_status.rebuild

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  teardown_once do
    Media::Blob.reset_http!
    Media::Blob.network_copy_batch_size = nil
  end

  test "copies object to new network" do
    transition = Media::Transition.create!(
      repository_network: @org_fork.network,
      old_repository_network: @source.network,
      operation: 0,
    )

    assert_equal @owner, @source_blob_2.pusher

    refute Media::Blob.fetch(@org_fork, @source_blob_2.oid)
    Media::Blob.copy_for_network(transition, [@source_blob_2], @org_fork.network)
    assert copied = Media::Blob.fetch(@org_fork, @source_blob_2.oid)

    assert_equal @source, copied.originating_repository
    assert_equal @owner, copied.pusher
    refute_equal @source_blob_2, copied
  end

  test "network copies with unverified blobs are rejected" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    @source_blob_2.update!(state: :saved)

    transition = Media::Transition.create!(
      repository_network: @org_fork.network,
      old_repository_network: @source.network,
      operation: 0,
    )

    refute Media::Blob.fetch(@org_fork, @source_blob_2.oid),
      "did not expect to find #{@source_blob_2.oid} in network: #{@org_fork.network.id} before copy_for_network"

    expected_keys = {
      "Body": "LFS blobs in repository network not copied due to unverified blobs",
      "code.namespace": "Media::Blob",
      "code.function": "copy_for_network",
      "gh.repo.network.id": @org_fork.network.id,
    }
    assert_logged(**expected_keys) do
      Media::Blob.copy_for_network(transition, [@source_blob_2], @org_fork.network)
    end

    assert_equal [1], GitHub.dogstats.increments("lfs.copy_for_network.unverified_blobs").map(&:value)
    refute Media::Blob.fetch(@org_fork, @source_blob_2.oid),
      "did not expect to find #{@source_blob_2.oid} in network: #{@org_fork.network.id} after copy_for_network"
  end

  test "media blobs unchanged after transferring repository to organization" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_equal_owner @forker, @fork.owner
    assert_equal_owner @owner, @source.owner
    assert_equal @owner, @source.network.owner
    assert_equal @owner, @fork.network.owner
    before_network = @source.network

    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)

    org = create :organization, admin: @owner, plan: "free"

    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      @source.transfer_ownership_to org, actor: @owner
    end

    @source.reload
    @fork.reload

    assert_equal 2.gigabytes, org.plan_limit(:media_blob_max_size)

    @source_blob_1.reload
    assert_equal 5.gigabytes, @source_blob_1.send(:max_blob_size)

    assert_equal_owner @forker, @fork.owner
    assert_equal_owner org, @source.owner
    assert_equal org, @source.network.owner
    assert_equal org, @fork.network.owner
    assert_equal before_network, @source.network
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "fork media blobs copied after fork visibility change" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork.network_id)
    assert_equal @source.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      assert @fork.toggle_visibility(actor: @fork.owner)
    end

    @source.reload
    @fork.reload

    fork_blobs = Media::Blob.where(repository_network_id: @fork.network_id)
    refute_equal @source.network_id, @fork.network_id
    assert_same_assets blobs, fork_blobs
    assert blobs.all? { |b| !fork_blobs.include?(b) }
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "source media blobs unchanged after fork visibility change" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_equal @source.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      assert @fork.toggle_visibility(actor: @fork.owner)
    end

    @source.reload
    @fork.reload

    refute_equal @source.network_id, @fork.network_id
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "nested fork media blobs unchanged after fork visibility change" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @subfork.network_id)
    assert_equal @source.network_id, @subfork.network_id
    assert_equal @subfork.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      assert @fork.toggle_visibility(actor: @fork.owner)
    end

    @source.reload
    @fork.reload
    @subfork.reload

    refute_equal @subfork.network_id, @fork.network_id
    assert_equal @source.network_id, @subfork.network_id
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "sibling fork media blobs unchanged after fork visibility change" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_equal @fork2.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      assert @fork.toggle_visibility(actor: @fork.owner)
    end

    @fork.reload
    @fork2.reload

    refute_equal @fork2.network_id, @fork.network_id
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_nil Media::Transition.by_network(@fork2.network)
  end

  test "fork owner storage updated after fork visibility change" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork.network_id)
    assert_equal @source.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      assert @fork.toggle_visibility(actor: @fork.owner)
    end

    # The "copying" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects have now
    # been copied, the new network's owner's LFS usage will be calculated to
    # include those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork.reload

    assert_storage_usage_equal blobs, @forker.asset_status.reload

    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "fork media blobs copied after fork network extraction" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork.network_id)
    assert_equal @source.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork.extract!
    end

    @source.reload
    @fork.reload

    fork_blobs = Media::Blob.where(repository_network_id: @fork.network_id)
    refute_equal @source.network_id, @fork.network_id
    assert_same_assets blobs, fork_blobs
    assert blobs.all? { |b| !fork_blobs.include?(b) }
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "nested fork media blobs copied after fork network extraction" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @subfork.network_id)
    assert_equal @source.network_id, @subfork.network_id
    assert_equal @subfork.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork.extract!
    end

    @source.reload
    @fork.reload
    @subfork.reload

    fork_blobs = Media::Blob.where(repository_network_id: @fork.network_id)
    assert_equal @subfork.network_id, @fork.network_id
    refute_equal @source.network_id, @subfork.network_id
    assert_same_assets blobs, fork_blobs
    assert blobs.all? { |b| !fork_blobs.include?(b) }
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "source media blobs unchanged after fork network extraction" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_equal @source.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork.extract!
    end

    @source.reload
    @fork.reload

    refute_equal @source.network_id, @fork.network_id
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @source.network_id)
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "sibling fork media blobs unchanged after fork network extraction" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_equal @fork2.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork.extract!
    end

    @fork.reload
    @fork2.reload

    refute_equal @fork2.network_id, @fork.network_id
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "fork media blobs copied even with missing asset" do
    file3 = create :asset, size: 800.megabytes
    source_blob_3 = create :media_blob, repository_network: @source.network, state: :verified,
      asset: file3
    file3.destroy!

    source_blob_3.reload

    ok_blobs = [@source_blob_1, @source_blob_2]
    blobs = [*ok_blobs, source_blob_3]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @subfork.network_id)
    assert_nil source_blob_3.asset
    assert_equal @source.network_id, @subfork.network_id
    assert_equal @subfork.network_id, @fork.network_id

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork.extract!
    end

    @source.reload
    @fork.reload
    @subfork.reload

    fork_blobs = Media::Blob.where(repository_network_id: @fork.network_id)
    assert_equal @subfork.network_id, @fork.network_id
    refute_equal @source.network_id, @subfork.network_id
    assert_same_assets ok_blobs, fork_blobs
    assert ok_blobs.all? { |b| !fork_blobs.include?(b) }
    assert_nil Media::Transition.by_network(@fork.network)
  end

  test "joined media blobs after network re-attach" do
    # Silence audit log warnings.
    Audit.context.push(from: "stafftools/test#post")

    assert_same_elements [
      @source_blob_1, @source_blob_2
    ], Media::Blob.where(repository_network_id: @source.network_id)

    assert_same_elements [
      @org_blob_1, @org_blob_2
    ], Media::Blob.where(repository_network_id: @org_fork.network_id)

    refute_equal @source.network, @org_fork.network

    # We run the the TransitionMediaBlobsJob enqueued for the "copying"
    # transition which has been created, as we want to ensure it has been
    # completed before we run the "deleting" transition which has also
    # been created.
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @org_fork.reattach!
    end
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    @source.reload
    @org_fork.reload

    assert_equal @source.network, @org_fork.network

    blobs = Media::Blob.where(repository_network_id: @source.network_id)
    assert blobs.include?(@source_blob_1)
    assert blobs.include?(@source_blob_2)

    # copies only org_blob_1's asset
    # org_blob_2 is skipped because its OID is the same as source_blob_1
    assert_same_assets [
      @source_blob_1, @source_blob_2, @org_blob_1
    ], Media::Blob.where(repository_network_id: @source.network_id)

    # clears old network Media::Blobs
    assert Media::Blob.find_by(id: @org_blob_1.id)&.archived?
    assert Media::Blob.find_by(id: @org_blob_2.id)&.archived?
    assert_nil Media::Transition.by_network(@source.network)
    assert_nil Media::Transition.by_network(@org_fork.network)
  end

  test "media blobs unchanged after network root changes" do
    # Silence audit log warnings.
    Audit.context.push(from: "stafftools/test#post")

    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @subfork.network_id)
    assert_equal @fork.network_id, @subfork.network_id
    assert_equal @source.network_id, @subfork.network_id

    @subfork.make_network_root!

    @source.reload
    @fork.reload
    @subfork.reload

    assert_same_elements blobs, Media::Blob.where(repository_network_id: @subfork.network_id)
    assert_equal @fork.network_id, @subfork.network_id
    assert_equal @source.network_id, @subfork.network_id
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "do not copy fork media blobs after all repositories in network are deleted and owner is destroyed" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_equal @source.network_id, @fork2.network_id

    # We do not run the TransitionMediaBlobsJob enqueued for the
    # "copying" transition which has been created, as we want to
    # simulate the condition where the repository is deleted and the
    # repository owner destroyed before the transition can be processed.
    assert_enqueued_jobs 1, only: [TransitionMediaBlobsJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @fork2.extract!
      end
    end

    # To delete the owner, we have to first ensure they have no active
    # repositories, so we delete the newly extracted fork.
    #
    # Note that we do not destroy the network because this will prevent the
    # "copying" transition created by the extraction from running, since
    # the transition job will check for an extant network when starting.
    # Instead we simulate the condition where all the repositories in the
    # destination network have only been deleted, not destroyed.
    #
    # Note also that a "deleting" transition is not created, although the
    # the last repository in the network has been deleted, because the
    # repository network has no LFS objects yet, as we haven't run the
    # "copying" transition job.  (Normally, even if the repository
    # network itself has not been destroyed, deleting the last repository
    # in the network causes a "deleting" transition to be created.)
    #
    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @fork2.remove(User.ghost)
      end
    end

    @fork2.reload

    # We can now destroy the user record for the forked repository's owner.
    @forker2.destroy

    # Note that a "copying" transition has been created because a
    # repository in the network has been extracted, but the network owner
    # was subsequently destroyed, so the transition cannot succeed and
    # should raise a Media::Transition::MissingRepositoryNetworkOwnerError
    # exception on each run before its timeout is reached.
    #
    # For the first run we execute the enqueued TransitionMediaBlobsJob,
    # which logs the Media::Transition::MissingRepositoryNetworkOwnerError.
    # The job does not re-enqueue itself, as the QueueMediaTransitionJobsJob
    # does this instead, so we execute the subsequent runs directly.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      expected_keys = {
        "Body": "Not retrying TransitionMediaBlobsJob",
        "exception.type": "Media::Transition::MissingRepositoryNetworkOwnerError",
        "gh.media.transition.id": T.must(Media::Transition.first).id,
      }
      assert_logged(**expected_keys) do
        perform_enqueued_jobs(only: [TransitionMediaBlobsJob])
      end
    end

    max_runs = (Media::Transition::MAX_REPOSITORY_NETWORK_WAIT / QueueMediaTransitionJobsJob::SCHEDULE_INTERVAL).ceil - 1
    max_runs.times do
      assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
        assert_raises Media::Transition::MissingRepositoryNetworkOwnerError do
          Media::Transition.all.each(&:perform)
        end
      end
    end

    # The final run of the "copying" transition should not duplicate any of
    # the LFS objects, nor enqueue a RebuildStorageUsageJob (because the
    # new repository network's owner is nil), but should destroy the
    # transition record.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      Media::Transition.all.each(&:perform)
    end

    @source.reload
    @fork2.reload

    assert_nil @forker2.asset_status

    fork2_blobs = Media::Blob.where(repository_network_id: @fork2.network_id)
    refute_equal @source.network_id, @fork2.network_id
    assert_empty fork2_blobs
    assert_nil Media::Transition.by_network(@fork2.network)
  end

  test "archive media blobs after all repositories in network are deleted" do
    blobs = [@source_blob_1, @source_blob_2]
    asset = @source_blob_1.asset
    assert @owner.asset_status.storage > 1, "storage: #{@owner.asset_status.storage} GB"

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    @source_blob_1.reload
    assert_equal 5.gigabytes, @source_blob_1.send(:max_blob_size)

    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @subfork.remove(User.ghost)
        @fork2.remove(User.ghost)
        @fork.remove(User.ghost)
        @source.remove(User.ghost)
      end
    end

    assert_storage_usage_equal blobs, @owner.asset_status.reload

    # Note that a "deleting" transition has been created because the last
    # repository in the network has been deleted, even though the repository
    # network itself has not been destroyed.
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork.reload
    @fork2.reload
    @subfork.reload

    assert Media::Blob.exists?(@source_blob_1.id)
    assert Media::Blob.exists?(@source_blob_2.id)
    assert @source_blob_1.reload.archived?
    assert @source_blob_2.reload.archived?
    assert Media::Blob.exists?(@org_blob_1.id)
    assert Media::Blob.exists?(@org_blob_2.id)
    refute @org_blob_1.reload.archived?
    refute @org_blob_2.reload.archived?

    assert_equal 0, @owner.asset_status.reload.storage

    archives = asset.archives
    assert_equal ["media/#{@source.network_id}"], archives.map(&:path_prefix)

    assert_same_elements [@source_blob_1, @org_blob_2, archives.first], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "archive media blobs after repository network is destroyed" do
    asset = @source_blob_1.asset
    assert @owner.asset_status.storage > 1, "storage: #{@owner.asset_status.storage} GB"

    # In practice, we expect a repository network to only be destroyed
    # after all its repositories have been destroyed, but if we force its
    # destruction then a "deleting" transition will be created by an
    # ActiveRecord callback in the RepositoryNetwork model because there
    # are LFS objects in the "verified" state in the network.
    @source.network.destroy
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload

    assert Media::Blob.exists?(@source_blob_1.id)
    assert Media::Blob.exists?(@source_blob_2.id)
    assert @source_blob_1.reload.archived?
    assert @source_blob_2.reload.archived?
    assert Media::Blob.exists?(@org_blob_1.id)
    assert Media::Blob.exists?(@org_blob_2.id)
    refute @org_blob_1.reload.archived?
    refute @org_blob_2.reload.archived?

    assert_equal 0, @owner.asset_status.reload.storage

    archives = asset.archives
    assert_equal ["media/#{@source.network_id}"], archives.map(&:path_prefix)

    assert_same_elements [@source_blob_1, @org_blob_2, archives.first], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "archive media blobs after repository is deleted and repository network is destroyed" do
    # Silence audit log warnings.
    Audit.context.push(from: "stafftools/test#post")

    asset = @source_blob_1.asset
    assert @owner.asset_status.storage > 1, "storage: #{@owner.asset_status.storage} GB"

    # When the root repository in the network is deleted, the
    # RepositoryOrchestrationJob enqueues a RebuildStorageUsageJob after
    # assigning another fork in the network to be the new root.
    # The old root repository's owner's LFS usage will be recalculated
    # to exclude those objects.
    # Note that as described in https://github.com/github/repos/issues/11401,
    # no RebuildStorageUsageJob is enqueued for the new root repository's
    # owner, so its storage usage total remains at zero for now.
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, RebuildStorageUsageJob]) do
      @source.remove(User.ghost)
    end

    assert_equal 0, @owner.asset_status.reload.storage
    # If we recalulated the new root repository owner's storage totals,
    # we would want to assert the full storage total instead:
    #  blobs = [@source_blob_1, @source_blob_2]
    #  assert_storage_usage_equal blobs, @forker.asset_status.reload
    assert_nil @forker.asset_status

    # In practice, we expect a repository network to only be destroyed
    # after all its repositories have been destroyed, but if we force its
    # destruction then a "deleting" transition will be created by an
    # ActiveRecord callback in the RepositoryNetwork model because there
    # are LFS objects in the "verified" state in the network.
    @source.network.destroy
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    # Note that the owner in this case is that of the new root repository.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @forker.reload

    assert Media::Blob.exists?(@source_blob_1.id)
    assert Media::Blob.exists?(@source_blob_2.id)
    assert @source_blob_1.reload.archived?
    assert @source_blob_2.reload.archived?
    assert Media::Blob.exists?(@org_blob_1.id)
    assert Media::Blob.exists?(@org_blob_2.id)
    refute @org_blob_1.reload.archived?
    refute @org_blob_2.reload.archived?

    assert_equal 0, @owner.asset_status.reload.storage
    assert_equal 0, @forker.asset_status.reload.storage

    archives = asset.archives
    assert_equal ["media/#{@source.network_id}"], archives.map(&:path_prefix)

    assert_same_elements [@source_blob_1, @org_blob_2, archives.first], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "unarchive media blobs after all repositories in network are deleted and repository is restored" do
    blobs = [@source_blob_1, @source_blob_2]
    asset = @source_blob_1.asset
    assert @owner.asset_status.storage > 1, "storage: #{@owner.asset_status.storage} GB"

    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @subfork.remove(User.ghost)
        @fork2.remove(User.ghost)
        @fork.remove(User.ghost)
        @source.remove(User.ghost)
      end
    end

    assert_storage_usage_equal blobs, @owner.asset_status.reload

    # Note that a "deleting" transition has been created because the last
    # repository in the network has been deleted, even though the repository
    # network itself has not been destroyed.
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork.reload
    @fork2.reload
    @subfork.reload

    assert_equal 0, @owner.asset_status.reload.storage

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    @source_blob_1.reload
    assert_equal 5.gigabytes, @source_blob_1.send(:max_blob_size)

    # When a repository in the network is restored, the
    # RepositoryOrchestrationJob does not enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@source.id, synchronous: false)
      end
    end

    # Note that a "restoring" transition has been created because a
    # repository in the network has been restored.
    Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically

    # The "restoring" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "verified" state, the owner's LFS usage will be recalculated to
    # include those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload

    assert Media::Blob.exists?(@source_blob_1.id)
    assert Media::Blob.exists?(@source_blob_2.id)
    refute @source_blob_1.reload.archived?
    refute @source_blob_2.reload.archived?
    assert Media::Blob.exists?(@org_blob_1.id)
    assert Media::Blob.exists?(@org_blob_2.id)
    refute @org_blob_1.reload.archived?
    refute @org_blob_2.reload.archived?

    assert_storage_usage_equal blobs, @owner.asset_status.reload

    assert_empty asset.archives

    assert_same_elements [@source_blob_1, @org_blob_2], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "do not unarchive media blobs after all repositories in network are deleted and repository is restored then network is destroyed" do
    blobs = [@source_blob_1, @source_blob_2]
    asset = @source_blob_1.asset
    assert @owner.asset_status.storage > 1, "storage: #{@owner.asset_status.storage} GB"

    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @subfork.remove(User.ghost)
        @fork2.remove(User.ghost)
        @fork.remove(User.ghost)
        @source.remove(User.ghost)
      end
    end

    assert_storage_usage_equal blobs, @owner.asset_status.reload

    # Note that a "deleting" transition has been created because the last
    # repository in the network has been deleted, even though the repository
    # network itself has not been destroyed.
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork.reload
    @fork2.reload
    @subfork.reload

    assert_equal 0, @owner.asset_status.reload.storage

    # When a repository in the network is restored, the
    # RepositoryOrchestrationJob does not enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@source.id, synchronous: false)
      end
    end

    # In practice, we expect a repository network to only be destroyed
    # after all its repositories have been destroyed, but as described in
    # https://github.com/github/github/pull/278191, in exceptional cases
    # the repository network may be destroyed after a repository has been
    # restored and has created a "restoring" transition.
    # To reproduce this case, we force the destruction of the network.
    # Note that the ActiveRecord callback in the RepositoryNetwork model
    # that would otherwise create a "deleting" transition does not do so
    # because there are no LFS objects in the "verified" state in the network.
    @source.reload.network.destroy

    # Note that a "restoring" transition has been created because a
    # repository in the network has been restored, but the network
    # was subsequently destroyed, so the transition cannot succeed
    # and should raise a Media::Transition::MissingRepositoryNetworkError
    # exception on each run before its timeout is reached.
    max_runs = (Media::Transition::MAX_REPOSITORY_NETWORK_WAIT / QueueMediaTransitionJobsJob::SCHEDULE_INTERVAL).ceil
    max_runs.times do
      assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
        assert_raises Media::Transition::MissingRepositoryNetworkError do
          Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically
        end
      end
    end

    # The final run of the "restoring" transition should make no changes
    # to the state of the LFS objects, enqueue a RebuildStorageUsageJob,
    # and destroy the transition record.
    Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically

    # The "restoring" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, but as the LFS objects are still in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # continue to exclude those objects, and so should not change.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload

    assert Media::Blob.exists?(@source_blob_1.id)
    assert Media::Blob.exists?(@source_blob_2.id)
    assert @source_blob_1.reload.archived?
    assert @source_blob_2.reload.archived?
    assert Media::Blob.exists?(@org_blob_1.id)
    assert Media::Blob.exists?(@org_blob_2.id)
    refute @org_blob_1.reload.archived?
    refute @org_blob_2.reload.archived?

    assert_equal 0, @owner.asset_status.reload.storage

    archives = asset.archives
    assert_equal ["media/#{@source.network_id}"], archives.map(&:path_prefix)

    assert_same_elements [@source_blob_1, @org_blob_2, archives.first], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@source.network)
  end

  test "do not unarchive media blobs after all repositories in network are deleted and repository is restored then deleted and owner is destroyed" do
    blobs = [@source_blob_1, @source_blob_2]
    assert_same_elements blobs, Media::Blob.where(repository_network_id: @fork2.network_id)
    assert_equal @source.network_id, @fork2.network_id
    asset = @source_blob_1.asset

    # We extract a repository into a separate repository network whose
    # owner owns no other repositories, and run the "copying" transition
    # to duplicate the repository's LFS objects.
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, TransitionMediaBlobsJob]) do
      @fork2.extract!
    end

    # The "copying" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects have now
    # been copied, the new network's owner's LFS usage will be calculated to
    # include those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork2.reload

    fork2_blobs = Media::Blob.where(repository_network_id: @fork2.network_id)
    refute_equal @source.network_id, @fork2.network_id
    assert_same_assets blobs, fork2_blobs
    assert blobs.all? { |b| !fork2_blobs.include?(b) }
    assert_nil Media::Transition.by_network(@fork2.network)

    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @fork2.remove(User.ghost)
      end
    end

    # Note that a "deleting" transition has been created because the last
    # repository in the network has been deleted, even though the repository
    # network itself has not been destroyed.
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # When a repository in the network is restored, the
    # RepositoryOrchestrationJob does not enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@fork2.id, synchronous: false)
      end
    end

    @fork2.reload

    # We do not run the "restoring" transition which has been created, as we
    # want to simulate the condition where the repository is deleted and the
    # repository owner destroyed before the transition can be processed.
    #
    # To delete the owner, we have to first ensure they have no active
    # repositories, so we delete the extracted fork again.
    #
    # Note that we do not destroy the network because this will prevent the
    # "restoring" transition created by the extraction from running, since
    # the transition job will check for an extant network when starting.
    # Instead we simulate the condition where all the repositories in the
    # destination network have only been deleted, not destroyed.
    #
    # Note also that a "deleting" transition is not created, although the
    # the last repository in the network has been deleted, because the
    # repository network has only LFS objects in the "archived" state,
    # as we haven't run the "restoring" transition job yet.  (Normally,
    # even if the repository network itself has not been destroyed,
    # deleting the last repository in the network causes a "deleting"
    # transition to be created.)
    #
    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @fork2.remove(User.ghost)
      end
    end

    @fork2.reload

    # We can now destroy the user record for the forked repository's owner.
    @forker2.destroy

    # Note that a "restoring" transition has been created because a
    # repository in the network has been restored, but the network owner
    # was subsequently destroyed, so the transition cannot succeed and
    # should raise a Media::Transition::MissingRepositoryNetworkOwnerError
    # exception on each run before its timeout is reached.
    max_runs = (Media::Transition::MAX_REPOSITORY_NETWORK_WAIT / QueueMediaTransitionJobsJob::SCHEDULE_INTERVAL).ceil
    max_runs.times do
      assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
        assert_raises Media::Transition::MissingRepositoryNetworkOwnerError do
          Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically
        end
      end
    end

    # The final run of the "restoring" transition should make no changes
    # to the state of the LFS objects, nor enqueue a RebuildStorageUsageJob
    # (because the repository network owner is nil), but should destroy the
    # transition record.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically
    end

    @fork2.reload

    fork2_blob_1 = fork2_blobs.find { |b| b.oid == @source_blob_1.oid }
    fork2_blob_2 = fork2_blobs.find { |b| b.oid == @source_blob_2.oid }
    assert Media::Blob.exists?(fork2_blob_1.id)
    assert Media::Blob.exists?(fork2_blob_2.id)
    assert fork2_blob_1.reload.archived?
    assert fork2_blob_2.reload.archived?

    assert_nil Asset::Status.find_by(id: @forker2.asset_status.id)

    archives = asset.reload.archives
    assert_equal ["media/#{@fork2.network_id}"], archives.map(&:path_prefix)

    assert_same_elements [@source_blob_1, @org_blob_2, fork2_blob_1, archives.first], asset.references.map(&:uploadable)
    assert_nil Media::Transition.by_network(@fork2.network)
  end

  test "archiving and unarchiving media blobs updates disk usage and reactivates user" do
    blobs = [@source_blob_1, @source_blob_2]
    assert @owner.asset_status.storage > 1.5, "storage: #{@owner.asset_status.storage} GB"
    if GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?(@owner)
      assert_equal "none", @owner.asset_status.notified_state
      assert @owner.asset_status.owner_feature_enabled?
    else
      assert_equal "disabled_over_quota", @owner.asset_status.notified_state
      refute @owner.asset_status.owner_feature_enabled?
    end

    # When the root repository in the network is deleted last after all
    # other repositories, the RepositoryOrchestrationJob does not
    # enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @subfork.remove(User.ghost)
        @fork2.remove(User.ghost)
        @fork.remove(User.ghost)
        @source.remove(User.ghost)
      end
    end

    assert_storage_usage_equal blobs, @owner.asset_status.reload

    # Note that a "deleting" transition has been created because the last
    # repository in the network has been deleted, even though the repository
    # network itself has not been destroyed.
    Media::Transition.all.each(&:perform) # deletion jobs are not queued automatically

    # The "deleting" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "archived" state, the owner's LFS usage will be recalculated to
    # exclude those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload
    @fork.reload
    @fork2.reload
    @subfork.reload

    assert_equal 0, @owner.asset_status.reload.storage
    assert_equal "none", @owner.asset_status.notified_state
    assert @owner.asset_status.owner_feature_enabled?

    # When a repository in the network is restored, the
    # RepositoryOrchestrationJob does not enqueue a RebuildStorageUsageJob.
    assert_enqueued_jobs 0, only: [RebuildStorageUsageJob] do
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        Repository.restore(@source.id, synchronous: false)
      end
    end

    # Note that a "restoring" transition has been created because a
    # repository in the network has been restored.
    Media::Transition.all.each(&:perform) # restoration jobs are not queued automatically

    # The "restoring" transition enqueues a RebuildStorageUsageJob when the
    # repository network owner is non-nil, and as the LFS objects are now in
    # the "verified" state, the owner's LFS usage will be recalculated to
    # include those objects.
    perform_enqueued_jobs(only: [RebuildStorageUsageJob])

    @source.reload

    assert_storage_usage_equal blobs, @owner.asset_status.reload
    if GitHub.enterprise? || GitHub.flipper[:lfs_disable_datapacks].enabled?(@owner)
      assert_equal "none", @owner.asset_status.notified_state
      assert @owner.asset_status.owner_feature_enabled?
    else
      assert_equal "disabled_over_quota", @owner.asset_status.notified_state
      refute @owner.asset_status.owner_feature_enabled?
    end

    assert_nil Media::Transition.by_network(@source.network)
  end

  test "can async_copy network with objects" do
    assert_enqueued_jobs 1, only: [TransitionMediaBlobsJob] do
      assert Media::Transition.async_copy(@source.network, @org_fork.network)
    end
    assert_equal 1, Media::Transition.count
  end

  test "can async_delete network with objects" do
    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      assert Media::Transition.async_delete(@source.network)
    end
    assert_equal 1, Media::Transition.count
  end

  test "can async_restore network with objects" do
    assert_enqueued_jobs 1, only: [TransitionMediaBlobsJob] do
      assert Media::Transition.async_restore(@source.network)
    end
    assert_equal 1, Media::Transition.count
  end

  test "async_restore unqueues async_delete jobs" do
    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      assert Media::Transition.async_delete(@source.network)
    end
    assert_equal 1, Media::Transition.count
    assert_enqueued_jobs 1, only: [TransitionMediaBlobsJob] do
      assert Media::Transition.async_restore(@source.network)
    end
    assert_equal 1, Media::Transition.count
    assert_equal ["restoring"], Media::Transition.all.map(&:operation)
  end

  test "cannot async_copy network without objects" do
    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      refute Media::Transition.async_copy(@other_repository.network, @fork.network)
    end
    assert_equal 0, Media::Transition.count
  end

  test "cannot async_delete network without objects" do
    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      refute Media::Transition.async_delete(@other_repository.network)
    end
    assert_equal 0, Media::Transition.count
  end

  test "cannot async_restore network without objects" do
    assert_enqueued_jobs 0, only: [TransitionMediaBlobsJob] do
      refute Media::Transition.async_restore(@other_repository.network)
    end
    assert_equal 0, Media::Transition.count
  end

  def assert_same_assets(expected_blobs, actual_blobs)
    assert_equal expected_blobs.size, actual_blobs.size, "Wrong # of blobs"

    # Media::Blob#oid is denormalized from Asset#oid
    assert_same_elements expected_blobs.map(&:oid), actual_blobs.map(&:oid), "mismatched oids"

    expected_assets = expected_blobs.index_by(&:asset)
    actual_assets = actual_blobs.index_by(&:asset)

    # confirm that Assets are the same
    assert_same_elements expected_assets.keys, actual_assets.keys

    assert_same_elements expected_blobs.map(&:state), actual_blobs.map(&:state)

    # assert that each Asset has a reference to each Media::Blob
    expected_assets.each_key do |asset|
      actual_blob = actual_assets[asset]
      uploadables = asset.references.reload.map(&:uploadable)
      assert uploadables.include?(actual_blob), same_assets_assertion_message(:Actual, asset, actual_blob)
    end
  end

  def same_assets_assertion_message(type, asset, blob)
    "#{type} blob not an reference\n#{blob.class}##{blob.id} not in #{asset.oid}:\n#{asset.references.map { |r| "#{r.uploadable_type}##{r.uploadable_id}" }.join("\n")}"
  end

  def assert_storage_usage_equal(expected_blobs, actual_asset_status)
    gb = 1024.0**3
    expected_usage = expected_blobs.map { |b| b.size }.sum / gb
    assert_equal expected_usage.round(3), actual_asset_status.storage.round(3)
  end
end
