# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class Organizations::DestroyFailedRepositoryInvitationsJob < BatchedJob
  queue_as :background_destroy

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |org_id|
    org = Organization.find_by(id: org_id)
    org&.business
  end

  BATCH_SIZE = 1000
  DELETE_BATCH_SIZE = 100

  sig { params(failed_ids: T::Array[Integer], args: T.untyped, options: T.untyped).void }
  def process_batch(failed_ids, *args, **options)
    failed_ids.each_slice(DELETE_BATCH_SIZE) do |batch|
      with_write do
        @org.failed_repo_invitations.where(id: batch).destroy_all
      end
    end
  end

  private

  def next_batch(org_id, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    @org = Organization.find_by(id: org_id)
    return unless @org

    @org.
      failed_repo_invitations.
      take(BATCH_SIZE).
      pluck(:id)
  end

  def next_batch_offset_item_id(*args, **options)
    # We don't have a way to order failed invitations efficiently, so we can't use this
    # field to paginate. We'll just override this field.
    0
  end
end
