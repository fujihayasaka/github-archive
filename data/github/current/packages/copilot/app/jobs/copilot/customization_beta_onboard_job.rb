# typed: strict
# frozen_string_literal: true

module Copilot
  class CustomizationBetaOnboardJob < ApplicationJob
    # TODO Remove?
    # Don't run more than one of this job at a time with the same args
    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

    queue_as :mailers
    retry_on_dirty_exit

    MAX_THROTTLE_RETRIES = 4
    MAX_BATCH_QUERIES = 3

    sig { params(user_logins: T::Array[::User], batch_size: T.nilable(Integer), choice: T.nilable(String)).void }
    def perform(user_logins, batch_size: nil, choice: nil)
      # intentionally no-op for now as this serves as a placeholder
    end
  end
end
