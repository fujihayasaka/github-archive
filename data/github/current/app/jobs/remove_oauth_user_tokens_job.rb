# typed: true
# frozen_string_literal: true

# This job will remove all OAuth tokens for a User
class RemoveOauthUserTokensJob < ApplicationJob
  queue_as :remove_oauth_user_tokens
  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ->(job) { job.arguments.first(2).join(" ") }

  resolve_tenant_context do |user_id|
    User.find_by(id: user_id)&.enterprise_managed_business
  end

  # Public: Remove all OAuth tokens for a User.
  #
  # user_id    - The user ID.
  # kind       - The kind of tokens to remove (either :third_party or
  #              :personal_tokens).
  # batch_size - The number of tokens to remove in each batch.
  # duration   - The amount of time in seconds that each job instance can run.
  #              After this time is elapsed, if there are still more batches to
  #              process, another job is enqueued to finish the work, and the
  #              current job terminates.
  def perform(user_id, kind, batch_size: 100, duration: 60)
    user = User.find_by(id: user_id)
    return unless user

    end_at = Time.current + duration

    scope = user.authorizations_for_kind(kind)

    loop do
      # TODO: It may eventually be necessary to push entry point down from the
      # originating call site to gain better visibility into permissions
      # revocations.
      with_write do
        user.revoke_oauth_tokens(
          kind,
          should_throttle: true,
          limit: batch_size,
          entry_point: :unknown_remove_oauth_user_tokens_background_job
        )
      end

      break if scope.none? || (Time.current >= end_at)
    end

    if scope.any?
      clear_lock
      RemoveOauthUserTokensJob.perform_later(user_id, kind, batch_size: batch_size, duration: duration)
    end
  end
end
