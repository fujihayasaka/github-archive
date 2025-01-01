# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryBulkPurgeJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  def create_active_repo(age = 1.year.ago, user = @user)
    repo = create :repository, owner: user
    repo.update_column(:updated_at, age)
    repo
  end

  def create_deleted_repo(age = 1.year.ago, user = @user)
    repo = build :repository, owner: user
    repo.created_by_user_id = user.id
    repo.save!
    repo.network.save!

    repo.remove(user, instrument: true, force: true, synchronous: true)
    repo.update_column(:updated_at, age)
    repo
  end

  test "enqueues job" do
    RepositoryBulkPurgeJob.perform_later
    assert_enqueued_jobs 1, only: RepositoryBulkPurgeJob, queue: :repository_bulk_purge
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RepositoryBulkPurgeJob, args: []
    assert_retry_on_error GitHub::Gitbackups::ClientError, RepositoryBulkPurgeJob, []
  end

  test "respects end date" do
    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      # currently configured to purge after 90 days
      repo0 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago + 1.day)
      repo1 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day)
      repo2 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 11.days)
      repo3 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 20.days)
      repo4 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 30.days)
      repo5 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.minute)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now
        assert_equal 4, purged, "expected purge count to be 4"
      end

      assert_equal repo0, Repository.find_by(id: repo0.id)
      assert_nil Repository.find_by(id: repo1.id)
      assert_nil Repository.find_by(id: repo2.id)
      assert_nil Repository.find_by(id: repo3.id)
      assert_nil Repository.find_by(id: repo4.id)
      assert_equal repo5, Repository.find_by(id: repo5.id)
    end
  end

  test "can skip active and held repos" do
    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      user1 = create :user
      user2 = create :user
      user_hold = create(:user)
      user_hold.place_legal_hold(actor: @staff)
      assert_predicate user_hold, :legal_hold?

      # create 10 repos for each user, 30 total
      (0..9).each do |count|
        age = RepositoryBulkPurgeJob.expiration_period.ago - (count + 1).days
        deleted_repo = create_deleted_repo(age, user1)
        GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(deleted_repo.repository_spec).returns(:ok)
        GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(deleted_repo.unsullied_wiki.repository_spec).returns(:ok)
        create_deleted_repo(age, user_hold)
        create_active_repo(age, user2)
      end

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(12)
        # expect 6 held repos to be ignored and timestamps updated
        # expect 6 repos to be purged
        assert_equal 6, purged
      end

      assert_equal 4, Repository.owned_by(user1).count
      assert_equal 10, Repository.owned_by(user_hold).count
      assert_equal 10, Repository.owned_by(user2).count

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(12)
        # expect the remaining 4 held repos to be ignored, and 4 to be purged
        assert_equal 4, purged
      end

      assert_equal 0, Repository.owned_by(user1).count
      assert_equal 10, Repository.owned_by(user_hold).count
      assert_equal 10, Repository.owned_by(user2).count

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(12)
        # nothing left to purge
        assert_equal 0, purged
      end
    end
  end

  if GitHub.flipper[:skip_repo_purge_during_peak].enabled?
    test "skips purging repos within INACTIVE_HOURS" do
      Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours - 1.hour) do
        # currently configured to purge after 90 days
        repo0 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago + 1.day)
        repo1 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day)
        repo2 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 11.days)
        repo3 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 20.days)
        repo4 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 30.days)
        repo5 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.minute)

        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          purged = RepositoryBulkPurgeJob.perform_now
          assert_equal 0, purged, "expected purge count to be 0"
        end
      end
    end

    test "does not skip purging repos on the weekend" do
      # Sunday
      Timecop.travel(Date.today.beginning_of_week.ago(1.day) + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours - 1.hour) do
        # currently configured to purge after 90 days
        repo0 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago + 1.day)
        repo1 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day)
        repo2 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 11.days)
        repo3 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 20.days)
        repo4 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 30.days)
        repo5 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.minute)

        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          purged = RepositoryBulkPurgeJob.perform_now
          assert_equal 4, purged, "expected purge count to be 4"
        end
      end
    end
  end

  test "can sample repos at a given rate" do
    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      GitHub.flipper[:repo_purge_batch_size_sample_rate].enable_percentage_of_time(25.0)
      8.times { create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day) }

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(2)
        assert_equal 2, purged, "expected purge count to be 2"
      end
    end
  end


  test "compute batch size" do
    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      job = RepositoryBulkPurgeJob.new
      batch_size = job.compute_batch_size
      assert_equal 10, batch_size

      batch_size = job.compute_batch_size
      assert_equal 20, batch_size

      batch_size = job.compute_batch_size
      assert_equal 30, batch_size

      Repositories::Kv.store.set(RepositoryBulkPurgeJob::KV_KEY, (RepositoryBulkPurgeJob::BATCH_SIZE + 1).to_s)
      batch_size = job.compute_batch_size
      assert_equal RepositoryBulkPurgeJob::BATCH_SIZE, batch_size

      batch_size = job.compute_batch_size
      assert_equal RepositoryBulkPurgeJob::BATCH_SIZE, batch_size

      job.stubs(:high_replication_lag?).returns(true)
      last_batch_size = batch_size
      batch_size = job.compute_batch_size
      assert_equal last_batch_size - 100, batch_size

      last_batch_size = batch_size
      batch_size = job.compute_batch_size
      assert_equal last_batch_size - 100, batch_size

      job.stubs(:high_replication_lag?).returns(false)
      last_batch_size = batch_size
      batch_size = job.compute_batch_size
      assert_equal last_batch_size + 10, batch_size

      last_batch_size = batch_size
      batch_size = job.compute_batch_size
      assert_equal last_batch_size + 10, batch_size
    end
  end

  test "compute batch size works when kv unavailable" do
    GitHub::Result.any_instance.stubs(:ok?).returns(false)

    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      job = RepositoryBulkPurgeJob.new
      # if kv is down and its not (during_peak_hours? || high_replication_lag?) then just do batches of 10
      assert_equal 10, job.compute_batch_size
      assert_equal 10, job.compute_batch_size
    end
  end

  test "high_replication_lag" do
    job = RepositoryBulkPurgeJob.new
    disable_feature_flag(:repository_bulk_purge_delay_threshold)
    Freno.client.stubs(:replication_delay).returns(0.5)
    refute job.high_replication_lag?
    Freno.client.stubs(:replication_delay).returns(1.1)
    assert job.high_replication_lag?

    Freno.client.stubs(:replication_delay).returns(0.75)
    GitHub.flipper[:repository_bulk_purge_delay_threshold].enable_percentage_of_time(7)
    assert job.high_replication_lag?
    GitHub.flipper[:repository_bulk_purge_delay_threshold].enable_percentage_of_time(8)
    refute job.high_replication_lag?
  end

  test "a single purge failure does not stop the job" do
    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      repo0 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day)
      repo1 = create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 1.day)

      Repository.any_instance.stubs(:deleted?).raises(StandardError).then.returns(true)

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(2)
      end

      assert_equal 1, Repository.owned_by(@user).count
    end
  end

  test "purges failed creations when batch_size exceeds the number of purgeable repos" do
    GitHub.flipper[:repo_purge_failed_creation_batch_size].enable_percentage_of_time(1)

    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      repos = []
      2.times { repos << create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 10.days) }
      2.times { repos << create(:repository, :failed_creation) }

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(5)
        assert_equal 4, purged, "expected purge count to be 4"
      end

      repos = repos.map { |repo| assert_nil Repository.find_by(id: repo.id) }
    end
  end

  test "at most purges batch_size purgeable repos and failed creations" do
    GitHub.flipper[:repo_purge_failed_creation_batch_size].enable_percentage_of_time(1)

    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      purgeable_repos = []
      failed_creations = []
      2.times { purgeable_repos << create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 10.days) }
      2.times { failed_creations << create(:repository, :failed_creation) }

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(3)
        assert_equal 3, purged, "expected purge count to be 3"
      end

      purgeable_repos = purgeable_repos.map { |repo| assert_nil Repository.find_by(id: repo.id) }
      # Even if repo_purge_failed_creation_batch_size would allow purging more failed creations, only 1 is purged
      # since the batch_size passed to bulk purge job limits the max number of repos we can purge
      assert_equal 1, failed_creations.count { |repo| Repository.find_by(id: repo.id).nil? }
      assert_equal 1, failed_creations.count { |repo| Repository.find_by(id: repo.id).present? }
    end
  end

  test "does not purge failed creations when batch_size exceeds the number of purgeable repos" do
    GitHub.flipper[:repo_purge_failed_creation_batch_size].enable_percentage_of_time(1)

    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      purgeable_repos = []
      failed_creations = []
      2.times { purgeable_repos << create_deleted_repo(RepositoryBulkPurgeJob.expiration_period.ago - 10.days) }
      2.times { failed_creations << create(:repository, :failed_creation) }

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(2)
        assert_equal 2, purged, "expected purge count to be 4"
      end

      purgeable_repos = purgeable_repos.map { |repo| assert_nil Repository.find_by(id: repo.id) }
      failed_creations = failed_creations.map { |repo| refute_nil Repository.find_by(id: repo.id) }
    end
  end

  test "defaults to FAILED_CREATION_BATCH_SIZE when batch_size FF is 0" do
    # Set batch size to 0
    GitHub.flipper[:repo_purge_failed_creation_batch_size].enable_percentage_of_time(0)

    Timecop.travel(Date.today.beginning_of_week + RepositoryBulkPurgeJob::INACTIVE_HOURS.last.hours + 1.hour) do
      failed_creations = []
      6.times { failed_creations << create(:repository, :failed_creation) }

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        purged = RepositoryBulkPurgeJob.perform_now(10)
        assert_equal 5, purged, "expected purge count to be 2"
      end

      assert_equal 5, failed_creations.count { |repo| Repository.find_by(id: repo.id).nil? }
      assert_equal 1, failed_creations.count { |repo| Repository.find_by(id: repo.id).present? }
    end
  end
end
