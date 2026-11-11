# typed: strict
# frozen_string_literal: true

module Licensing
  class HydroSyncCustomerToLicensifyOnOrganizationAddJob < HydroSyncCustomerToLicensifyJob
    queue_as :hydro_sync_customer_to_licensify_on_organization_add

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :new_organization

    protected

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def extract_message_attributes(message)
      @new_organization = T.let(message[:new_organization], T.nilable(T::Boolean))
    end

    # Only process if not a newly created organization
    sig { override.returns(T::Boolean) }
    def should_process?
      !@new_organization
    end
  end
end
