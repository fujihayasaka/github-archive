# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RevokeOauthAccessesJob < ApplicationJob
  queue_as :revoke_oauth_accesses

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |user, _, _|
    user.enterprise_managed_business
  end

  def perform(user, explanation:, enqueued_at:, entry_point: nil)
    user.oauth_accesses.where("created_at < ?", enqueued_at).find_in_batches(batch_size: BATCH_SIZE) do |oauth_accesses|
      OauthAccess.throttle do
        oauth_accesses.each do |oauth_access|
          with_write do
            # We want to destroy each one individually so that we get
            # the proper audit logging for security.
            oauth_access.destroy_with_explanation(explanation, entry_point: entry_point)
          end
        end
      end
    end
  end
end
