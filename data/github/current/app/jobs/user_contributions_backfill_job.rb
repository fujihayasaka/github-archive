# typed: true
# frozen_string_literal: true

class UserContributionsBackfillJob < ApplicationJob
  queue_as :user_contributions_backfill

  around_perform :use_mysql1_replica

  locked_by timeout: 1.hour, key: ->(job) {
    repo_ids = job.arguments[0]
    user_id = job.arguments[1]
    [repo_ids.first, user_id].join(":")
  }

  # If the job is still running after 60 seconds, it should requeue itself with the remanining unprocessed
  # repo IDs.
  MAX_RUNTIME = 60

  # Does the job have runtime remaining or has it hit the max runtime?
  def self.runtime_remaining?(started:)
    (Time.now - started) < MAX_RUNTIME
  end

  resolve_tenant_context do |_, user_id|
    user = User.find_by(id: user_id)
    return unless user.present?
    Business.find_by(id: user.business_id)
  end

  # This job uses repo_ids to maintain its own work queue: it will attempt
  # to process the first repo in the `repo_ids` list, and then requeues the
  # remainder.
  def perform(repo_ids, user_id, opts = {})
    queue_remainder = T.let(true, T::Boolean)
    started = Time.now
    # Clone to avoid confusing hash lock key generation
    repo_ids = repo_ids.dup

    while repo_ids.any? do
      begin
        repo_id = repo_ids.shift

        lock_key = [repo_id, user_id].join(":")
        restraint.lock!(lock_key, 1, 1.hour) do
          user = T.let(nil, T.nilable(User))
          repo = T.let(nil, T.nilable(Repository))
          ActiveRecord::Base.connected_to(role: :reading) do
            repo = Repository.find_by(id: repo_id)
            user = User.find_by(id: user_id)
          end

          if repo && user
            Failbot.push repo_id: repo.id
            Failbot.push user_id: user.id
            with_write do
              CommitContribution.backfill_user!(repo, user)
            end
          end
        end
      rescue GitHub::Restraint::UnableToLock
        # Ignore and move on to the next repo
      rescue Freno::Throttler::Error
        # Automatic retry will requeue this job when this error occurs, and we
        # don't want to queue both this job and the subsequent repos at the same
        # time. Just allow this to be retried and don't queue anything else.

        queue_remainder = false
        raise
      end

      # Avoid batching if this is a retry in case batching is causing throttling.
      break if executions > 1

      break unless self.class.runtime_remaining?(started: started)
    end
  ensure
    if queue_remainder && repo_ids.any?
      UserContributionsBackfillJob.perform_later(repo_ids, user_id)
    end
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
