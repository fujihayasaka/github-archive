# typed: true
# frozen_string_literal: true

class DestroyMobileAuthDeviceKeysJob < ApplicationJob
  queue_as :authnd_destroy_device_auth_keys

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RetryableError = Class.new(RuntimeError)
  retry_on RetryableError, wait: :polynomially_longer, attempts: 3

  REASON = "destroy_mobile_auth_device_keys_job"

  # Discard the job if the user does not exist or is deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(user, id, application, access_ids = [])
    # requeue the job if any of the accesses haven't been destroyed
    if user.oauth_accesses.where(application: application, id: access_ids).exists?
      GitHub.dogstats.increment("destroy_mobile_auth_device_keys_job.retry", tags: ["event:accesses_not_destroyed"])
      raise RetryableError
    end

    android = Apps::Internal.oauth_application(:android_mobile)
    ios = Apps::Internal.oauth_application(:ios_mobile)
    other_authorizations = T.cast(nil, T.untyped)

    ActiveRecord::Base.connected_to(role: :writing) do
      other_authorizations = user.oauth_authorizations.where(application: [android, ios]).where.not(id: id)
    end

    # we can't bulk delete the auth keys if there are any existing github mobile oauth authorizations
    if other_authorizations.any?
      access_ids.each do |id|
        result = user.revoke_mobile_device_auth_key(user, id, REASON)
        if result == :RESULT_FAILED_GENERIC
          GitHub.dogstats.increment("destroy_mobile_auth_device_keys_job.retry", tags: ["event:bulk_revoke_failed"])
          raise RetryableError
        end
      end
    else
      # we can bulk revoke keys
      result = user.revoke_mobile_device_auth_keys(user, REASON)
      if result == :RESULT_FAILED_GENERIC
        GitHub.dogstats.increment("destroy_mobile_auth_device_keys_job.retry", tags: ["event:revoke_failed"])
        raise RetryableError
      end
    end

    GitHub.dogstats.distribution("destroy_mobile_auth_device_keys_job.keys", access_ids.count, tags: ["application:#{application.name}", "other_authorizations:#{other_authorizations.any?}"])
  end
end
