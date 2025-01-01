# typed: true
# frozen_string_literal: true

class RefPushReactiveCleanupJob < ApplicationJob
  queue_as :ref_push_delete
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Ensure the job only runs once per repo and set of refs at a time
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  use_primaries ApplicationRecord::Repositories

  def perform(repository_id, refs)
    GitHub.dogstats.distribution_time "ref_push_reactive_cleanup.duration" do
      repository = Repositories.domain.active_by_id(repository_id)
      return unless repository&.feature_enabled?(:ref_push_reactive_cleanup)

      deleted = 0
      deleted_ref_pushes = 0
      refs.each do |ref|
        last_push = find_last_push(repository, ref)
        if last_push&.deleted?
          deleted_ref_pushes += RefPush.where(repository:, ref:, pushed_at: ..last_push.pushed_at).delete_all
          deleted += 1
        end
      end
      GitHub.dogstats.count("gh.ref_push_reactive_delete.ref_deleted", deleted)
      GitHub.dogstats.count("gh.ref_push_reactive_delete.ref_push_deleted", deleted_ref_pushes)
    end
  end

  # A more complicated way to find the last push to account for pushes with the same pushed_at
  sig { params(repository: Repositories::IRepository, ref: String).returns(T.nilable(Repositories::Push)) }
  private def find_last_push(repository, ref)
    # Find the last 5 pushes to the ref. 5 is an arbitrary number, but should be enough to cover most cases
    last_pushes = Repositories.domain.pushes.by_repository_id_and_refs(repository_id: T.must(repository.id), refs: [ref], limit: 5)

    # If there is only one (or 0) push, return it
    return last_pushes.first if last_pushes.size <= 1

    latest = T.must(last_pushes.first)
    same_pushed_at = last_pushes.select { |push| push.pushed_at == latest.pushed_at }

    # If there are no other pushes with the same pushed_at, return the latest
    return latest if same_pushed_at.size <= 1

    GitHub.dogstats.increment("gh.ref_push_reactive_cleanup_sha.same_pushed_at", tags: ["count:#{same_pushed_at.size}"]) # cardinality is fine since count can only be 2-5

    # If there are multiple pushes with the same pushed_at, we need to find the latest one by SHA
    # Find the push whose after SHA is not the before SHA of any other push
    pushes_by_before = same_pushed_at.index_by(&:before)
    latest_by_sha = same_pushed_at.reject { |push| pushes_by_before.include?(push.after) }.max_by(&:id)

    if latest_by_sha
      latest_by_sha
    elsif repository.feature_enabled?(:ref_push_reactive_cleanup_git_exists)
      # `lastest_by_sha` being nil indicates a loop (aaaaa -> 00000, 00000 -> aaaaa)
      # It is impossible to determine which is the latest without walking back the chain further, which could be an unbounded operation
      # In this case, check git to see if the ref exists and use that to determine which push is the latest
      if T.cast(repository, Repository).heads.exist?(ref) # rubocop:disable GitHub/AvoidCast:
        GitHub.dogstats.increment("gh.ref_push_reactive_cleanup_sha.same_pushed_at_git_check", tags: ["exists:true"])
        same_pushed_at.reject(&:deleted?).max_by(&:id)
      else
        GitHub.dogstats.increment("gh.ref_push_reactive_cleanup_sha.same_pushed_at_git_check", tags: ["exists:false"])
        same_pushed_at.filter(&:deleted?).max_by(&:id)
      end
    else
      latest
    end
  end
end
