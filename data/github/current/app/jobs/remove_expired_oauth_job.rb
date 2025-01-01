# typed: true
# frozen_string_literal: true

# This job will remove all expired OauthAccesses.
class RemoveExpiredOauthJob < ApplicationJob
  queue_as :remove_expired_oauth
  retry_on_dirty_exit

  schedule interval: 1.minute
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is exempt from the tenant context requirement because
  # expired accesses should always be removed, regardless of the tenant.
  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100

  def enabled?; true; end

  def perform
    RefreshToken.inactive.where(refreshable_type: "OauthAccess").in_batches(of: BATCH_SIZE) do |relation|
      refreshable_ids = relation.pluck(:refreshable_id)
      # We need to use `to_a` here to force the query to be executed before
      # we establish the write connection below.
      accesses = OauthAccess.where(id: refreshable_ids).to_a

      ActiveRecord::Base.connected_to(role: :writing) do
        OauthAccess.throttle do
          accesses.map do |access|
            access.expire(entry_point: :remove_expired_oauth_job)
          end
        end

        # Cleanup refresh tokens that are missing their `refreshable` relation
        # and weren't cleaned up in the `OauthAccess#expire` loop.
        relation.destroy_all
      end
    end
  end
end
