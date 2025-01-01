# typed: strict
# frozen_string_literal: true

class Copilot::UpdateUserSettingsCacheJob < CopilotJob

  queue_as :copilot_update_org_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/lockable-jobs/?reloaded=true#hash-locks
  # the semantics of this job are that values are pulled from the database, so we only need one enqueued between the first event
  # and when the job is executed. if the values have changed during execution we will re-enqueue the job at the end with the same
  # arguments.
  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  sig { params(org_id: Integer, start: Integer, finish: Integer).void }
  def perform(org_id, start, finish)
    # take a hash of the configuration settings at the start of the run to catch race conditions
    start_hash = configuration_hash(org_id)
    Copilot::Seat.where(organization_id: org_id)
    .includes(:assigned_user)
    .find_each(start: start, finish: finish) do |seat|
      # TODO skip if it matches the user hash
      with_write do
        Copilot::User.new(T.must(seat.assigned_user)).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      end
    end

    # if the value of the hash has changed while we were running this job, enqueue it again
    if start_hash != configuration_hash(org_id)
      GitHub.dogstats.increment("copilot.update_user_settings_cache_job.hash_changed")
      Copilot::UpdateUserSettingsCacheJob.perform_later(org_id, start, finish)
    end
  end

  sig { params(org_id: Integer).returns(T.nilable(Integer)) }
  def configuration_hash(org_id)
    Copilot::Configuration.find_by(configurable_id: org_id, configurable_type: "Organization")
    # ignore timestamp values when calculating the hash since we only care about the configuration values
    &.attributes&.except("created_at", "updated_at")
    &.hash
  end
end
