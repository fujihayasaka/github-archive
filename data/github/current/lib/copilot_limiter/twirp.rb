# typed: true
# frozen_string_literal: true

module CopilotLimiter
  module Twirp
    autoload :BaseClient, "copilot_limiter/twirp/base_client"
    autoload :NullClient, "copilot_limiter/twirp/null_client"
    autoload :QuotaClient, "copilot_limiter/twirp/quota_client"
    autoload :InteractionsClient, "copilot_limiter/twirp/interactions_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end

    sig { returns(QuotaClient) }
    def self.quota_client
      @quota_client ||= QuotaClient.new
    end

    sig { returns(InteractionsClient) }
    def self.interactions_client
      @interactions_client ||= InteractionsClient.new
    end
  end
end
