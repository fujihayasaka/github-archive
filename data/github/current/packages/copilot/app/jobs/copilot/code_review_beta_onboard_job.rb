# typed: strict
# frozen_string_literal: true

module Copilot
  class CodeReviewBetaOnboardJob < ApplicationJob
    # TODO: REMOVE THIS JOB?
    MAX_THROTTLE_RETRIES = 4
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    queue_as :mailers
    retry_on_dirty_exit

    # When onboarding a business, onboard_entity will be a EarlyAccessMembership. Otherwise, it will be an array of logins
    sig { params(onboard_entity: T.any(EarlyAccessMembership, T::Array[String]), batch_size: T.nilable(Integer), actor: T.nilable(::User)).void }
    def perform(onboard_entity, batch_size: nil, actor: nil)
      # keeping the void method till we decide to remove CCR Beta from stafftools UI
    end
  end
end
