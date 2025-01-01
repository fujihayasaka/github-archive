# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  class UpdateFirstPartyAppJob < ApplicationJob
    include UpdateAppJobHelper
    extend T::Sig

    queue_as :proxima_app_sync_update_first_party_app_job

    exempt_from_tenant_context_requirement

    sig { override.returns(String) }
    def party_type
      FIRST_PARTY_TYPE
    end
  end
end
