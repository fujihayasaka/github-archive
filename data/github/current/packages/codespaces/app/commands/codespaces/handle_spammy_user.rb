# typed: true
# frozen_string_literal: true

module Codespaces
  class HandleSpammyUser < Command
    attr_reader :user_id, :user_type

    def initialize(user_id:, user_type:)
      @user_id = user_id
      @user_type = user_type
    end

    def perform
      Codespaces::SuspendDependentCodespacesJob.perform_later(owner_id: user_id)
      Codespaces::DeleteDependentNeverAvailableCodespacesJob.perform_later(owner_id: user_id)

      Codespaces::CleanupSpammyOwnerCodespacesJob.perform_after_waiting_period(
        waiting_period: Codespaces::CleanupSpammyOwnerCodespacesJob::SPAMMY_USER_DEPROVISIONING_WAITING_PERIOD,
        owner_id: user_id,
        owner_type: user_type
      )
    end
  end
end
