# typed: true
# frozen_string_literal: true

# This job migrates tag protections to rulesets without user interevention. It is idempotent and can be run multiple times.
# It is intended to be run by hand, and will not be run automatically.
class MigrateTagProtectionsJob < ApplicationJob
  queue_as :migrate_tag_protections
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Borrow the retryable exceptions from the orchestrations (used by RepositoryPushJob)
  # This job is idempotent, so we can retry on any error (ideally to avoid incorrect RefPush data)
  retry_on *Orchestration::RETRYABLE_ERRORS, wait: 30.seconds, attempts: 8

  use_primaries ApplicationRecord::Repositories

  # Ensure the job only runs one instance at a time
  # Requeueing will work because `last_migrated_repo_id` will be different each time
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  # It's a count of tag protections, not repos. Although most repos have only one or two protections.
  BATCH_SIZE = 100

  # last_migrated_repo_id lets us batch the work and pick up where we left off.
  sig do params(
    last_migrated_repo_id: Integer,
    only_repo_ids: T.nilable(T::Array[Integer]),
    dry_run: T::Boolean
  ).void
  end
  def perform(last_migrated_repo_id: 0, only_repo_ids: nil, dry_run: true)
    return if GitHub.flipper[:kill_migrate_tag_protections_job].enabled?

    start_time = Time.now.utc

    GitHub.dogstats.distribution_time("migrate_tag_protections_job.duration", tags: ["dry_run:#{dry_run}"]) do
      repo_id_batch = []

      if only_repo_ids
        repo_id_batch = only_repo_ids
      else
        # It's possible the last repo we fetch will be partial -- i.e., only include some of the tag protections for the repo.
        # That's ok, we are only interested in the repo id. The migration will retrieve the full list of tag protections.
        repo_id_batch = RepositoryTagProtectionState
          .order(repository_id: :asc)
          .where("repository_id > ? AND enabled = 1", last_migrated_repo_id)
          .limit(BATCH_SIZE)
          .pluck(:repository_id)
          .uniq
      end

      if repo_id_batch.any?
        repos = Repository.where(id: repo_id_batch).group_by(&:id)

        repo_id_batch.each do |repo_id|
          begin
            # We advance "last migrated" before migrating anything. If something blows up, we don't want to get stuck retrying
            # the same repo again and again. Log it to failbot, move on, and let the humans figure it out.
            last_migrated_repo_id = T.must(T.let(repo_id, Integer))

            # We might end up migrating some repos which are disabled, embargoed, or otherwise not accessible. That's fine,
            # because we don't know if they might be re-enabled in the future and if so we want to be migrated.
            repo = repos[repo_id]&.first

            if repo.nil? || repo.owner.nil?
              orphan_tag_prots = RepositoryTagProtectionState.where("repository_id = ? AND enabled = 1", repo_id)

              GitHub.logger.warn(
                "MigrateTagProtectionsJob: disabling tag protections for missing repo or owner",
                "gh.repo_id" => repo_id,
                "gh.dry_run" => dry_run,
                "gh.tag_prot.count" => orphan_tag_prots.count,
              )

              unless dry_run
                orphan_tag_prots.update_all(enabled: 0)
              end

              next
            end

            # Find an appropriate owner to "own" the newly created rulesets. Pick a repo admin.
            ruleset_owner = T.cast(User.find(repo.admin_ids), T::Array[User]).find { |u| !u.disabled } || User.ghost

            unless dry_run
              # Complete fidelity to existing tag protections is not possible in a single ruleset. Always create two rulesets.
              repo.import_tag_protections_to_rulesets(ruleset_owner, single_ruleset: false, is_auto_import: true)
            end

          rescue StandardError => ex
            Failbot.report(ex,
              "gh.repo_id": repo_id,
              "gh.ruleset_owner": ruleset_owner.try(:display_login),
              "gh.dry_run": dry_run,
            )
          end
        end

        if !only_repo_ids
          # Queue the next job to pick up where we left off. We do not worry too much about failures in the current batch.
          # This job will be run by hand, and we can go back and start a new run from zero to pick up anything missed.
          MigrateTagProtectionsJob.perform_later(last_migrated_repo_id:, dry_run:)
        end
      end

      GitHub.logger.info(
        "MigrateTagProtectionsJob: migrated",
        "gh.last_migrated_repo_id" => last_migrated_repo_id,
        "gh.repo_ids" => repo_id_batch,
        "gh.start_time" => start_time,
        "gh.dry_run" => dry_run,
      )
    end
  end
end
