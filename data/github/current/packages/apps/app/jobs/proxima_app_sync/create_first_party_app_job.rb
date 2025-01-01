# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  class CreateFirstPartyAppJob < ApplicationJob
    include CreateAppJobHelper

    queue_as :proxima_app_sync_create_first_party_app_job

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit

    sig { override.returns(String) }
    def party_type
      FIRST_PARTY_TYPE
    end
  end
end
