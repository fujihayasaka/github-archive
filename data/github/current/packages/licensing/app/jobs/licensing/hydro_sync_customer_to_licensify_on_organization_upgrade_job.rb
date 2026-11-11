# typed: strict
# frozen_string_literal: true

module Licensing
  class HydroSyncCustomerToLicensifyOnOrganizationUpgradeJob < HydroSyncCustomerToLicensifyJob
    queue_as :hydro_sync_customer_to_licensify_on_organization_upgrade

    # Valid upgrade statuses that should trigger a customer update
    UPGRADE_STATUSES = T.let([:PURCHASE_UPGRADED, :DIRECT_UPGRADED].freeze, T::Array[Symbol])

    sig { returns(T.nilable(Symbol)) }
    attr_reader :status

    protected

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def extract_message_attributes(message)
      @status = T.let(message[:status], T.nilable(Symbol))
    end

    # Only process if status is PURCHASE_UPGRADED or DIRECT_UPGRADED
    sig { override.returns(T::Boolean) }
    def should_process?
      UPGRADE_STATUSES.include?(@status)
    end
  end
end
