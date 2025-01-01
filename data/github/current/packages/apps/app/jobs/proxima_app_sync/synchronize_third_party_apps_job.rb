# typed: true
# frozen_string_literal: true

# This job kicks off syncing 1st party apps from dotcom
# to a Proxima stamp
module ProximaAppSync
  class SynchronizeThirdPartyAppsJob < ApplicationJob
    extend T::Helpers

    queue_as :proxima_third_party_app_synchronization

    schedule interval: 5.minutes, condition: -> { GitHub.multi_tenant_enterprise? }

    exempt_from_tenant_context_requirement
    retry_on_dirty_exit

    sig { void }
    def perform
      SynchronizeJobOrchestrator.orchestrate(ProximaAppHelper::THIRD_PARTY_TYPE)
    end
  end
end
