# typed: strict
# frozen_string_literal: true

module Licensing
  class HydroSyncCustomerToLicensifyOnOrganizationTransferJob < HydroSyncCustomerToLicensifyJob
    queue_as :hydro_sync_customer_to_licensify_on_organization_transfer

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :transfer_failed

    protected

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def extract_message_attributes(message)
      # failed_at is a protobuf timestamp - if present (not nil), the transfer failed
      @transfer_failed = T.let(!message[:failed_at].nil?, T.nilable(T::Boolean))
    end

    # Only process successful transfers (where failed_at is nil)
    sig { override.returns(T::Boolean) }
    def should_process?
      !@transfer_failed
    end
  end
end
