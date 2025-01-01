# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class InstrumentBulkCredentialAuthorizationGrantsJob < ApplicationJob
  queue_as :instrument_bulk_credential_authorization_grants

  MAX_CONCURRENT_JOBS = 10
  LOCK_KEY = "instrument-bulk-credential-authorization-grants-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes

  retry_on_dirty_exit

  # Public: Perform instrumentation of bulk credential authorization grants.
  #
  # organization_ids - Array of Organization IDs
  # credential - Credential to instrument
  #
  # Returns nothing
  def perform(organization_ids:, credential_id:, credential_type:)
    return unless organization_ids.kind_of?(Array) && credential_id && credential_type
    return if organization_ids.empty?

    with_write do
      # Create an audit log entry for each organization
      # See Organization::CredentialAuthorization#instrument_grant for details on audit log creation
      Organization::CredentialAuthorization.where(organization_id: organization_ids, credential_id: credential_id, credential_type: credential_type).map(&:instrument_grant)
    end
  end
end
