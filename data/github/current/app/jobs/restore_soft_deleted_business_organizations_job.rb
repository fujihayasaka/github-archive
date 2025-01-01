# typed: true
# frozen_string_literal: true

class RestoreSoftDeletedBusinessOrganizationsJob < ApplicationJob
  extend T::Sig

  queue_as :restore_soft_deleted_business_orgs

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 100

  sig { params(business: Business, unix_timestamp: Integer).void }
  def perform(business, unix_timestamp)
    # We only want to restore the organizations that were soft-deleted at the time of the business soft-delete
    business_soft_deleted_at = Time.at(unix_timestamp)
    business.soft_deleted_organizations.in_batches(of: BATCH_SIZE) do |batch|
      with_write { batch.each { |org| org.mark_not_deleted if org.soft_deleted_at >= business_soft_deleted_at } }
    end
  end
end
