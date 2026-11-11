# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendDependentCodespacesJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    retry_on Codespaces::Client::BadResponseError, wait: :polynomially_longer, attempts: 5 # will retry 4 times over 6 minutes
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(owner_id:)
      codespaces = Codespace.where(owner_id: owner_id).or(Codespace.where(billable_owner_id: owner_id))

      codespaces.each do |codespace|
        next unless codespace.suspendable?
        CodespacesSuspendEnvironmentJob.perform_later(codespace: codespace)
      end
    end
  end
end
