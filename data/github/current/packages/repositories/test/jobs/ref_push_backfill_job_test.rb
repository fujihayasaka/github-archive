# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RefPushBackfillJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @user1  = create(:user, login: "user1")
    @user2  = create(:user, login: "user2")
    @repo = create :repository

    @push_number = 0

    # populate an unrelated repo that should not be affected
    @unrelated_repo = create :repository, from_example: :simple
    push(@unrelated_repo, @user1, "feature")
    push(@unrelated_repo, @user2, "master")
    RefPushBackfillJob.perform_now(@unrelated_repo.id)
    assert_equal 4, RefPush.where(repository: @unrelated_repo).count, "unrelated repo was not initialized"
  end

  setup do
    # reset the repo before every test
    example_repo :simple, @repo

    Repositories::Redis.redis_instance.flushdb
  end

  teardown do
    # assert @unrelated_repo is unaffected
    assert_equal 4, RefPush.where(repository: @unrelated_repo).count, "unrelated repo was affected"
    assert_equal 1, RefPush.where(repository: @unrelated_repo, ref: "refs/heads/master").count, "unrelated repo was affected"
    assert_equal 1, RefPush.where(repository: @unrelated_repo, ref: "refs/heads/feature").count, "unrelated repo was affected"
  end

  def push(repo, pusher, branch, delete: false)
    before = repo.ref_to_sha(branch) || GitHub::NULL_OID
    ref = Git::Ref.new(repo, "refs/heads/#{branch}", before)

    push_proc = proc do
      if delete
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          ref.delete(pusher)
        end
      else
        metadata = { message: "a commit", committer: pusher, author: pusher }
        perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          ref.append_commit(metadata, pusher) do |files|
            files.add("file.txt", SecureRandom.hex(10).to_s)
          end
        end
      end
    end

    if @push_frozen_date
      Timecop.freeze(@push_frozen_date + @push_number.seconds) do
        push_proc.call
      end
    else
      push_proc.call
    end
    @push_number += 1

    ref
  end

  test "job retries" do
    assert_retry_on_dirty_exit(job: RefPushBackfillJob, args: [@repo.id])
    assert_retry_on_recoverable_exceptions(job: RefPushBackfillJob,  args: [@repo.id])
    assert_retry_on_throttler_error(job: RefPushBackfillJob,  args: [@repo.id])
  end

  test "skip git check" do
    push(@repo, @user1, "feature")
    push(@repo, @user2, "feature2")
    push(@repo, @user1, "feature", delete: true)
    push(@repo, @user2, "feature2", delete: true)

    # remove the delete record from the Push table and redis
    T.must(Push.where(repository: @repo, ref: "refs/heads/feature").last).delete
    Repositories::Redis.redis_instance.flushdb

    # the job should only process the pushes that are in the Push table and ignore what's in git
    RefPushBackfillJob.perform_now(@repo.id, Time.zone.at(0), false)

    pushes = RefPush.where(repository: @repo)
    assert_equal 1, pushes.count
    assert_same_elements ["refs/heads/feature"], pushes.map(&:ref)
  end

  test "missing pushes" do
    # When this test file is initialized, the :simple repo is populated with some refs:
    # master, -gh-pages, and cr-line-endings
    # While the Push table has 0 records.
    # In this scenario, the sync job should insert "ghost" records for those branches
    # so they show up in branch queries, although we have no push data to go with it
    RefPushBackfillJob.perform_now(@repo.id)

    pushes = RefPush.where(repository: @repo)
    assert_equal 3, pushes.count
    assert_same_elements ["refs/heads/master", "refs/heads/-gh-pages", "refs/heads/cr-line-endings"], pushes.map(&:ref)

    pushes.each do |push|
      assert_equal User.ghost, push.pusher
    end
  end

  test "extra pushes" do
    # Git-systems is the source of truth, so if the Push table has branches that git-system doesn't, we should delete them
    push(@repo, @user1, "feature")
    push(@repo, @user2, "feature2")
    push(@repo, @user1, "feature", delete: true)
    push(@repo, @user2, "feature2", delete: true)

    # remove the delete record from the Push table
    T.must(Push.where(repository: @repo, ref: "refs/heads/feature").last).delete

    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/feature2").count
  end

  test "queue job on push" do
    assert_enqueued_jobs(1, only: RefPushBackfillJob) do
      push(@repo, @user1, "master")
      assert_equal 1, RefPush.where(repository: @repo).count
    end
  end

  test "queue job on branch finder" do
    assert_enqueued_jobs(1, only: RefPushBackfillJob) do
      Branches::BranchFinder.new(@repo, @user1).your_branches
      assert_equal 0, RefPush.where(repository: @repo).count
    end
  end

  test "basic scenario" do
    refs = {}
    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc
    # create and push to master a bunch of times, enough to force the job to requeue itself
    push(@repo, @user1, "master")
    push(@repo, @user1, "feature")
    push(@repo, @user2, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    refs["master2"] = push(@repo, @user2, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    refs["topic2"] = push(@repo, @user2, "topic")
    refs["feature1"] = push(@repo, @user1, "feature")
    refs["master1"] = push(@repo, @user1, "master")

    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal 2, RefPush.where(repository: @repo, ref: "refs/heads/master").count
    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/topic").count
    assert_equal refs["master1"].target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/master")&.after
    assert_equal refs["master2"].target.oid, RefPush.find_by(repository: @repo, pusher: @user2, ref: "refs/heads/master")&.after
    assert_equal refs["feature1"].target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/feature")&.after
    assert_equal refs["topic2"].target.oid, RefPush.find_by(repository: @repo, pusher: @user2, ref: "refs/heads/topic")&.after
  end

  test "create delete create branch" do
    refs = {}
    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc
    push(@repo, @user1, "master")
    push(@repo, @user1, "feature")
    refs["master2"] = push(@repo, @user2, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "feature", delete: true)
    refs["master1"] = push(@repo, @user1, "master")
    refs["feature2"] = push(@repo, @user2, "feature")

    RefPushBackfillJob.perform_now(@repo.id)

    # the original feature branch by user1 should have been removed from the table, and only user2's push should remain
    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_nil   RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/feature")
    assert_equal refs["feature2"].target.oid, RefPush.find_by(repository: @repo, pusher: @user2, ref: "refs/heads/feature")&.after
    assert_equal refs["master1"].target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/master")&.after
    assert_equal refs["master2"].target.oid, RefPush.find_by(repository: @repo, pusher: @user2, ref: "refs/heads/master")&.after
  end

  test "create and delete topic branch" do
    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc

    # create and push to topic1, then delete it
    push(@repo, @user1, "topic1")
    ref = push(@repo, @user2, "topic1")

    assert_equal ref.target.oid, @repo.ref_to_sha("topic1")
    assert_equal 2, Push.where(repository: @repo, ref: "refs/heads/topic1").count

    # delete the branch
    push(@repo, @user1, "topic1", delete: true)

    assert_nil @repo.ref_to_sha("topic1")
    assert_equal 3, Push.where(repository: @repo, ref: "refs/heads/topic1").count

    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/topic1").count
  end

  test "deleted when repo is purged" do
    push(@repo, @user1, "feature")
    RefPushBackfillJob.perform_now(@repo.id)
    assert_equal 1, RefPush.where(repository_id: @repo.id, pusher: @user1).count

    @repo.remove(@repo.owner, synchronous: true)
    assert_equal 1, RefPush.where(repository_id: @repo.id, pusher: @user1).count

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob, DeleteDependentRecordsJob]) do
      @repo.purge
    end
    assert_equal 0, RefPush.where(repository_id: @repo.id).count
  end

  test "backfill job doesn't lose new pushes" do
    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc
    push(@repo, @user1, "master")

    # insert/update the RefPush
    push = Push.where(repository: @repo, pusher: @user1, ref: "refs/heads/master").last
    RefPush.log_push(T.must(push))

    RefPushBackfillJob.perform_now(@repo.id)

    rp = RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/master")

    assert_equal T.must(push).pushed_at, rp&.pushed_at
    assert_equal T.must(push).after, rp&.after
  end

  test "job requeues and finishes" do
    refs = {}
    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc

    # create and push to master a bunch of times, enough to force the job to requeue itself
    push(@repo, @user1, "master")
    push(@repo, @user1, "feature")
    push(@repo, @user2, "master")
    refs["feature1"] = push(@repo, @user1, "feature")
    push(@repo, @user2, "master") # last of 1st job, first of 2nd job
    push(@repo, @user1, "feature", delete: true)
    push(@repo, @user2, "master")
    push(@repo, @user1, "master")
    push(@repo, @user1, "master") # last of 2nd job, first of 3rd job
    refs["feature2"] = push(@repo, @user2, "feature")
    push(@repo, @user2, "master")
    push(@repo, @user1, "master")

    # flush the table in case the FFs are enabled that kick off this job in the product code
    perform_enqueued_jobs(only: RefPushBackfillJob)
    RefPush.where(repository: @repo).delete_all
    Repositories::Redis.redis_instance.flushdb

    # reduce the max operations and batch sizes to force the job to requeue itself after just one loop
    RefPushBackfillJob.stub_const(:MAX_OPERATION_UNITS, 0) do
      RefPushBackfillJob.stub_const(:BATCH_SIZE, 5) do
        RefPushBackfillJob.perform_now(@repo.id)
      end
    end

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal refs["feature1"].target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/feature")&.after

    RefPushBackfillJob.stub_const(:MAX_OPERATION_UNITS, 0) do
      RefPushBackfillJob.stub_const(:BATCH_SIZE, 5) do
        perform_enqueued_jobs(only: RefPushBackfillJob)
      end
    end

    assert_equal 0, RefPush.where(repository: @repo, ref: "refs/heads/feature").count

    assert_enqueued_jobs(0, only: RefPushBackfillJob) do
      RefPushBackfillJob.stub_const(:MAX_OPERATION_UNITS, 0) do
        RefPushBackfillJob.stub_const(:BATCH_SIZE, 5) do
          perform_enqueued_jobs(only: RefPushBackfillJob)
        end
      end
    end

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal refs["feature2"].target.oid, RefPush.find_by(repository: @repo, pusher: @user2, ref: "refs/heads/feature")&.after
  end

  test "skip invalid pushes" do
    # create 1 valid push and 3 invalid pushes with various nils
    valid_ref = push(@repo, @user1, "feature")
    ref1 = push(@repo, @user1, "feature")
    ref2 = push(@repo, @user1, "feature")
    ref3 = push(@repo, @user1, "feature")

    RefPush.where(repository: @repo).delete_all

    # corrupt all but the first push with invalid nils
    Push.where(repository: @repo, ref: "refs/heads/feature", after: ref1.target.oid).update_all(pusher_id: nil)
    Push.where(repository: @repo, ref: "refs/heads/feature", after: ref2.target.oid).update_all(ref: nil)
    Push.where(repository: @repo, ref: "refs/heads/feature", after: ref3.target.oid).update_all(after: nil)

    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal valid_ref.target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/feature")&.after
  end

  test "yields to pushes that occur when the job is running" do
    # Simulate a race by inserting a newer RefPush (without a Push) before the job starts
    # This simulates a push coming in during the job run that is not captured by the loop query

    @push_frozen_date = Time.new(2020, 1, 1, 0, 0, 0).utc
    # An older push
    val = push(@repo, @user1, "feature")
    RefPush.where(repository: @repo).delete_all

    # create a RefPush without a Push
    ref = push(@repo, @user1, "feature")
    Push.where(repository: @repo, after: ref.target.oid).delete_all

    # The job should read `old` and replay it but `during_job` should take precedence
    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal 1, RefPush.where(repository: @repo, ref: "refs/heads/feature").count
    assert_equal ref.target.oid, RefPush.find_by(repository: @repo, pusher: @user1, ref: "refs/heads/feature")&.after
  end

  test "resolves tenant context" do
    GitHub::CurrentTenant.remove
    assert_nil GitHub::CurrentTenant.get

    RefPushBackfillJob.perform_now(@repo.id)

    assert_equal @repo.reload.tenant_id, GitHub::CurrentTenant.get.id
  end if TestEnv.test_in_multitenancy_mode?
end
