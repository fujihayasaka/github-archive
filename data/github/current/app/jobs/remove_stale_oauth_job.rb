# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job looks for all unused or stale (not recently used) OAuth related
# records that should be deleted.

# We first remove all stale OauthAccesses upfront via a mass delete. We're
# not worried about logging for accesses since they are meant to be created
# and destroyed as needed. Since these accesses haven't been used in a long
# time there shouldn't be any forensic need for logs.
#
# After deleting all stale accesses we then process any authorizations that
# are eligible to be destroyed. It's important we destroy authorizations so
# that we get the dependent destroys as well as the associated logging.
class RemoveStaleOauthJob < ApplicationJob
  queue_as :remove_stale_oauth
  locked_by key: ->(_job) { DEFAULT_LOCK_KEY }, timeout: 1.day
  schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit

  # This job is exempt from the tenant context requirement because
  # stale accesses should always be removed, regardless of the tenant.
  exempt_from_tenant_context_requirement

  REMOVE_AFTER_DURATION = 1.year

  REMOVAL_CONDITIONS = <<-SQL
    (accessed_at IS NULL AND created_at < :after) or
    (accessed_at < :after)
  SQL

  # Accesses shouldn't remove PATs
  IS_APPLICATION = <<-SQL
    is_application = 1
  SQL

  # Public: Remove all stale OAuth accesses and authorizations.
  #
  # batch_size - The number of records to remove in each batch.
  # duration   - The amount of time in seconds that each job instance can run.
  #              After this time is elapsed, if there are still more batches to
  #              process, another job is enqueued to finish the work, and the
  #              current job terminates.
  # entry_point - Symbol. The unique call site initiating this background job.
  #               Used to track writes to the permissions cluster.
  #
  # Returns nothing.
  def perform(batch_size: 100, duration: 60, entry_point: nil)
    end_at = Time.current + duration

    status = remove_accesses(batch_size: batch_size, end_at: end_at, entry_point:)
    return requeue(batch_size: batch_size, duration: duration) if status == :timeout

    status = remove_authorizations(batch_size: batch_size, end_at: end_at, entry_point: entry_point)
    requeue(batch_size: batch_size, duration: duration) if status == :timeout
  end

  private

  # Returns :completed if all stale accesses were removed. Returns :timeout if
  #   the given end_at time was reached before all stale accesses could be
  #   removed.
  def remove_accesses(batch_size:, end_at:, entry_point:)
    mobile_device_manager = nil
    if cleanup_mobile_device_keys?
      mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
    end

    loop do
      oauth_accesses = OauthAccess.where(REMOVAL_CONDITIONS, {
        after: REMOVE_AFTER_DURATION.ago,
      }).where(IS_APPLICATION).limit(batch_size)

      deleted_accesses = OauthAccess.throttle_with_retry(max_retry_count: 8) do
        size = oauth_accesses.count

        access_ids = []
        oauth_accesses.each do |access|
          with_write { access.destroy_with_explanation(:stale, entry_point: entry_point, skip_destroy_authorization: true) }
          access_ids << access.id
        end

        if mobile_device_manager
          # this is a best effort to cleanup any device keys from
          # authnd that belong to the oauth accesses we just deleted
          begin
            response = mobile_device_manager.revoke_device_keys_by_oauth_access_ids(access_ids)
            GitHub.dogstats.count("remove_stale_oauth_job.revoke_device_keys_by_oauth_access_ids", 1, tags: ["result:#{response.result}"])
            GitHub.dogstats.count("remove_stale_oauth_job.revoke_device_keys_by_oauth_access_ids.batch_size", size, tags: ["result:#{response.result}"])
          rescue ::Authnd::Proto::Error, Faraday::Error => err
            GitHub.dogstats.count("remove_stale_oauth_job.revoke_device_keys_by_oauth_access_ids", 1, tags: ["result:client_raised"])
            Failbot.report!(err)
          end
        end

        size
      end
      GitHub.dogstats.count("account_security.oauth_access", deleted_accesses, tags: ["action:destroy", "explanation:stale"])


      break(:completed) if deleted_accesses < batch_size

      break(:timeout) if Time.current >= end_at
    end
  end

  # Returns :completed if all stale authorizations were removed. Returns :timeout
  #   if the given end_at time was reached before all stale authorizations
  #   could be removed.
  def remove_authorizations(batch_size:, end_at:, entry_point: nil)
    loop do
      oauth_authorizations = OauthAuthorization.where(REMOVAL_CONDITIONS, {
        after: REMOVE_AFTER_DURATION.ago,
      }).limit(batch_size)

      destroyed_count = 0
      OauthAuthorization.throttle_with_retry(max_retry_count: 8) do
        oauth_authorizations.each do |authorization|
          GitHub.audit.inline do
            with_write do
              authorization.destroy_with_explanation(:stale, entry_point: entry_point)
              destroyed_count += 1
            end
          end

          return(:timeout) if Time.current >= end_at
        end
      end

      break(:completed) if destroyed_count < batch_size
    end
  end

  def requeue(**args)
    clear_lock
    self.class.perform_later(**args)
  end

  def cleanup_mobile_device_keys?
    return false if GitHub.single_or_multi_tenant_enterprise?
    GitHub.flipper[:remove_stale_oauth_job_revoke_device_auth_keys].enabled?
  end
end
