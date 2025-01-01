# typed: strict
# frozen_string_literal: true

module ProximaAppSync
  class CreateThirdPartyAppJob < ApplicationJob
    include CreateAppJobHelper
    extend T::Sig

    queue_as :proxima_app_sync_create_third_party_app_job

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit

    sig { override.returns(String) }
    def party_type
      THIRD_PARTY_TYPE
    end
  end
end
