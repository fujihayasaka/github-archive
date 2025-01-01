# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

class RemoveIntegrationTokensJob < ApplicationJob
  queue_as :remove_integration_tokens

  locked_by timeout: 10.minutes, key: ->(job) { job.arguments.first.id }

  # Discard the job if the integration is deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit

  # Public: Destroy all user tokens for an integration (i.e., a GitHub App).
  #
  # integration - The Integration whose user tokens will be destroyed.
  # duration    - The amount of time in seconds that each job instance can run.
  #               After this time is elapsed, if there are still more tokens to
  #               destroy, another job is enqueued to finish the work, and the
  #               current job terminates.
  # entry_point - Symbol. Unique identifier used for tracing writes to the
  #               permissions cluster.
  def perform(integration, duration: 60, created_before: nil, entry_point: nil)
    created_before = if created_before.present?
      Time.iso8601(created_before)
    else
      Time.now
    end

    scope = OauthAuthorization.where(application: integration)
      .where("created_at < ?", created_before)

    iterator = GitHub::QueryBatching::ScopeIterator.new(scope, batch_size: 100).pluck(:id)

    authorizations_count = 0
    authorizations_revoked = 0

    GitHub::SafeTimer.timeout(duration) do |timer|
      GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
        authorization_ids = rows.flatten
        Integration.throttle do
          authorizations = OauthAuthorization.where(id: authorization_ids)
          authorizations_count += authorizations.size

          authorizations.each do |authorization|
            destroyed = with_write do
              authorization.destroy_with_explanation(:integration, entry_point: entry_point)
            end

            authorizations_revoked += 1 if destroyed

            break if timer.expired?
          end
        end
      end
    end

    integration.instrument :revoke_tokens, tokens_revoked: authorizations_revoked
    return if authorizations_count == 0

    clear_lock
    RemoveIntegrationTokensJob.perform_later(integration, duration: duration, created_before: created_before.iso8601, entry_point: entry_point)
  end
end
