# typed: true
# frozen_string_literal: true

module CopilotModelRegistry
  module Twirp
    autoload :BaseClient, "copilot_model_registry/twirp/base_client"
    autoload :NullClient, "copilot_model_registry/twirp/null_client"
    autoload :ModelClient, "copilot_model_registry/twirp/model_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end

    sig { returns(ModelClient) }
    def self.model_registry_client
      @model_registry_client ||= ModelClient.new
    end
  end
end
