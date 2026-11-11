# typed: strict
# frozen_string_literal: true

module Licensing
  class HydroSyncCustomerToLicensifyOnOrganizationRemoveJob < HydroSyncCustomerToLicensifyJob
    queue_as :hydro_sync_customer_to_licensify_on_organization_remove
  end
end
