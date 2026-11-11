# typed: true
# frozen_string_literal: true

module Codespaces
  class CopilotWorkspaceBillingMessageHandlerResult
    attr_reader :payload

    def initialize(payload)
      @payload = payload
    end

    def publish
      # All we do is enqueue a job that creates the usage record from this payload because we don't want database writes
      # to be a factor in the billing system's performance.
      Codespaces::CreateUsageRecordJob.perform_later(payload)
    end
  end
end
