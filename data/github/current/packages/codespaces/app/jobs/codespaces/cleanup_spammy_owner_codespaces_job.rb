# typed: true
# frozen_string_literal: true

module Codespaces
  class CleanupSpammyOwnerCodespacesJob < CodespacesJob
    SPAMMY_USER_DEPROVISIONING_WAITING_PERIOD = 1.day

    locked_by timeout: SPAMMY_USER_DEPROVISIONING_WAITING_PERIOD, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(owner_id:, owner_type:)
      owner = User.find_by(id: owner_id)
      return unless owner.present?

      owner_suspected_of_fraud = owner.spammy? || owner.suspended?

      DeleteDependentCodespaces.call(owner_id: owner_id) if owner_suspected_of_fraud
    end
  end
end
