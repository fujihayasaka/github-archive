# typed: true
# frozen_string_literal: true

module Codespaces
  class DeleteDependentNeverAvailableCodespacesJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(owner_id:)
      DeleteDependentNeverAvailableCodespaces.call(owner_id: owner_id)
    end
  end
end
