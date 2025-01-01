# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveOauthAppTokensJob < ApplicationJob
  queue_as :remove_oauth_app_tokens
  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ->(job) {
    job.arguments.first
  }

  resolve_tenant_context do |app_id, _, _, _|
    user = OauthApplication.find_by(id: app_id)&.user
    return unless user.present?
    user.is_a?(Organization) ? user.business : user.enterprise_managed_business
  end


  # Public: Remove all tokens for an OauthApplication
  #
  # app_id     - The application ID.
  # batch_size - The number of tokens to read from the database per batch.
  # duration   - The amount of time in seconds that each job instance can run
  #              for. After this time is elapsed, if there are still more
  #              batches to process, another job is enqueued to finish the work,
  #              and the current job terminates.
  # entry_point - Symobl: the originating action or code that requires
  #               permissions writes to occur.
  def perform(app_id, batch_size: 10_000, duration: 60, entry_point: nil)
    end_at = Time.current + duration

    application = OauthApplication.find_by(id: app_id)
    return false if application.nil?

    authorizations_revoked = 0

    loop do
      authorizations = application.authorizations.limit(batch_size)
      break if authorizations.none?

      authorizations.each do |authorization|
        destroyed = with_write do
          authorization.destroy_with_explanation(:oauth_application, entry_point: entry_point)
        end

        authorizations_revoked += 1 if destroyed
      end

      break if Time.current >= end_at
    end

    application.instrument :revoke_tokens, tokens_revoked: authorizations_revoked

    if application.authorizations.any?
      clear_lock
      # TODO: Pass entry point to job once method signature change has shipped.
      RemoveOauthAppTokensJob.perform_later(app_id, batch_size: batch_size, duration: duration)
    end

    true
  end
end
