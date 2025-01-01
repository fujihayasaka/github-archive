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
    OauthAccessTokens.domain.tokens_created_before(user.id, enqueued_at, batch_size: BATCH_SIZE).each do |oauth_accesses|
      ids = oauth_accesses.map(&:id)
      OauthAccessTokens.domain.destroy_by_ids(ids, explanation, entry_point: entry_point)
    end
  end
end
