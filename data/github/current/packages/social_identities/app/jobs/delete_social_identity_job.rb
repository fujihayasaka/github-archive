# typed: true
# frozen_string_literal: true

class DeleteSocialIdentityJob < ApplicationJob
  queue_as :delete_social_identity_job
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RetryableError = Class.new(RuntimeError)
  retry_on RetryableError, wait: :polynomially_longer, attempts: 3

  def perform(user_id, email_id)
    return unless FeatureFlag.vexi.enabled?(:social_cleanup_job, default: false)
    return unless user_id

    begin
      if email_id.nil?
        # user has been destroyed, delete all social identities
        delete_response = SocialIdentities.domain.delete_social_identities(user_id)
        if delete_response.result == :RESULT_SUCCESS
          GitHub.dogstats.increment("delete_social_identity_job.success", tags: ["event:delete_all_orphaned_records_success"])
        elsif delete_response.result == :RESULT_FAILED_NOT_FOUND
          GitHub.dogstats.increment("delete_social_identity_job.success", tags: ["event:no_records_to_delete"])
        else
          GitHub.dogstats.increment("delete_social_identity_job.retry", tags: ["event:delete_failed", "response:#{delete_response.result}"])
          raise RetryableError
        end
      else
        # Attempt to delete the specific social identity associated with the email_id
        response = SocialIdentities.domain.delete_social_identity(email_id)
        if response.result == :RESULT_SUCCESS
          GitHub.dogstats.increment("delete_social_identity_job.success", tags: ["event:delete_success"])
        elsif response.result == :RESULT_FAILED_NOT_FOUND
          GitHub.dogstats.increment("delete_social_identity_job.success", tags: ["event:no_record_to_delete"])
        else
          GitHub.dogstats.increment("delete_social_identity_job.retry", tags: ["event:delete_failed", "response:#{response.result}"])
          raise RetryableError
        end
      end
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      # Report the error to Sentry
      Failbot.report!(err)
      GitHub.dogstats.increment("delete_social_identity_job.failure", tags: ["reason:client_raised"])
      raise RetryableError
    end
  end
end
