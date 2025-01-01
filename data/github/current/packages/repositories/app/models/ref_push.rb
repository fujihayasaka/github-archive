# typed: strict
# frozen_string_literal: true

class RefPush < ApplicationRecord::Domain::Repositories
  extend T::Sig
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  attribute :ref, StringFromBinary.new

  belongs_to  :repository
  delete_in_background_with :repository
  belongs_to  :pusher, class_name: "User"

  sig { params(push: Push).returns(T.nilable(RefPush)) }
  def self.from_push(push)
    return unless valid_push?(push)
    RefPush.new(
    {
      repository_id: push.repository_id,
      pusher_id: push.pusher_id,
      ref: push.ref,
      after: push.after,
      pushed_at: push.pushed_at
    })
  end

  sig { params(push: Push).returns(T::Boolean) }
  def self.valid_push?(push)
    push.repository_id.present? && push.pusher_id.present? && push.ref.present? && push.after.present? && push.pushed_at.present?
  end

  sig { params(push: Push, is_backfill_job: T::Boolean).void }
  def self.log_push(push, is_backfill_job: false)
    return if push.nil?

    if push.repository&.feature_enabled?(:ref_push_delete)
      # Check to see if a delete entry exists for a pusher with a later `pushed_at`
      # If so, ignore this push
      last_delete = Repositories::Redis.get(key: delete_redis_key(T.must(push.repository_id), push.ref), fallback: nil)
      if last_delete.present? && push.pushed_at.to_f < last_delete.to_f
        GitHub.dogstats.increment("gh.ref_push.push_out_of_order_ignored", tags: ["backfill:#{is_backfill_job}"])
        return
      end

      if push.deleted?
        GitHub.dogstats.increment("gh.ref_push.ref_deleted", tags: ["backfill:#{is_backfill_job}", "redis:true"])
        # Set the delete time for this ref so other pushes can be ignored if they come in out of order
        unless is_backfill_job
          Repositories::Redis.set(key: delete_redis_key(T.must(push.repository_id), push.ref), value: "#{push.pushed_at.to_f}", px: 1.hour.in_milliseconds)
        end

        # Delete all pushes for this ref that are older than the current delete
        # Also schedule a job to delete matching ref pushes from the database if they race the Redis check
        RefPush.where(repository_id: push.repository_id, ref: push.ref, pushed_at: ..push.pushed_at).delete_all
        if push.repository&.feature_enabled?(:ref_push_delete_job)
          RefPushDeleteJob.set(wait: 5.minutes).perform_later(push.repository_id, push.ref, push.pushed_at)
        end
        return
      end
    else
      if push.deleted?
        RefPush.where(repository_id: push.repository_id, ref: push.ref, pushed_at: ..push.pushed_at).delete_all
        GitHub.dogstats.increment("gh.ref_push.ref_deleted", tags: ["backfill:#{is_backfill_job}"])
        return
      end
    end

    RefPush.upsert(
      {
        repository_id: push.repository_id,
        pusher_id: push.pusher_id,
        ref: push.ref,
        after: push.after,
        pushed_at: push.pushed_at
      },
      on_duplicate: Arel.sql("
        after = IF(VALUES(pushed_at) > pushed_at, VALUES(after), after),
        pushed_at = IF(VALUES(pushed_at) > pushed_at, VALUES(pushed_at), pushed_at)
      ")
    )
  end

  sig { params(repo_id: Integer, ref: String).returns(String) }
  def self.delete_redis_key(repo_id, ref)
    "ref-push-delete/#{repo_id}/#{ref}"
  end
  private_class_method :delete_redis_key

  sig { params(pushes: T::Array[Push]).void }
  def self.batch_log_pushes(pushes)
    pushes.each do |push|
      ApplicationRecord::Domain::Repositories.throttle do
        log_push(push, is_backfill_job: true)
      end
    end
  end
end
