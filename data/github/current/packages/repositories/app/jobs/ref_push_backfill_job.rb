# typed: true
# frozen_string_literal: true

# This job is intended to run one time to collect the entire history of pushes for a single repo
# and consolidate that data into the new RefPush table. Once it has run once it should never
# need to be run again, but it should be safe to rerun.
#
# The plan: Read in a batch of 10k push records from the repo. In testing, this takes about 2.5 seconds.
# Process the batch and keeping the lastest ref per user. Delete refs as they are deleted.
# Process 20 batches per job run, then writing the results to the database. Should take about 1 minute.
# Queue another job to pickup where this left off. Repeat until all pushes have been processed.
class RefPushBackfillJob < ApplicationJob
  queue_as :ref_push_backfill
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Borrow the retryable exceptions from the orchestrations
  # This job is idempotent, so we can retry on any error (ideally to avoid incorrect RefPush data)
  retry_on *Orchestration::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 8

  use_primaries ApplicationRecord::Repositories, ApplicationRecord::RepositoriesPushes

  # Ensure the job only runs once per repo at a time
  # Requeueing will work because `last_pushed_at` will be different each time
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  # It takes about 2.5 seconds just to query 10k records from the Push table in dotcom.
  # We cannot exceed 10 seconds or query will abort and the job will fail
  BATCH_SIZE = 10_000

  # Try to keep the job under 1 minute. Fetch records for up to 30 seconds.
  MAX_FETCH_TIME = 30.seconds

  # In production testing, upserts take ~1 second per 200 records. Deletes take ~1 second per 500 records
  # Try and keep this section under ~30 seconds
  MAX_OPERATION_UNITS = 30_000

  # last_pushed_at lets us batch the work and pick up where we left off.
  # This is necessary for big repos that might take 30+ minutes to process.
  # It's also useful if we need to repair history in the event the job didn't run during a livesite outage
  #
  # compare_with_git tells the job to do an extra level of validation by comparing refs with git-systems.
  # For the first time populating this table, we should do this since we know there are pushes missing from the Push table.
  # But if we are repairing history due to a livesite outage it is not necessary and can be an expensive operation.
  def perform(repository_id, last_pushed_at = Time.zone.at(0), compare_with_git = true)
    GitHub.dogstats.distribution_time "ref_push_backfill_job.duration" do
      repo = Repositories::Public.find_active(repository_id)
      return unless repo

      timer = Timer.start
      loop_count = 0
      start_time = Time.now
      pushed_refs = T.let({}, T::Hash[String, T::Hash[Integer, Push]]) # to track latest push per user per ref
      deleted_refs = T.let({}, T::Hash[String, ActiveSupport::TimeWithZone]) # to track deleted refs
      requeue_job = T.let(false, T::Boolean)

      loop do
        loop_count += 1
        GitHub.logger.info("gh.repo.ref_push_backfill_job.loop", {
          "gh.repo.id": repo.id,
          "gh.repo.ref_push_backfill_job.last_pushed_at": last_pushed_at,
          "gh.repo.ref_push_backfill_job.count": loop_count
        })

        # Get a batch of pushes in chronological order starting with the oldest
        # Note there will be at least one duplicate record from previous batch
        # because we are using the same timestamp as the last record in the previous batch
        # which is necessary because timestamps are not that precise enough to ensure we got all the pushes with that timestamp in the previous batch
        pushes = Push.from("pushes FORCE INDEX (index_pushes_on_repository_id_and_pushed_at)").where(repository_id: repo.id, pushed_at: last_pushed_at..).order(pushed_at: :asc).limit(BATCH_SIZE)
        last_pushed_at = pushes.last&.pushed_at
        batch_count = 0

        pushes.to_ary.each do |push|
          batch_count += 1
          if push.deleted?
            # delete any pushes to this deleted ref
            pushed_refs.delete(push.ref)
            deleted_refs[push.ref] = push.pushed_at
            next
          end

          # record this push
          if RefPush.valid_push?(push)
            pushed_refs[push.ref] ||= {}
            T.must(pushed_refs[push.ref])[T.must(push.pusher_id)] = push
          end
        end

        # we can stop if we didn't get a full batch from the Push table
        if batch_count < BATCH_SIZE
          break
        end

        # we can stop if it has already been 30 seconds or we have a large number of records to process
        if Time.now - start_time >= MAX_FETCH_TIME || pushed_refs.values.map(&:values).sum(&:size) * 5 + deleted_refs.size * 2 >= MAX_OPERATION_UNITS
          requeue_job = true
          break
        end
      end

      # delete the deleted refs
      delete_timer = Timer.start
      deleted_refs.each do |ref, pushed_at|
        RefPush.where(repository: repo, ref: ref, pushed_at: ..pushed_at).delete_all
      end
      delete_timer.stop

      # insert/update all new pushes from this job
      # flatten the hash of hashes into an array of records
      records = pushed_refs.values.map(&:values).flatten
      create_timer = Timer.start
      RefPush.batch_log_pushes(records)
      create_timer.stop

      GitHub.logger.info("gh.repo.ref_push_backfill_job.loop_end", {
        "gh.repo.id": repo.id,
        "gh.repo.ref_push_backfill_job.create_time": create_timer.elapsed_ms,
        "gh.repo.ref_push_backfill_job.delete_time": delete_timer.elapsed_ms,
        "gh.repo.ref_push_backfill_job.records": records.size,
        "gh.repo.ref_push_backfill_job.deleted_refs": deleted_refs.size,
      })

      if requeue_job
        RefPushBackfillJob.perform_later(repo.id, last_pushed_at, compare_with_git)
        timer.stop
        GitHub.logger.info("gh.repo.ref_push_backfill_job.requeued", {
          "gh.repo.id": repo.id,
          "gh.repo.ref_push_backfill_job.last_pushed_at": last_pushed_at,
          "gh.repo.ref_push_backfill_job.duration": timer.elapsed_ms
        })
      elsif compare_with_git
        GitHub.logger.info("gh.repo.ref_push_backfill_job.compare_with_git", { "gh.repo.id": repo.id })
        # Do an extra level of cleanup by comparing refs with git-systems
        # Git-systems is the source of truth for branches in this repo, so confirm our results with them.

        # get a list of refs in the RefPush table
        ref_pushes = RefPush.where(repository_id: repo.id).distinct.pluck(:ref).to_a.map { |ref| ref.b }

        # get a list of refs from git-systems
        git_branches = repo.heads.map { |r| "#{repo.heads.prefix}#{r.name}" }

        # If repo.heads returns nothing, it's probably because git-rpc silently failed, and not because there are no branches.
        # Don't truncate all the work we just did above.
        if git_branches.any?
          refs_to_add = git_branches - ref_pushes
          # add a ghost record for any existing branch that we didn't find in the RefPush table
          batch = refs_to_add.map { |ref| Push.new(repository_id: repo.id, ref: ref, pusher_id: User.ghost.id, pushed_at: DateTime.now, after: repo.heads.find(ref).target.oid) }
          RefPush.batch_log_pushes(batch)

          # prune any branches we think exist but git-system says does not
          to_delete = ref_pushes - git_branches
          to_delete.each do |ref|
            RefPush.where(repository: repo, ref: ref).delete_all
          end
        end

        timer.stop
        GitHub.logger.info("gh.repo.ref_push_backfill_job.finished", {
          "gh.repo.id": repo.id,
          "gh.repo.ref_push_backfill_job.duration": timer.elapsed_ms
        })
      end
    end
  end
end
